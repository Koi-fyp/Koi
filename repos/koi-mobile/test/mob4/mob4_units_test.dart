import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/account/capability_controller.dart';
import 'package:koi_mobile/account/destinations.dart';
import 'package:koi_mobile/appointments/appointment_api.dart';
import 'package:koi_mobile/appointments/appointment_models.dart';
import 'package:koi_mobile/care/care_api_support.dart';
import 'package:koi_mobile/care/care_session.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/care/mock_care_backend.dart';
import 'package:koi_mobile/care_messages/message_api.dart';
import 'package:koi_mobile/experts/expert_api.dart';
import 'package:koi_mobile/invitations/invitation_api.dart';
import 'package:koi_mobile/invitations/invitation_screen.dart';
import 'package:koi_mobile/notifications/notification_api.dart';
import 'package:koi_mobile/notifications/notification_models.dart';
import 'package:koi_mobile/platform/platform_client.dart';

import '../support/mob2_fakes.dart';

// MOB-4: mobile vs contract v0.5.2 (origin/handoff/koi-web-1-to-5-2026-10-20,
// read with git show only). The JSON below is copied from the contract's
// fixtures.json (valid: general_capabilities, unregistered_custom_session,
// notification; invalid: notification_job_status_leak,
// patient-cannot-receive-submission-notice) or follows the route code.

const _token = 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopq'; // 43, lower-case
const _token2 = 'Zx9_-Zx9_-Zx9_-Zx9_-Zx9_-Zx9_-Zx9_-Zx9_-Zx9_-';

Map<String, Object?> _caps({
  String uid = 'u1',
  String state = 'registered',
  bool general = true,
  bool professional = false,
  List<Map<String, Object?>> relationships = const [],
}) => {
  'contract_version': '0.5.0',
  'uid': uid,
  'account_state': state,
  'authorization_revision': state == 'unregistered' ? 0 : 1,
  'capabilities': {
    'companion_account_sync': general,
    'expert_directory': general,
    'professional_workspace': professional,
    'create_organization': false,
  },
  'professional_organization_ids': const <String>[],
  'active_patient_relationships': relationships,
};

PlatformHttpResponse _err(int status, String code) => PlatformHttpResponse(
  status,
  jsonEncode({'code': code, 'request_id': 'r1', 'retryable': false}),
);

/// A paged fake server: [pages] in order, cursors 'c1', 'c2', …
class _PagedFetch<T> {
  _PagedFetch(this.pages);
  final List<List<T>> pages;
  final cursors = <String?>[];
  Object? errorFor;
  String? errorCursor;

  Future<ApiPage<T>> call(String? cursor) async {
    cursors.add(cursor);
    if (errorCursor != null && cursor == errorCursor) {
      errorCursor = null;
      throw errorFor!;
    }
    final i = cursor == null ? 0 : int.parse(cursor.substring(1));
    return ApiPage(pages[i], i + 1 < pages.length ? 'c${i + 1}' : null);
  }
}

class _Item {
  const _Item(this.id, this.at);
  final String id;
  final int at;
}

const PlatformException _staleCursor = PlatformException(
  PlatformErrorCode.invalid,
  status: 422,
  body: {'code': 'invalid_request', 'request_id': 'r', 'retryable': false},
);

void main() {
  group('capabilities: account_state', () {
    test('MOB4-01 unregistered_custom_session → "not set up", no privilege, '
        'not anonymous', () {
      final c = KoiCapabilities.fromJson({
        'contract_version': '0.5.0',
        'uid': 'synthetic_custom_guest',
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
      }, uid: 'synthetic_custom_guest');
      expect(c.accountState, AccountState.unregistered);
      expect(c.careNotSetUp, isTrue);
      expect(c.hasCareArea, isFalse);
      expect(c.isPatient, isFalse);
      expect(c.isPsychologist, isFalse);
      expect(c.canDiscoverExperts, isFalse);
      // The route guard never opens Care data for it.
      for (final d in [
        KoiDestination.care,
        KoiDestination.experts,
        KoiDestination.invitation,
        KoiDestination.messages,
        KoiDestination.proPortal,
      ]) {
        expect(
          decideDestination(d, status: CapabilityStatus.ready, caps: c),
          LinkDecision.deny,
          reason: d.name,
        );
      }
    });

    test('MOB4-02 every non-registered state, and registered with no '
        'General access, is "not set up"; General / Patient / psychologist '
        'and "no answer" are not', () {
      for (final s in ['unregistered', 'suspended', 'closed', 'other']) {
        final c = KoiCapabilities.fromJson(
          _caps(
            state: s,
            relationships: [
              {
                'relationship_id': 'r1',
                'organization_id': 'o1',
                'psychologist_uid': 'p1',
              },
            ],
          ),
          uid: 'u1',
        );
        expect(c.careNotSetUp, isTrue, reason: s);
        expect(c.isPatient, isFalse, reason: s);
      }
      final noGeneral = KoiCapabilities.fromJson(
        _caps(general: false),
        uid: 'u1',
      );
      expect(noGeneral.accountState, AccountState.registered);
      expect(noGeneral.careNotSetUp, isTrue);

      final general = KoiCapabilities.fromJson(_caps(), uid: 'u1');
      expect(general.careNotSetUp, isFalse);
      expect(general.canDiscoverExperts, isTrue);
      final pro = KoiCapabilities.fromJson(
        _caps(general: false, professional: true),
        uid: 'u1',
      );
      expect(pro.isPsychologist, isTrue);
      expect(pro.careNotSetUp, isFalse);
      expect(KoiCapabilities.none.careNotSetUp, isFalse);
      expect(KoiCapabilities.none.accountState, AccountState.unknown);
    });

    test('MOB4-03 the demo source: "anonymous" role = an unregistered '
        'server answer, the others are registered', () async {
      final src = MockCapabilitiesSource(initial: KoiRole.anonymous);
      expect((await src.fetch('u1')).careNotSetUp, isTrue);
      src.role.value = KoiRole.general;
      expect((await src.fetch('u1')).careNotSetUp, isFalse);
    });
  });

  group('REAL v0.5.2 adapters (route code)', () {
    test('MOB4-04 experts: GET /api/v1/experts?limit=25 and /experts/{uid}; '
        'only the four ExpertDTO fields are read', () async {
      final t = RecordingTransport(
        (m, uri) => uri.path.endsWith('/experts')
            ? json200({
                'items': [
                  {
                    'id': 'psy-1',
                    'display_name': 'A',
                    'bio': 'B',
                    'accepting_new_patients': true,
                    'organization_id': 'should-not-be-read',
                  },
                ],
                'next_cursor': null,
              })
            : json200({
                'id': 'psy-1',
                'display_name': 'A',
                'bio': 'B',
                'accepting_new_patients': false,
              }),
      );
      final api = HttpExpertDirectoryApi(recordingClient(t));
      final page = await api.list();
      expect(page.items.single.id, 'psy-1');
      expect(page.nextCursor, isNull);
      expect(t.requests.single.uri.path, '/api/v1/experts');
      expect(t.requests.single.uri.queryParameters, {'limit': '25'});
      final one = await api.detail('psy-1');
      expect(one.acceptingNewPatients, isFalse);
      expect(t.requests.last.uri.path, '/api/v1/experts/psy-1');
    });

    test('MOB4-05 messages: list with limit=100; send = POST /api/v1/messages '
        '{relationship_id, body} + Idempotency-Key', () async {
      final t = RecordingTransport(
        (m, uri) => m == 'GET'
            ? json200({'items': <Object>[], 'next_cursor': null})
            : PlatformHttpResponse(
                201,
                jsonEncode({
                  'id': 'message_1',
                  'relationship_id': 'rel-1',
                  'sender_uid': 'u1',
                  'body': 'hi',
                  'created_at': '2026-10-21T10:00:00Z',
                }),
              ),
      );
      final api = HttpCareMessageApi(recordingClient(t));
      await api.list('rel-1', cursor: 'cur');
      expect(t.requests[0].uri.path, '/api/v1/relationships/rel-1/messages');
      expect(t.requests[0].uri.queryParameters, {
        'limit': '100',
        'cursor': 'cur',
      });
      final m = await api.send('rel-1', 'hi', idempotencyKey: 'k-1');
      expect(m.id, 'message_1');
      expect(t.requests[1].method, 'POST');
      expect(t.requests[1].uri.path, '/api/v1/messages');
      expect(jsonDecode(t.requests[1].body!), {
        'relationship_id': 'rel-1',
        'body': 'hi',
      });
      expect(t.requests[1].headers['Idempotency-Key'], 'k-1');
    });

    test('MOB4-06 appointments: list limit=100; create {relationship_id}; '
        'transition {expected_revision, to_state} only', () async {
      Map<String, Object?> dto(String state, int rev) => {
        'id': 'appointment_1',
        'relationship_id': 'rel-1',
        'state': state,
        'revision': rev,
        'updated_at': '2026-10-21T10:00:00Z',
      };
      final t = RecordingTransport(
        (m, uri) => m == 'GET'
            ? json200({'items': <Object>[], 'next_cursor': null})
            : uri.path.endsWith('/transition')
            ? json200(dto('cancelled', 2))
            : PlatformHttpResponse(201, jsonEncode(dto('requested', 1))),
      );
      final api = HttpAppointmentApi(recordingClient(t));
      await api.list('rel-1');
      expect(
        t.requests[0].uri.path,
        '/api/v1/relationships/rel-1/appointments',
      );
      expect(t.requests[0].uri.queryParameters['limit'], '100');
      await api.request('rel-1', idempotencyKey: 'k1');
      expect(t.requests[1].uri.path, '/api/v1/appointments');
      expect(jsonDecode(t.requests[1].body!), {'relationship_id': 'rel-1'});
      final a = await api.transition(
        'appointment_1',
        expectedRevision: 1,
        to: AppointmentState.cancelled,
        idempotencyKey: 'k2',
      );
      expect(a.state, AppointmentState.cancelled);
      expect(
        t.requests[2].uri.path,
        '/api/v1/appointments/appointment_1/transition',
      );
      expect(jsonDecode(t.requests[2].body!), {
        'expected_revision': 1,
        'to_state': 'cancelled',
      });
      expect(t.requests[2].headers['Idempotency-Key'], 'k2');
    });

    test('MOB4-07 notifications: GET list, POST …/read with {} ; leak '
        'fixtures never reach the model', () async {
      final t = RecordingTransport(
        (m, uri) => m == 'GET'
            ? json200({
                'items': [
                  // fixtures.json valid "notification"
                  {
                    'id': 'notification_1',
                    'event_id': 'event_1',
                    'kind': 'assignment',
                    'reference': {'assignment_id': 'assignment_1'},
                    'created_at': '2026-10-19T12:00:00Z',
                  },
                  // invalid "patient-cannot-receive-submission-notice" item
                  {
                    'id': 'notice_demo',
                    'event_id': 'submission_demo',
                    'submission_id': 'submission_demo',
                    'created_at': '2026-10-20T00:00:00Z',
                  },
                ],
                'next_cursor': null,
              })
            : json200({
                // invalid "notification_job_status_leak"
                'id': 'notification_1',
                'event_id': 'event_1',
                'kind': 'assignment',
                'reference': {
                  'assignment_id': 'assignment_1',
                  'job_status': 'completed',
                },
                'created_at': '2026-10-19T12:00:00Z',
                'read_at': '2026-10-19T12:05:00Z',
              }),
      );
      final api = HttpNotificationApi(recordingClient(t));
      final page = await api.list();
      expect(page.items, hasLength(1), reason: 'submission notice dropped');
      expect(t.requests[0].uri.path, '/api/v1/notifications');
      final n = await api.markRead('notification_1', idempotencyKey: 'k');
      expect(
        t.requests[1].uri.path,
        '/api/v1/notifications/notification_1/read',
      );
      expect(t.requests[1].body, '{}');
      expect(n.referenceId, 'assignment_1');
      expect(n.isRead, isTrue);
      // Only the one typed id is read from `reference` (no job state).
      expect(n.kind, NotificationKind.assignment);
    });
  });

  group('paging (v0.5.2: id order, expiring cursors, empty pages)', () {
    test('MOB4-08 loadAll reads every page and sorts by time: an item that '
        'is only on page 3 is shown; no "Show more"', () async {
      final f = _PagedFetch<_Item>([
        [const _Item('m-b', 5), const _Item('m-a', 1)],
        [const _Item('m-c', 3)],
        [const _Item('m-z', 9)], // the newest message lives on the last page
      ]);
      final list = CareList<_Item>(
        f.call,
        idOf: (i) => i.id,
        sort: (a, b) => a.at.compareTo(b.at),
        loadAll: true,
      );
      await list.refresh();
      expect(f.cursors, [null, 'c1', 'c2']);
      expect(list.items.map((i) => i.id), ['m-a', 'm-c', 'm-b', 'm-z']);
      expect(list.hasMore, isFalse);
      expect(list.capped, isFalse);
      // Polling (merge) reads everything again.
      f.pages[2] = [const _Item('m-z', 9), const _Item('m-new', 10)];
      await list.refresh(merge: true);
      expect(list.items.last.id, 'm-new');
    });

    test('MOB4-09 loadAll stops at 10 pages and says so (capped)', () async {
      final f = _PagedFetch<_Item>([
        for (var p = 0; p < 12; p++) [_Item('i$p', p)],
      ]);
      final list = CareList<_Item>(f.call, idOf: (i) => i.id, loadAll: true);
      await list.refresh();
      expect(f.cursors, hasLength(careMaxPages));
      expect(list.items, hasLength(10));
      expect(list.capped, isTrue);
      expect(carePageLimitAll * careMaxPages, 1000);
    });

    test('MOB4-10 an expired cursor (422) restarts from the first page, '
        'never an error or a dead "Show more"', () async {
      final f = _PagedFetch<_Item>([
        [const _Item('a', 1)],
        [const _Item('b', 2)],
      ]);
      final list = CareList<_Item>(f.call, idOf: (i) => i.id);
      await list.refresh();
      expect(list.hasMore, isTrue);
      f
        ..errorCursor = 'c1'
        ..errorFor = _staleCursor;
      await list.loadMore();
      expect(list.error, isNull);
      expect(f.cursors, [null, 'c1', null]);
      expect(list.hasMore, isTrue, reason: 'back on page 1');
      await list.loadMore();
      expect(list.items.map((i) => i.id), containsAll(['a', 'b']));

      // loadAll: a stale cursor in the middle of a read starts over once.
      final g =
          _PagedFetch<_Item>([
              [const _Item('a', 1)],
              [const _Item('b', 2)],
            ])
            ..errorCursor = 'c1'
            ..errorFor = _staleCursor;
      final all = CareList<_Item>(g.call, idOf: (i) => i.id, loadAll: true);
      await all.refresh();
      expect(all.error, isNull);
      expect(g.cursors, [null, 'c1', null, 'c1']);
      expect(all.items, hasLength(2));
    });

    test('MOB4-11 an empty page with a next cursor is followed (hidden '
        'directory profiles), up to 10 pages', () async {
      final f = _PagedFetch<_Item>([
        const [],
        const [],
        [const _Item('x', 1)],
        [const _Item('y', 2)],
      ]);
      final list = CareList<_Item>(f.call, idOf: (i) => i.id);
      await list.refresh();
      expect(list.items.single.id, 'x');
      expect(list.hasMore, isTrue);
      final empty = _PagedFetch<_Item>([for (var i = 0; i < 15; i++) const []]);
      final none = CareList<_Item>(empty.call, idOf: (i) => i.id);
      await none.refresh();
      expect(empty.cursors, hasLength(CareList.maxEmptyPages));
      expect(none.items, isEmpty);
    });
  });

  group('invitation redeem', () {
    test('MOB4-12 parseInvitationToken: the code, the web link, spaces; '
        'anything else is refused on the phone', () {
      expect(parseInvitationToken(_token), _token);
      expect(parseInvitationToken('  $_token2\n'), _token2);
      expect(
        parseInvitationToken('https://koi.example/patient#invite=$_token'),
        _token,
      );
      expect(
        parseInvitationToken('https://koi.example/patient#a=1&invite=$_token2'),
        _token2,
      );
      expect(parseInvitationToken('abc'), isNull, reason: 'too short');
      expect(parseInvitationToken('${_token.substring(1)}!'), isNull);
      expect(parseInvitationToken('https://koi.example/patient#x=1'), isNull);
      expect(parseInvitationToken('a' * 129), isNull, reason: 'too long');
      expect(parseInvitationToken(''), isNull);
    });

    test('MOB4-13 HTTP: POST /api/v1/patient-invitations/{token}/redeem '
        '{consent_version: care-consent-v1} + Idempotency-Key; the ack is '
        'RelationshipAckDTO', () async {
      final t = RecordingTransport(
        (m, uri) => json200({
          'relationship_id': 'relationship_1',
          'organization_id': 'org_1',
          'state': 'active',
        }),
      );
      final ack = await HttpInvitationApi(recordingClient(t))
          .redeem(_token, idempotencyKey: 'key-1');
      expect(ack.relationshipId, 'relationship_1');
      final r = t.requests.single;
      expect(r.method, 'POST');
      expect(r.uri.path, '/api/v1/patient-invitations/$_token/redeem');
      expect(jsonDecode(r.body!), {'consent_version': 'care-consent-v1'});
      expect(r.headers['Idempotency-Key'], 'key-1');
      expect(
        () => InvitationAck.fromJson({
          'relationship_id': 'r',
          'organization_id': 'o',
          'state': 'closed',
        }),
        throwsFormatException,
      );
    });

    test('MOB4-14 server answers → friendly failures; 409 = ONE message for '
        'expired / cancelled / used', () async {
      Future<InvitationFailure> failWith(PlatformHttpResponse res) async {
        final api = HttpInvitationApi(
          recordingClient(RecordingTransport((m, u) => res)),
        );
        try {
          await api.redeem(_token2, idempotencyKey: 'k');
        } catch (e) {
          return invitationFailureOf(e);
        }
        fail('no error');
      }

      expect(
        await failWith(_err(422, 'invalid_request')),
        InvitationFailure.format,
      );
      expect(
        await failWith(_err(404, 'not_found')),
        InvitationFailure.notFound,
      );
      expect(await failWith(_err(409, 'conflict')), InvitationFailure.used);
      expect(await failWith(_err(403, 'forbidden')), InvitationFailure.denied);
      expect(
        await failWith(_err(401, 'unauthenticated')),
        InvitationFailure.reauth,
      );
      expect(
        await failWith(_err(429, 'rate_limited')),
        InvitationFailure.rateLimited,
      );
      expect(
        await failWith(const PlatformHttpResponse(404, 'Not Found')),
        InvitationFailure.notAvailable,
        reason: 'route missing on that server',
      );
      expect(
        invitationFailureText(CareStrings.en, InvitationFailure.used),
        'This code has expired, been cancelled, or was already used.',
      );
      for (final f in InvitationFailure.values) {
        expect(invitationFailureText(CareStrings.ur, f), isNotEmpty);
      }
    });

    test('MOB4-15 the token is never logged, never in an exception text, '
        'never in the log path template', () async {
      final logs = <String>[];
      final old = debugPrint;
      debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = old);
      for (final status in [400, 401, 403, 404, 409, 422, 429, 503]) {
        final api = HttpInvitationApi(
          recordingClient(
            RecordingTransport((m, u) => _err(status, 'conflict')),
          ),
        );
        try {
          await api.redeem(_token, idempotencyKey: 'k');
        } catch (e) {
          expect(e.toString(), isNot(contains(_token)));
          expect(e.toString(), isNot(contains(_token.substring(0, 20))));
        }
      }
      expect(logs, isNotEmpty);
      for (final l in logs) {
        expect(l, isNot(contains(_token.substring(0, 20))), reason: l);
      }
      expect(
        PlatformClient.template('/api/v1/patient-invitations/$_token/redeem'),
        '/api/v1/patient-invitations/…/redeem',
      );
      expect(
        PlatformClient.template('/api/v1/relationships/rel-1/messages'),
        '/api/v1/relationships/…/messages',
      );
    });

    test('MOB4-16 demo backend follows the server: General only (403), '
        'unknown 404, used 409, success → Patient', () async {
      final caps = MockCapabilitiesSource(initial: KoiRole.anonymous);
      final backend = MockCareBackend(
        currentUid: () => 'u1',
        capabilities: caps,
        latency: Duration.zero,
      );
      Future<InvitationFailure?> redeem(String code) async {
        try {
          await backend.redeemInvitation(code);
          return null;
        } catch (e) {
          return invitationFailureOf(e);
        }
      }

      expect(
        await redeem(MockCareBackend.demoInvitationCode),
        InvitationFailure.denied,
        reason: 'not set up yet',
      );
      caps.role.value = KoiRole.general;
      expect(await redeem(_token), InvitationFailure.notFound);
      expect(
        await redeem(MockCareBackend.demoUsedInvitationCode),
        InvitationFailure.used,
      );
      expect(await redeem(MockCareBackend.demoInvitationCode), isNull);
      expect((await caps.fetch('u1')).isPatient, isTrue);
      expect(
        await redeem(MockCareBackend.demoInvitationCode),
        InvitationFailure.used,
        reason: 'single use',
      );
      expect(
        parseInvitationToken(MockCareBackend.demoInvitationCode),
        isNotNull,
      );
      expect(
        parseInvitationToken(MockCareBackend.demoUsedInvitationCode),
        isNotNull,
      );
    });
  });

  group('applications (v0.5.2 addition)', () {
    test(
      'MOB4-17 a new application to a profile not accepting new '
      'patients is a 403 (demo backend mirrors lifecycle.ts:159-160)',
      () async {
        final caps = MockCapabilitiesSource();
        final backend = MockCareBackend(
          currentUid: () => 'u1',
          capabilities: caps,
          latency: Duration.zero,
        );
        await expectLater(
          backend.createApplication('demo-expert-2'),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              PlatformErrorCode.forbidden,
            ),
          ),
        );
        final ok = await backend.createApplication('demo-expert-1');
        expect(ok.psychologistUid, 'demo-expert-1');
      },
    );
  });

  test('MOB4-18 every MOB-4 string exists in English and Urdu', () {
    final keys = CareText.values.where((k) => k.name.startsWith('m4'));
    expect(keys, hasLength(19));
    for (final k in keys) {
      expect(CareStrings.en.t(k), isNotEmpty, reason: k.name);
      expect(CareStrings.ur.t(k), isNotEmpty, reason: k.name);
      expect(CareStrings.ur.t(k), isNot(CareStrings.en.t(k)), reason: k.name);
    }
    expect(
      CareStrings.en.t(CareText.m4NotSetUp),
      "Your account is created, but care features aren't set up for it yet.",
    );
  });

  test('MOB4-19 the appointment / message models still parse the exact '
      'v0.5.2 DTOs and read no other field', () {
    final a = Appointment.fromJson({
      'id': 'appointment_1',
      'relationship_id': 'rel-1',
      'state': 'proposed',
      'revision': 2,
      'updated_at': '2026-10-21T10:00:00Z',
      'starts_at': '2026-10-22T10:00:00Z',
      'ends_at': '2026-10-22T10:50:00Z',
      'psychologist_note': 'never read',
    });
    expect(
      patientAppointmentActions(a),
      contains(PatientAppointmentAction.confirm),
    );
    final n = CareNotification.fromJson({
      'id': 'n',
      'event_id': 'e',
      'kind': 'appointment_change',
      'reference': {'appointment_id': 'appointment_1', 'score': 7},
      'created_at': '2026-10-21T10:00:00Z',
    })!;
    expect(n.kind, NotificationKind.appointmentChange);
    expect(n.referenceId, 'appointment_1');
  });
}
