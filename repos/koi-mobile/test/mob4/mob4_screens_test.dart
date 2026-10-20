import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/account_gate_screens.dart';
import 'package:koi_mobile/account/account_providers.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/account/capability_controller.dart';
import 'package:koi_mobile/care/care_api_support.dart';
import 'package:koi_mobile/care/care_providers.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/care/mock_care_backend.dart';
import 'package:koi_mobile/care_messages/message_api.dart';
import 'package:koi_mobile/care_messages/message_models.dart';
import 'package:koi_mobile/care_messages/message_screens.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/invitations/invitation_api.dart';
import 'package:koi_mobile/platform/platform_client.dart';

import '../support/mob1_fakes.dart';
import '../support/mob2_fakes.dart';
import '../support/real_fonts.dart';

// MOB-4 screens: "not set up yet", the invitation code, the 1,000 cap.

KoiUser _registered(String uid) => AccountFakeAuth.registered(uid, '$uid@x');

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

String _t(CareText k) => CareStrings.en.t(k);

Future<void> _openCare(WidgetTester tester) async {
  await tester.tap(navTab('care'));
  await settle(tester);
}

/// Scrolls [key] to the middle first: right after typing, the focused
/// field's scroll animation ignores taps at the edge.
Future<void> _tapCentered(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await settle(tester, 3);
  await tester.tap(f);
  await settle(tester);
}

Future<void> _typeCode(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('invitation-code')),
      matching: find.byType(EditableText),
    ),
    text,
  );
  await settle(tester, 3);
}

/// Counts redeems; delegates to the demo backend unless [error] is set.
class _CountingInvitations implements InvitationApi {
  _CountingInvitations(this.inner);
  final InvitationApi inner;
  final keys = <String>[];
  Object? errorOnce;

  @override
  bool get isMock => false;

  @override
  Future<InvitationAck> redeem(String token, {required String idempotencyKey}) {
    keys.add(idempotencyKey);
    final e = errorOnce;
    if (e != null) {
      errorOnce = null;
      return Future.error(e);
    }
    return inner.redeem(token, idempotencyKey: idempotencyKey);
  }
}

/// [pages] pages of one message each, cursors 'c1'…, in id order.
class _PagedMessages implements CareMessageApi {
  _PagedMessages(this.pages);
  final int pages;
  int calls = 0;

  @override
  bool get isMock => false;

  @override
  Future<ApiPage<HumanMessage>> list(
    String relationshipId, {
    String? cursor,
  }) async {
    calls++;
    final i = cursor == null ? 0 : int.parse(cursor.substring(1));
    return ApiPage([
      HumanMessage(
        id: 'message_$i',
        relationshipId: relationshipId,
        senderUid: 'demo-expert-1',
        body: 'Message $i',
        createdAt: DateTime.utc(2026, 10, 21, 9).subtract(Duration(minutes: i)),
      ),
    ], i + 1 < pages ? 'c${i + 1}' : null);
  }

  @override
  Future<HumanMessage> send(
    String relationshipId,
    String body, {
    required String idempotencyKey,
  }) => Future.error(StateError('not used'));
}

void main() {
  useRealFonts();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('"not set up yet"', () {
    testWidgets('MOB4-20 a new Email/Password account (server: '
        'unregistered) sees the calm page — not the anonymous page, not '
        'Patient, not psychologist — and only /me/capabilities is called', (
      tester,
    ) async {
      final t = RecordingTransport(
        (m, uri) => uri.path == '/api/v1/me/capabilities'
            ? json200({
                'contract_version': '0.5.0',
                'uid': 'u1',
                'account_state': 'unregistered',
                'authorization_revision': 0,
                'capabilities': {
                  'companion_account_sync': false,
                  'expert_directory': false,
                  'professional_workspace': false,
                  'create_organization': false,
                },
                'professional_organization_ids': <String>[],
                'active_patient_relationships': <Object>[],
              })
            : const PlatformHttpResponse(404, ''),
      );
      final h = Mob1Harness(
        user: _registered('u1'),
        capabilities: HttpCapabilitiesSource(recordingClient(t)),
      );
      await h.secrets.setLinkedSecret('u1', 'pw');
      await pumpKoi(tester, h.overrides);
      expect(find.byType(PsychologistLandingScreen), findsNothing);
      expect(navTab('care'), findsOneWidget);
      await _openCare(tester);

      expect(find.byKey(const Key('care-not-set-up')), findsOneWidget);
      expect(find.text(_t(CareText.m4NotSetUp)), findsOneWidget);
      expect(find.byKey(const Key('care-anonymous')), findsNothing);
      expect(find.byKey(const Key('care-sign-in')), findsNothing);
      expect(find.byKey(const Key('care-create-account')), findsNothing);
      expect(find.byKey(const Key('care-invitation')), findsNothing);
      expect(find.byKey(const Key('care-psychologist')), findsNothing);
      expect(find.byKey(const Key('care-experts')), findsNothing);
      expect(t.requests.map((r) => r.uri.path).toSet(), {
        '/api/v1/me/capabilities',
      });
      // KOI chat is unaffected.
      await tester.tap(navTab('chat'));
      await settle(tester);
      expect(find.byKey(const Key('care-not-set-up')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MOB4-21 registered with no General access gets the same '
        'page; Retry keeps the tab while checking, then General Care opens', (
      tester,
    ) async {
      final h = Mob1Harness(
        user: _registered('u1'),
        caps: {
          'u1': const KoiCapabilities(
            role: KoiRole.general,
            accountState: AccountState.registered,
          ),
        },
      );
      await h.secrets.setLinkedSecret('u1', 'pw');
      await pumpKoi(tester, h.overrides);
      await _openCare(tester);
      expect(find.byKey(const Key('care-not-set-up')), findsOneWidget);

      final gate = h.source.gate = Completer<void>();
      h.source.byUid['u1'] = const KoiCapabilities(
        role: KoiRole.general,
        expertDiscovery: true,
        accountState: AccountState.registered,
      );
      await tester.tap(find.text(_t(CareText.retry)));
      await settle(tester, 4);
      expect(
        _container(tester).read(capabilityControllerProvider).status,
        CapabilityStatus.loading,
      );
      expect(navTab('care'), findsOneWidget, reason: 'tab kept while checking');
      gate.complete();
      h.source.gate = null;
      await settle(tester);
      expect(find.byKey(const Key('care-not-set-up')), findsNothing);
      expect(find.byKey(const Key('care-experts')), findsOneWidget);
      expect(find.byKey(const Key('care-invitation')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MOB4-22 the debug "anonymous" demo role behaves like the '
        'unregistered server answer (Urdu, right-to-left, 320dp)', (
      tester,
    ) async {
      final h = Mob2Harness(user: _registered('g1'), role: KoiRole.anonymous);
      h.urdu('g1');
      await h.base.secrets.setLinkedSecret('g1', 'pw');
      await pumpKoi(tester, h.overrides, width: 320);
      await _openCare(tester);
      expect(find.byKey(const Key('care-not-set-up')), findsOneWidget);
      expect(find.text(CareStrings.ur.t(CareText.m4NotSetUp)), findsOneWidget);
      expect(
        Directionality.of(
          tester.element(find.text(CareStrings.ur.t(CareText.m4NotSetUp))),
        ),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('invitation code', () {
    late Mob2Harness h;
    late _CountingInvitations api;
    Future<List<Override>> overrides() async {
      await h.base.secrets.setLinkedSecret('g1', 'pw');
      return [...h.overrides, invitationApiProvider.overrideWithValue(api)];
    }

    setUp(() {
      h = Mob2Harness(user: _registered('g1'));
      api = _CountingInvitations(MockInvitationApi(h.backend));
      h.auth.accounts['g1@x'] = ('g1', 'pw');
    });

    testWidgets('MOB4-23 General → paste the web link → agree → accept → '
        'capabilities re-checked → Patient Care; the code is gone and '
        'never saved or logged', (tester) async {
      // The REAL adapter on a fake wire: 409 first (logged by the platform
      // client), then the server's ack; the demo capabilities then report
      // the new relationship, like /me/capabilities would.
      var redeems = 0;
      final t = RecordingTransport((m, uri) {
        if (++redeems == 1) {
          return const PlatformHttpResponse(
            409,
            '{"code":"conflict","request_id":"r1","retryable":false}',
          );
        }
        h.caps.role.value = KoiRole.patient;
        return json200({
          'relationship_id': 'relationship_1',
          'organization_id': 'org_1',
          'state': 'active',
        });
      });
      api = _CountingInvitations(HttpInvitationApi(recordingClient(t)));
      final logs = <String>[];
      final old = debugPrint;
      debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
      // Restored inside the body: testWidgets checks debug vars before
      // tear-downs run.
      try {
        await _redeemFlow(tester, h, api, await overrides());
      } finally {
        debugPrint = old;
      }
      const code = MockCareBackend.demoInvitationCode;
      // Never in saved state, logs or Care state.
      final saved = jsonEncode({
        'prefs': h.base.prefs.values,
        'secure': h.base.secureKv.values,
        'drafts': h.base.drafts.rows,
        'checkIns': h.base.checkIns.rows,
        'messages': [for (final r in h.base.messages.rows.values) r.toJson()],
      });
      expect(saved, isNot(contains(code)));
      expect(t.requests, hasLength(2));
      expect(
        logs.where((l) => l.contains('patient-invitations/…/redeem → 409')),
        hasLength(1),
      );
      for (final l in logs) {
        expect(l, isNot(contains(code)), reason: l);
      }
      expect(find.textContaining(code), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('MOB4-24 a used / expired / cancelled code shows the ONE '
        'combined message and stays on the page', (tester) async {
      await pumpKoi(tester, await overrides());
      await _openCare(tester);
      await tapKey(tester, 'care-invitation');
      await _typeCode(tester, MockCareBackend.demoUsedInvitationCode);
      await _tapCentered(tester, 'invitation-consent');
      await _tapCentered(tester, 'invitation-redeem');
      expect(
        find.text(
          'This code has expired, been cancelled, or was already used.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('invitation-page')), findsOneWidget);
      expect(find.byKey(const Key('care-psychologist')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MOB4-25 a wrong-looking code or no consent never reaches '
        'the server', (tester) async {
      await pumpKoi(tester, await overrides());
      await _openCare(tester);
      await tapKey(tester, 'care-invitation');
      await _typeCode(tester, 'not-a-code');
      await _tapCentered(tester, 'invitation-consent');
      await _tapCentered(tester, 'invitation-redeem');
      expect(find.text(_t(CareText.m4InviteFormat)), findsOneWidget);
      await _typeCode(tester, MockCareBackend.demoInvitationCode);
      await _tapCentered(tester, 'invitation-consent'); // unticks it
      await _tapCentered(tester, 'invitation-redeem');
      expect(find.text(_t(CareText.consentNeeded)), findsOneWidget);
      expect(api.keys, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MOB4-26 recent sign-in (401) opens the re-check and retries '
        'the SAME redeem; 404 shows "not found"', (tester) async {
      api.errorOnce = reauthError;
      await pumpKoi(tester, await overrides());
      await _openCare(tester);
      await tapKey(tester, 'care-invitation');
      await _typeCode(tester, 'Abc_def-123' * 4);
      await _tapCentered(tester, 'invitation-consent');
      await _tapCentered(tester, 'invitation-redeem');
      expect(find.byKey(const Key('care-reauth')), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('care-reauth-password')),
          matching: find.byType(EditableText),
        ),
        'pw',
      );
      await tapKey(tester, 'care-reauth-confirm');
      await settle(tester);
      expect(api.keys, hasLength(2));
      expect(api.keys[0], api.keys[1], reason: 'same Idempotency-Key');
      expect(find.text(_t(CareText.m4InviteNotFound)), findsOneWidget);
      expect(find.byType(AccessEndedScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MOB4-27 Urdu invitation page at 320dp: right-to-left page, '
        'left-to-right code field, no overflow', (tester) async {
      h.urdu('g1');
      await pumpKoi(tester, await overrides(), width: 320);
      await _openCare(tester);
      await tapKey(tester, 'care-invitation');
      expect(
        find.text(CareStrings.ur.t(CareText.m4InviteTitle)),
        findsOneWidget,
      );
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('invitation-page'))),
        ),
        TextDirection.rtl,
      );
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('invitation-code')),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.textDirection, TextDirection.ltr);
      expect(field.keyboardType, TextInputType.visiblePassword);
      expect(tester.takeException(), isNull);
    });
  });

  group('load-all lists', () {
    testWidgets('MOB4-28 a thread past 1,000 messages shows the calm note; '
        'no "older messages" button', (tester) async {
      final h = Mob2Harness(user: _registered('p1'), role: KoiRole.patient);
      await h.base.secrets.setLinkedSecret('p1', 'pw');
      final paged = _PagedMessages(12);
      h.messageApi = paged;
      await pumpKoi(
        tester,
        h.overrides,
        home: const MessageThreadScreen(relationshipId: 'demo-relationship-1'),
      );
      await settle(tester, 10);
      expect(paged.calls, careMaxPages);
      expect(find.byKey(const Key('thread-capped')), findsOneWidget);
      expect(find.text(_t(CareText.m4MessagesCapped)), findsOneWidget);
      expect(find.text(_t(CareText.loadOlder)), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _redeemFlow(
  WidgetTester tester,
  Mob2Harness h,
  _CountingInvitations api,
  List<Override> overrides,
) async {
  await pumpKoi(tester, overrides);
  await _openCare(tester);
  expect(find.byKey(const Key('care-psychologist')), findsNothing);
  await tapKey(tester, 'care-invitation');
  expect(find.byKey(const Key('invitation-page')), findsOneWidget);

  const code = MockCareBackend.demoInvitationCode;
  await _typeCode(tester, 'https://koi.example/patient#invite=$code');
  await _tapCentered(tester, 'invitation-consent');
  await _tapCentered(tester, 'invitation-redeem');
  expect(find.text(_t(CareText.m4InviteUsed)), findsOneWidget);
  final fetches = h.counting.fetches;
  await _tapCentered(tester, 'invitation-redeem');
  await settle(tester, 10);

  expect(api.keys, hasLength(2));
  expect(api.keys[0], api.keys[1], reason: 'same code, same action key');
  expect(h.counting.fetches, greaterThan(fetches), reason: 're-checked');
  expect(find.byKey(const Key('invitation-page')), findsNothing);
  expect(find.byKey(const Key('care-psychologist')), findsOneWidget);
  expect(find.text(_t(CareText.m4InviteAccepted)), findsOneWidget);
}
