import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/account_controller.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/account/capability_controller.dart';
import 'package:koi_mobile/account/destinations.dart';
import 'package:koi_mobile/app/root_router.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/platform/platform_client.dart';

import '../support/mob1_fakes.dart';

const _anon = KoiUser(uid: 'u1', isAnonymous: true);

class _Transport implements PlatformTransport {
  _Transport(this.replies);
  final List<PlatformHttpResponse> replies;
  final tokens = <String>[];

  @override
  Future<PlatformHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    tokens.add(headers['Authorization']!);
    return replies.removeAt(0);
  }
}

void main() {
  group('MOB1-01 capabilities come only from the backend response', () {
    // MOB-2: fixtures follow contract v0.5.1 CapabilitiesDTO (no role, no
    // relationship name; patient = an active relationship).
    Map<String, Object?> caps({
      String uid = 'u1',
      String state = 'registered',
      bool directory = true,
      bool professional = false,
      List<Map<String, Object?>> relationships = const [],
    }) => {
      'contract_version': '0.5.0',
      'uid': uid,
      'account_state': state,
      'authorization_revision': 1,
      'capabilities': {
        'companion_account_sync': directory,
        'expert_directory': directory,
        'professional_workspace': professional,
        'create_organization': false,
      },
      'professional_organization_ids': const <String>[],
      'active_patient_relationships': relationships,
    };
    const rel = {
      'relationship_id': 'r',
      'organization_id': 'o',
      'psychologist_uid': 'psy',
    };
    test('role + flags; a missing flag is false', () {
      final c = KoiCapabilities.fromJson(caps(relationships: [rel]), uid: 'u1');
      expect(c.isPatient, isTrue);
      expect(c.canDiscoverExperts, isTrue);
      expect(c.relationship!.psychologistUid, 'psy');
      expect(c.relationship!.organizationId, 'o');
      final noFlag = KoiCapabilities.fromJson(
        caps(directory: false),
        uid: 'u1',
      );
      expect(noFlag.canDiscoverExperts, isFalse, reason: 'flag false');
      expect(noFlag.hasCareArea, isFalse);
    });
    test('a response for another uid is rejected', () {
      expect(
        () => KoiCapabilities.fromJson(caps(uid: 'u2'), uid: 'u1'),
        throwsFormatException,
      );
      expect(
        () => KoiCapabilities.fromJson({
          ...caps(),
          'contract_version': '1.0.0',
        }, uid: 'u1'),
        throwsFormatException,
        reason: 'unknown contract version',
      );
    });
    test('not registered → no privileges; no relationship → not patient', () {
      for (final state in ['unregistered', 'suspended', 'closed', 'other']) {
        final c = KoiCapabilities.fromJson(
          caps(state: state, relationships: [rel]),
          uid: 'u1',
        );
        expect(c.role, KoiRole.anonymous, reason: state);
        expect(c.hasCareArea, isFalse, reason: state);
      }
      final ended = KoiCapabilities.fromJson(caps(), uid: 'u1');
      expect(ended.isPatient, isFalse);
      expect(ended.canUseQuestionnaires, isFalse);
      expect(
        KoiCapabilities.fromJson(caps(professional: true), uid: 'u1').role,
        KoiRole.psychologist,
      );
    });
  });

  group(
    'MOB1-02 Firebase isAnonymous=true never gets registered privileges',
    () {
      test(
        'never fetched, effective = none even if the source says patient',
        () async {
          final auth = AccountFakeAuth(fakeUser: _anon);
          final source = ScriptedCapabilitiesSource({'u1': patientCaps});
          final c = CapabilityController(auth: auth, source: source);
          await pumpEventQueue();
          expect(c.status, CapabilityStatus.anonymous);
          expect(source.fetches, 0);
          expect(c.effective.hasCareArea, isFalse);
          auth.fireTokenChange();
          c.appResumed();
          c.onForbidden();
          await pumpEventQueue();
          expect(source.fetches, 0);
        },
      );
    },
  );

  group('MOB1-03 default-deny while loading', () {
    test(
      'a registered user has NO privileges until the fetch completes',
      () async {
        final auth = AccountFakeAuth(
          fakeUser: AccountFakeAuth.registered('p1', 'p@x'),
        );
        final source = ScriptedCapabilitiesSource({'p1': patientCaps})
          ..gate = Completer<void>();
        final c = CapabilityController(auth: auth, source: source);
        await pumpEventQueue();
        expect(c.status, CapabilityStatus.loading);
        expect(c.effective.canUseQuestionnaires, isFalse);
        expect(
          resolveRootRoute(
            restored: true,
            loading: false,
            signedIn: true,
            onboardingComplete: true,
            registered: true,
            capabilities: c.status,
          ),
          RootRoute.capabilityCheck,
        );
        source.gate!.complete();
        await pumpEventQueue();
        expect(c.status, CapabilityStatus.ready);
        expect(c.effective.canUseQuestionnaires, isTrue);
      },
    );
    test('failure → unavailable, still no privileges', () async {
      final auth = AccountFakeAuth(
        fakeUser: AccountFakeAuth.registered('p1', 'p@x'),
      );
      final source = ScriptedCapabilitiesSource({'p1': patientCaps})
        ..error = const PlatformException(PlatformErrorCode.network);
      final c = CapabilityController(auth: auth, source: source);
      await pumpEventQueue();
      expect(c.status, CapabilityStatus.unavailable);
      expect(c.error, PlatformErrorCode.network);
      expect(c.effective.hasCareArea, isFalse);
    });
  });

  group(
    'MOB1-04 refreshes on token refresh, resume, 403 and account switch',
    () {
      test(
        'each trigger fetches again; a uid switch resets to loading',
        () async {
          final auth = AccountFakeAuth(
            fakeUser: AccountFakeAuth.registered('g1', 'g@x'),
          );
          final source = ScriptedCapabilitiesSource({
            'g1': generalCaps,
            'p1': patientCaps,
          });
          final c = CapabilityController(auth: auth, source: source);
          await pumpEventQueue();
          expect(source.fetches, 1);
          auth.fireTokenChange();
          await pumpEventQueue();
          c.appResumed();
          await pumpEventQueue();
          c.onForbidden();
          await pumpEventQueue();
          expect(source.fetches, 4);

          source.gate = Completer<void>();
          auth.set(user: AccountFakeAuth.registered('p1', 'p@x'));
          await pumpEventQueue();
          expect(c.status, CapabilityStatus.loading);
          expect(
            c.effective.hasCareArea,
            isFalse,
            reason: 'nothing of g1 left',
          );
          source.gate!.complete();
          await pumpEventQueue();
          expect(c.effective.isPatient, isTrue);
        },
      );
      test('a stale response for the previous uid is ignored', () async {
        final auth = AccountFakeAuth(
          fakeUser: AccountFakeAuth.registered('p1', 'p@x'),
        );
        final slow = Completer<void>();
        final source = ScriptedCapabilitiesSource({'p1': patientCaps})
          ..gate = slow;
        final c = CapabilityController(auth: auth, source: source);
        await pumpEventQueue();
        source.byUid['g1'] = generalCaps;
        auth.set(user: AccountFakeAuth.registered('g1', 'g@x'));
        slow.complete();
        await pumpEventQueue();
        expect(c.effective.isPatient, isFalse);
        expect(c.effective.canDiscoverExperts, isTrue);
      });
    },
  );

  group('MOB1-04c a 403 drops confirmed privileges while re-checking', () {
    test(
      'ready patient → 403 → loading with NO privileges → re-confirmed',
      () async {
        final auth = AccountFakeAuth(
          fakeUser: AccountFakeAuth.registered('p1', 'p@x'),
        );
        final source = ScriptedCapabilitiesSource({'p1': patientCaps});
        final c = CapabilityController(auth: auth, source: source);
        await pumpEventQueue();
        expect(c.effective.canUseQuestionnaires, isTrue);
        source.gate = Completer<void>();
        c.onForbidden();
        await pumpEventQueue();
        expect(c.status, CapabilityStatus.loading);
        expect(c.effective.canUseQuestionnaires, isFalse);
        expect(c.effective.hasCareArea, isFalse);
        source.gate!.complete();
        await pumpEventQueue();
        expect(c.effective.canUseQuestionnaires, isTrue);
        expect(c.accessEnded, isFalse);
      },
    );
  });

  group('MOB1-04b account switch never inherits "was a patient"', () {
    test(
      'patient signs out, a general account signs in → no access-ended',
      () async {
        final auth = AccountFakeAuth(
          fakeUser: AccountFakeAuth.registered('p1', 'p@x'),
        );
        final lost = <String>[];
        final c = CapabilityController(
          auth: auth,
          source: ScriptedCapabilitiesSource({
            'p1': patientCaps,
            'g1': generalCaps,
          }),
          onPatientAccessLost: (uid) async => lost.add(uid),
        );
        await pumpEventQueue();
        expect(c.effective.isPatient, isTrue);
        auth.set(user: null);
        auth.set(user: AccountFakeAuth.registered('g1', 'g@x'));
        await pumpEventQueue();
        expect(c.accessEnded, isFalse);
        expect(lost, isEmpty);
      },
    );
  });

  group('MOB1-05 root routes for each role', () {
    RootRoute r({
      bool registered = true,
      CapabilityStatus caps = CapabilityStatus.ready,
      bool psychologist = false,
      UnlockState unlock = UnlockState.notNeeded,
      bool migrating = false,
      bool claim = false,
      bool ended = false,
    }) => resolveRootRoute(
      restored: true,
      loading: false,
      signedIn: true,
      onboardingComplete: true,
      registered: registered,
      capabilities: caps,
      psychologist: psychologist,
      unlock: unlock,
      migrating: migrating,
      claimOffered: claim,
      accessEnded: ended,
    );

    test('anonymous ignores every registered-only state', () {
      expect(
        r(
          registered: false,
          caps: CapabilityStatus.loading,
          psychologist: true,
          unlock: UnlockState.needed,
          migrating: true,
          claim: true,
          ended: true,
        ),
        RootRoute.chat,
      );
    });
    test(
      'order: check → psychologist → unlock → migration → claim → ended',
      () {
        expect(
          r(caps: CapabilityStatus.loading, psychologist: true),
          RootRoute.capabilityCheck,
        );
        expect(
          r(psychologist: true, unlock: UnlockState.needed),
          RootRoute.psychologist,
        );
        expect(
          r(unlock: UnlockState.needed, migrating: true),
          RootRoute.unlock,
        );
        expect(r(migrating: true, claim: true), RootRoute.migrating);
        expect(r(claim: true, ended: true), RootRoute.claim);
        expect(r(ended: true), RootRoute.accessEnded);
        expect(r(), RootRoute.chat);
      },
    );
  });

  group('MOB1-06 deep links / route guard', () {
    LinkDecision d(String link, CapabilityStatus s, KoiCapabilities c) =>
        decideDestination(
          parseKoiLink(Uri.parse(link)).destination,
          status: s,
          caps: c,
        );

    test('anonymous (incl. Firebase isAnonymous) → sign in for every protected link', () {
      for (final l in [
        'koi://experts',
        'koi://experts/x',
        'koi://care',
        'koi://care/questionnaires',
        'koi://care/questionnaires/a1',
        'koi://care/messages',
        'koi://care/appointments',
        'koi://care/notifications',
        'koi://care/psychologist',
      ]) {
        expect(
          d(l, CapabilityStatus.anonymous, patientCaps),
          LinkDecision.signIn,
          reason: l,
        );
      }
      expect(
        d('koi://portal', CapabilityStatus.anonymous, KoiCapabilities.none),
        LinkDecision.deny,
      );
      expect(
        d('koi://anything', CapabilityStatus.anonymous, KoiCapabilities.none),
        LinkDecision.allow,
      );
    });
    test(
      'loading → wait; general → experts only; patient → questionnaires',
      () {
        expect(
          d(
            'koi://care/questionnaires/a',
            CapabilityStatus.loading,
            KoiCapabilities.none,
          ),
          LinkDecision.wait,
        );
        expect(
          d('koi://experts', CapabilityStatus.ready, generalCaps),
          LinkDecision.allow,
        );
        expect(
          d('koi://care/questionnaires', CapabilityStatus.ready, generalCaps),
          LinkDecision.deny,
        );
        expect(
          d('koi://care/questionnaires', CapabilityStatus.ready, patientCaps),
          LinkDecision.allow,
        );
        expect(
          d(
            'koi://care/questionnaires',
            CapabilityStatus.unavailable,
            KoiCapabilities.none,
          ),
          LinkDecision.deny,
        );
      },
    );
    test(
      'psychologist: never companion or patient screens; portal allowed',
      () {
        for (final l in [
          'koi://chat',
          'koi://care/questionnaires',
          'koi://care',
          'koi://experts',
        ]) {
          expect(
            d(l, CapabilityStatus.ready, psychologistCaps),
            LinkDecision.deny,
            reason: l,
          );
        }
        expect(
          d('koi://portal', CapabilityStatus.ready, psychologistCaps),
          LinkDecision.allow,
        );
      },
    );
  });

  group('MOB1-21 token expiry and 403 handling in the platform client', () {
    test(
      '401 → one forced refresh + retry; second 401 → unauthorized',
      () async {
        final ok = _Transport([
          const PlatformHttpResponse(401, ''),
          PlatformHttpResponse(200, jsonEncode({'a': 1})),
        ]);
        var refreshed = 0;
        final client = PlatformClient(
          base: Uri.parse('https://api.test'),
          transport: ok,
          idToken: () async => 'old',
          refreshIdToken: () async => 'new-${++refreshed}',
        );
        expect(await client.getJson('/x'), {'a': 1});
        expect(ok.tokens, ['Bearer old', 'Bearer new-1']);

        final expired = _Transport([
          const PlatformHttpResponse(401, ''),
          const PlatformHttpResponse(401, ''),
        ]);
        final c2 = PlatformClient(
          base: Uri.parse('https://api.test'),
          transport: expired,
          idToken: () async => 'old',
          refreshIdToken: () async => 'new',
        );
        await expectLater(
          c2.getJson('/x'),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              PlatformErrorCode.unauthorized,
            ),
          ),
        );
      },
    );
    test(
      '403 calls onForbidden (capability refresh) and maps the code',
      () async {
        var forbidden = 0;
        final client = PlatformClient(
          base: Uri.parse('https://api.test'),
          transport: _Transport([const PlatformHttpResponse(403, '{}')]),
          idToken: () async => 't',
          refreshIdToken: () async => 't',
          onForbidden: () => forbidden++,
        );
        await expectLater(
          client.getJson('/x'),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              PlatformErrorCode.forbidden,
            ),
          ),
        );
        expect(forbidden, 1);
      },
    );
    test('409 codes: revision_conflict carries the current revision', () async {
      final client = PlatformClient(
        base: Uri.parse('https://api.test'),
        transport: _Transport([
          PlatformHttpResponse(
            409,
            jsonEncode({
              'error': {'code': 'revision_conflict', 'current_revision': 7},
            }),
          ),
          PlatformHttpResponse(
            409,
            jsonEncode({
              'error': {'code': 'attempt_submitted'},
            }),
          ),
        ]),
        idToken: () async => 't',
        refreshIdToken: () async => 't',
      );
      await expectLater(
        client.getJson('/x'),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', PlatformErrorCode.revisionConflict)
              .having((e) => e.currentRevision, 'rev', 7),
        ),
      );
      await expectLater(
        client.getJson('/x'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            PlatformErrorCode.attemptSubmitted,
          ),
        ),
      );
    });
    test('not configured → notConfigured, nothing sent', () async {
      final t = _Transport([]);
      final client = PlatformClient(
        base: null,
        transport: t,
        idToken: () async => 't',
        refreshIdToken: () async => 't',
      );
      await expectLater(
        client.getJson('/x'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            PlatformErrorCode.notConfigured,
          ),
        ),
      );
      expect(t.tokens, isEmpty);
    });
  });
}
