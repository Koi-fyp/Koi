import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/account/capability_controller.dart';
import 'package:koi_mobile/app/root_router.dart';
import 'package:koi_mobile/applications/application_api.dart';
import 'package:koi_mobile/applications/application_flow.dart';
import 'package:koi_mobile/applications/application_models.dart';
import 'package:koi_mobile/appointments/appointment_api.dart';
import 'package:koi_mobile/appointments/appointment_models.dart';
import 'package:koi_mobile/care/care_api_support.dart';
import 'package:koi_mobile/care/care_providers.dart';
import 'package:koi_mobile/care/care_session.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/care_messages/message_api.dart';
import 'package:koi_mobile/care_messages/message_models.dart';
import 'package:koi_mobile/experts/expert_api.dart';
import 'package:koi_mobile/experts/expert_screens.dart';
import 'package:koi_mobile/notifications/notification_api.dart';
import 'package:koi_mobile/notifications/notification_models.dart';
import 'package:koi_mobile/platform/platform_client.dart';

import '../support/mob1_fakes.dart';
import '../support/mob2_fakes.dart';

/// Fields a patient model must never even parse (spec: scores, evaluations,
/// risk levels, psychologist notes).
const Map<String, Object?> _clinical = {
  'score': 12,
  'scores': [1, 2],
  'evaluation': {'status': 'queued'},
  'evaluation_id': 'ev1',
  'risk_level': 'HIGH',
  'severity': 'moderate',
  'interpretation': 'x',
  'clinician_notes': 'private',
  'review_status': 'approved',
  'ai_job_id': 'job1',
};

CareSession _session({
  NotificationApi? notifications,
  CareMessageApi? messages,
  ApplicationApi? applications,
  Future<void> Function()? refreshCaps,
}) => CareSession(
  uid: 'g1',
  expertApi: MockExpertDirectoryApi(latency: Duration.zero),
  applicationApi: applications ?? FakeApplicationApi(),
  messageApi: messages ?? FakeMessageApi(),
  appointmentApi: FakeAppointmentApi(),
  notificationApi: notifications ?? FakeNotificationApi(),
  refreshCapabilities: refreshCaps,
);

void main() {
  group('MOB2-01 capabilities follow contract v0.5.1 CapabilitiesDTO', () {
    Map<String, Object?> body(List<Object?> rels) => {
      'contract_version': '0.5.0',
      'uid': 'p1',
      'account_state': 'registered',
      'authorization_revision': 7,
      'capabilities': {
        'companion_account_sync': true,
        'expert_directory': true,
        'professional_workspace': false,
        'create_organization': false,
      },
      'professional_organization_ids': const <String>[],
      'active_patient_relationships': rels,
      ..._clinical,
    };
    test('every active relationship is kept, in order; extras ignored', () {
      final c = KoiCapabilities.fromJson(
        body([
          {
            'relationship_id': 'r1',
            'organization_id': 'o1',
            'psychologist_uid': 'p-a',
          },
          {'relationship_id': 'bad'}, // incomplete → dropped
          {
            'relationship_id': 'r2',
            'organization_id': 'o2',
            'psychologist_uid': 'p-b',
          },
        ]),
        uid: 'p1',
      );
      expect(c.isPatient, isTrue);
      expect(c.canUseQuestionnaires, isTrue, reason: 'no flag: relationship');
      expect([for (final r in c.activeRelationships) r.id], ['r1', 'r2']);
      expect(c.relationship!.psychologistDisplayName, isNull);
      expect(c.authorizationRevision, 7);
    });
    test('no relationship → General; a General never has patient areas', () {
      final c = KoiCapabilities.fromJson(body(const []), uid: 'p1');
      expect(c.role, KoiRole.general);
      expect(c.activeRelationships, isEmpty);
      expect(c.canUseQuestionnaires, isFalse);
    });
  });

  group(
    'MOB2-02 platform client: flat ErrorDTO, Idempotency-Key, recent sign-in',
    () {
      PlatformHttpResponse err(int status, String code) => PlatformHttpResponse(
        status,
        jsonEncode({'code': code, 'request_id': 'req', 'retryable': false}),
      );
      Future<PlatformErrorCode> codeOf(
        PlatformHttpResponse r, {
        String method = 'GET',
      }) async {
        final client = recordingClient(RecordingTransport((_, _) => r));
        try {
          if (method == 'GET') {
            await client.getJson('/x');
          } else {
            await client.sendJson(method, '/x', const {}, idempotencyKey: 'k');
          }
        } on PlatformException catch (e) {
          return e.code;
        }
        fail('no error');
      }

      test('codes', () async {
        expect(
          await codeOf(err(403, 'forbidden')),
          PlatformErrorCode.forbidden,
        );
        expect(await codeOf(err(404, 'not_found')), PlatformErrorCode.notFound);
        expect(await codeOf(err(409, 'conflict')), PlatformErrorCode.conflict);
        expect(
          await codeOf(err(429, 'rate_limited')),
          PlatformErrorCode.rateLimited,
        );
        expect(
          await codeOf(err(422, 'invalid_request')),
          PlatformErrorCode.invalid,
        );
      });
      test('a mutation 401 unauthenticated (even after a fresh token) = '
          'recent sign-in needed; a GET 401 = session expired', () async {
        expect(
          await codeOf(err(401, 'unauthenticated'), method: 'POST'),
          PlatformErrorCode.reauthRequired,
        );
        expect(
          await codeOf(err(401, 'unauthenticated')),
          PlatformErrorCode.unauthorized,
        );
        expect(
          await codeOf(const PlatformHttpResponse(401, ''), method: 'POST'),
          PlatformErrorCode.unauthorized,
          reason: 'MOB-1 provisional (non-contract) 401 unchanged',
        );
      });
      test('Idempotency-Key header on every mutation; never on GET', () async {
        final t = RecordingTransport((_, _) => json200(const {}));
        final c = recordingClient(t);
        await c.sendJson('POST', '/a', const {}, idempotencyKey: 'key-1');
        await c.getJson('/b');
        expect(t.requests[0].headers['Idempotency-Key'], 'key-1');
        expect(t.requests[1].headers.containsKey('Idempotency-Key'), isFalse);
      });
      test('a 404 without a contract body = endpoint missing (Not available '
          'yet); a contract not_found = gone', () {
        expect(
          careFailureOf(
            const PlatformException(PlatformErrorCode.notFound, status: 404),
          ),
          CareFailure.notAvailable,
        );
        expect(
          careFailureOf(
            const PlatformException(
              PlatformErrorCode.notFound,
              status: 404,
              body: {'code': 'not_found', 'request_id': 'r'},
            ),
          ),
          CareFailure.gone,
        );
        expect(
          careFailureOf(
            const PlatformException(PlatformErrorCode.notConfigured),
          ),
          CareFailure.notAvailable,
        );
        expect(careFailureOf(reauthError), CareFailure.reauth);
      });
      test('idempotency keys are random uuid v4', () {
        final a = newIdempotencyKey(), b = newIdempotencyKey();
        expect(a, isNot(b));
        expect(
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-')
              .hasMatch(a),
          isTrue,
        );
      });
    },
  );

  group(
    'MOB2-03 adapters: real vs mock vs unavailable, exact contract paths',
    () {
      test('selection: mocks > configured > unavailable', () {
        String pick({required bool mocks, required bool configured}) =>
            pickCareAdapter<String>(
              mocks: mocks,
              configured: configured,
              mock: () => 'mock',
              real: () => 'real',
              unavailable: 'none',
            );
        expect(pick(mocks: true, configured: true), 'mock');
        expect(pick(mocks: true, configured: false), 'mock');
        expect(pick(mocks: false, configured: true), 'real');
        expect(pick(mocks: false, configured: false), 'none');
      });
      test(
        'unavailable adapters fail as "Not available yet", never data',
        () async {
          for (final f in <Future<Object?> Function()>[
            () => const UnavailableApplicationApi().list(),
            () => const UnavailableCareMessageApi().list('r'),
            () => const UnavailableAppointmentApi().list('r'),
            () => const UnavailableNotificationApi().list(),
            () => const UnavailableExpertDirectoryApi().list(),
          ]) {
            await expectLater(
              f(),
              throwsA(
                predicate((e) => careFailureOf(e!) == CareFailure.notAvailable),
              ),
            );
          }
        },
      );
      test('real adapters: method, path, body, Idempotency-Key', () async {
        final t = RecordingTransport((method, uri) {
          final p = uri.path;
          if (p.endsWith('/messages') && method == 'GET') {
            return json200({'items': [], 'next_cursor': null});
          }
          if (p == '/api/v1/messages') {
            return json200({
              'id': 'm1',
              'relationship_id': 'r1',
              'sender_uid': 'u',
              'body': 'hi',
              'created_at': '2026-10-19T08:00:00Z',
            });
          }
          if (p.contains('connection-requests')) {
            return json200({
              'id': 'c1',
              'organization_id': 'o',
              'applicant_uid': 'u',
              'psychologist_uid': 'p',
              'state': 'requested',
              'demo_payment_state': 'demo_pending',
              'revision': 1,
              'created_at': '2026-10-19T08:00:00Z',
              'updated_at': '2026-10-19T08:00:00Z',
            });
          }
          if (p.contains('appointments')) {
            return json200({
              'id': 'a1',
              'relationship_id': 'r1',
              'state': 'requested',
              'revision': 1,
              'updated_at': '2026-10-19T08:00:00Z',
            });
          }
          return json200({
            'id': 'n1',
            'event_id': 'e1',
            'kind': 'assignment',
            'reference': {'assignment_id': 'as1'},
            'created_at': '2026-10-19T08:00:00Z',
            'read_at': '2026-10-19T09:00:00Z',
          });
        });
        final c = recordingClient(t);
        await HttpApplicationApi(c).create('p', idempotencyKey: 'k1');
        await HttpApplicationApi(c).transition(
          'c1',
          expectedRevision: 1,
          to: ApplicationState.withdrawn,
          idempotencyKey: 'k2',
        );
        await HttpApplicationApi(
          c,
        ).completeDemoPayment('c1', expectedRevision: 2, idempotencyKey: 'k3');
        await HttpCareMessageApi(c).list('r1');
        await HttpCareMessageApi(c).send('r1', 'hi', idempotencyKey: 'k4');
        await HttpAppointmentApi(c).request('r1', idempotencyKey: 'k5');
        await HttpAppointmentApi(c).transition(
          'a1',
          expectedRevision: 1,
          to: AppointmentState.cancelled,
          idempotencyKey: 'k6',
        );
        await HttpNotificationApi(c).markRead('n1', idempotencyKey: 'k7');
        final r = t.requests;
        expect(
          [for (final x in r) '${x.method} ${x.uri.path}'],
          [
            'POST /api/v1/connection-requests',
            'POST /api/v1/connection-requests/c1/transition',
            'POST /api/v1/connection-requests/c1/demo-payment',
            'GET /api/v1/relationships/r1/messages',
            'POST /api/v1/messages',
            'POST /api/v1/appointments',
            'POST /api/v1/appointments/a1/transition',
            'POST /api/v1/notifications/n1/read',
          ],
        );
        expect(jsonDecode(r[0].body!), {
          'psychologist_uid': 'p',
          'consent_version': 'care-consent-v1',
        });
        expect(jsonDecode(r[1].body!), {
          'expected_revision': 1,
          'to_state': 'withdrawn',
        });
        expect(jsonDecode(r[2].body!), {'expected_revision': 2});
        expect(jsonDecode(r[4].body!), {'relationship_id': 'r1', 'body': 'hi'});
        expect(jsonDecode(r[5].body!), {'relationship_id': 'r1'});
        expect(r[3].uri.queryParameters, {'limit': '25'});
        expect(
          [for (final x in r) x.headers['Idempotency-Key']],
          ['k1', 'k2', 'k3', null, 'k4', 'k5', 'k6', 'k7'],
        );
        for (final x in r) {
          expect(x.uri.path.contains('/api/v1/chat'), isFalse);
        }
      });
    },
  );

  group('MOB2-04 patient models never parse clinical fields', () {
    test('extra score / evaluation / risk / notes keys are dropped', () {
      final e = ExpertProfile.fromJson({
        'id': 'p',
        'display_name': 'P',
        'bio': 'b',
        'accepting_new_patients': true,
        ..._clinical,
      });
      expect(e.bio, 'b');
      final n = CareNotification.fromJson({
        'id': 'n',
        'event_id': 'e',
        'kind': 'assignment',
        'reference': {'assignment_id': 'a', ..._clinical},
        'created_at': '2026-10-19T08:00:00Z',
        ..._clinical,
      })!;
      expect(n.referenceId, 'a');
    });
    test('no MOB-2 model or screen file even names such a field', () {
      final forbidden = RegExp(
        r'score|evaluation|severity|interpretation|clinician|risk_level|'
        r'review_status|ai_job',
        caseSensitive: false,
      );
      for (final dir in [
        'lib/applications',
        'lib/appointments',
        'lib/care_messages',
        'lib/notifications',
        'lib/experts',
      ]) {
        for (final f in Directory(dir).listSync().whereType<File>()) {
          final lines = f.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final l = lines[i].trimLeft();
            if (l.startsWith('//')) continue; // comments may explain the rule
            expect(
              forbidden.hasMatch(l),
              isFalse,
              reason: '${f.path}:${i + 1}: $l',
            );
          }
        }
      }
    });
  });

  group('MOB2-05 application state machine (applicant moves only)', () {
    test('allowed actions per state', () {
      expect(applicantActions(ApplicationState.requested), {
        ApplicantAction.continueToPayment,
        ApplicantAction.withdraw,
      });
      expect(applicantActions(ApplicationState.awaitingDemoPayment), {
        ApplicantAction.completeDemoPayment,
        ApplicantAction.withdraw,
      });
      expect(applicantActions(ApplicationState.pendingPsychologistReview), {
        ApplicantAction.withdraw,
      });
      for (final s in [
        ApplicationState.accepted,
        ApplicationState.rejected,
        ApplicationState.withdrawn,
      ]) {
        expect(applicantActions(s), isEmpty, reason: s.wire);
        expect(s.isTerminal, isTrue);
      }
    });
    test('an illegal move never reaches the server', () async {
      final api = FakeApplicationApi()
        ..items = [request('r', 'p', state: ApplicationState.accepted)];
      final list = CareList<ConnectionRequest>(
        (_) async => const ApiPage([], null),
        idOf: (r) => r.id,
      );
      final flow = ApplicationFlow(api, list);
      await expectLater(
        flow.act(
          api.items.single,
          ApplicantAction.withdraw,
          idempotencyKey: 'k',
        ),
        throwsA(isA<IllegalTransitionError>()),
      );
      expect(api.keys, isEmpty);
    });
    test(
      'apply = create, then continue to demo payment; server state shown',
      () async {
        final api = FakeApplicationApi();
        final list = CareList<ConnectionRequest>(
          (_) async => const ApiPage([], null),
          idOf: (r) => r.id,
        );
        final r = await ApplicationFlow(
          api,
          list,
        ).apply('p', createKey: 'c', continueKey: 'n');
        expect(r.state, ApplicationState.awaitingDemoPayment);
        expect(api.keys, ['c', 'n']);
        expect(list.items.single.state, ApplicationState.awaitingDemoPayment);
      },
    );
    test('unknown wire state → item skipped, not shown half-read', () {
      final page = parseApiPage({
        'items': [
          {
            'id': 'x',
            'psychologist_uid': 'p',
            'state': 'expired',
            'demo_payment_state': 'demo_pending',
            'revision': 1,
            'created_at': '2026-10-19T08:00:00Z',
            'updated_at': '2026-10-19T08:00:00Z',
          },
        ],
        'next_cursor': null,
      }, ConnectionRequest.fromJson);
      expect(page.items, isEmpty);
    });
  });

  group('MOB2-06 appointment state machine (patient side)', () {
    test('actions per state; completed / cancelled / rejected → none', () {
      expect(
        patientAppointmentActions(appointment('a', AppointmentState.requested)),
        {PatientAppointmentAction.cancel},
      );
      expect(
        patientAppointmentActions(
          appointment(
            'a',
            AppointmentState.proposed,
            start: DateTime.utc(2026, 10, 20, 10),
          ),
        ),
        {PatientAppointmentAction.confirm, PatientAppointmentAction.cancel},
      );
      expect(
        patientAppointmentActions(appointment('a', AppointmentState.proposed)),
        {PatientAppointmentAction.cancel},
        reason: 'a proposal without times cannot be confirmed',
      );
      expect(
        patientAppointmentActions(appointment('a', AppointmentState.confirmed)),
        {
          PatientAppointmentAction.cancel,
          PatientAppointmentAction.askAnotherTime,
        },
      );
      for (final s in [
        AppointmentState.completed,
        AppointmentState.cancelled,
        AppointmentState.rejected,
      ]) {
        expect(
          patientAppointmentActions(appointment('a', s)),
          isEmpty,
          reason: s.wire,
        );
      }
    });
    test('illegal transitions are blocked before any request', () {
      for (final (from, to) in [
        (AppointmentState.requested, AppointmentState.confirmed),
        (AppointmentState.confirmed, AppointmentState.confirmed),
        (AppointmentState.completed, AppointmentState.cancelled),
        (AppointmentState.cancelled, AppointmentState.cancelled),
        (AppointmentState.rejected, AppointmentState.confirmed),
        (AppointmentState.proposed, AppointmentState.completed),
        (AppointmentState.proposed, AppointmentState.rejected),
      ]) {
        expect(
          isLegalPatientTransition(from, to),
          isFalse,
          reason: '$from→$to',
        );
        expect(
          () => checkPatientTransition(from, to),
          throwsA(isA<IllegalTransitionError>()),
        );
      }
      expect(
        isLegalPatientTransition(
          AppointmentState.proposed,
          AppointmentState.confirmed,
        ),
        isTrue,
      );
    });
    test('sections', () {
      expect(
        [
          for (final s in AppointmentState.values)
            sectionOf(appointment('a', s)),
        ],
        [
          AppointmentSection.pending,
          AppointmentSection.pending,
          AppointmentSection.upcoming,
          AppointmentSection.past,
          AppointmentSection.cancelled,
          AppointmentSection.cancelled,
        ],
      );
    });
  });

  group('MOB2-07 notifications: 4 fixed kinds, unknown ignored, deduped', () {
    test('parse + ignore', () {
      Map<String, Object?> n(String id, String kind, Map<String, Object?> r) =>
          {
            'id': id,
            'event_id': 'ev-$id',
            'kind': kind,
            'reference': r,
            'created_at': '2026-10-19T08:00:00Z',
          };
      final page = parseApiPage({
        'items': [
          n('1', 'assignment', {'assignment_id': 'a'}),
          n('2', 'new_message', {'message_id': 'm'}),
          n('3', 'appointment_change', {'appointment_id': 'p'}),
          n('4', 'application_state', {'connection_request_id': 'c'}),
          n('5', 'evaluation_ready', {'evaluation_id': 'x'}),
          n('6', 'relationship_ended', {'relationship_id': 'r'}),
          n('7', 'new_message', {'wrong': 'shape'}),
        ],
        'next_cursor': 'cur',
      }, CareNotification.fromJson);
      expect(
        [for (final x in page.items) x.kind],
        [
          NotificationKind.assignment,
          NotificationKind.newMessage,
          NotificationKind.appointmentChange,
          NotificationKind.applicationState,
        ],
      );
      expect([for (final x in page.items) x.referenceId], ['a', 'm', 'p', 'c']);
      expect(page.nextCursor, 'cur');
    });
    test('a repeated delivery (same event id) is shown once', () async {
      final api = FakeNotificationApi()
        ..items = [
          note('1', NotificationKind.assignment, 'a'),
          CareNotification(
            id: '1b',
            eventId: 'e-1',
            kind: NotificationKind.assignment,
            referenceId: 'a',
            createdAt: DateTime.utc(2026, 10, 19, 7),
          ),
        ];
      final s = _session(notifications: api);
      await s.notifications.refresh();
      expect(s.notifications.items, hasLength(1));
      s.dispose();
    });
  });

  group(
    'MOB2-08 in-memory cache: stale shown with "Updating…", then replaced',
    () {
      test('stale-while-revalidate', () async {
        var answer = ['a'];
        final gate = Completer<void>();
        var gated = false;
        final list = CareList<String>((_) async {
          if (gated) await gate.future;
          return ApiPage([...answer], null);
        }, idOf: (s) => s);
        await list.refresh();
        expect(list.items, ['a']);
        expect(list.isUpdating, isFalse);
        gated = true;
        answer = ['b', 'c'];
        final f = list.refresh();
        expect(list.isUpdating, isTrue, reason: 'cached data + Updating…');
        expect(list.items, ['a']);
        gate.complete();
        await f;
        expect(list.items, ['b', 'c']);
        expect(list.isUpdating, isFalse);
      });
      test('clear() drops everything and a late answer is ignored', () async {
        final gate = Completer<void>();
        final list = CareList<String>((_) async {
          await gate.future;
          return const ApiPage(['late'], null);
        }, idOf: (s) => s);
        final f = list.refresh();
        list.clear();
        gate.complete();
        await f;
        expect(list.items, isEmpty);
        expect(list.loaded, isFalse);
      });
      test('pagination appends the next cursor page', () async {
        final list = CareList<String>(
          (cursor) async => cursor == null
              ? const ApiPage(['1', '2'], 'next')
              : const ApiPage(['3'], null),
          idOf: (s) => s,
        );
        await list.refresh();
        expect(list.hasMore, isTrue);
        await list.loadMore();
        expect(list.items, ['1', '2', '3']);
        expect(list.hasMore, isFalse);
      });
    },
  );

  group('MOB2-09 thread: pending / sent / failed, retry, polling', () {
    test('send → pending → server message; failure → failed; retry reuses '
        'the key', () async {
      final api = FakeMessageApi();
      final t = ThreadController(api: api, relationshipId: 'r1');
      final gate = api.sendScript.gate = Completer<void>();
      final sending = t.send('  hello  ');
      expect(t.outgoing.single.status, OutgoingStatus.pending);
      expect(t.outgoing.single.body, 'hello');
      gate.complete();
      expect(await sending, isNull);
      expect(t.outgoing, isEmpty);
      expect(t.messages.single.body, 'hello');

      api.sendScript
        ..gate = null
        ..error = offlineError;
      expect(await t.send('again'), CareFailure.offline);
      final failed = t.outgoing.single;
      expect(failed.status, OutgoingStatus.failed);
      api.sendScript.error = null;
      expect(await t.retry(failed.localId), isNull);
      expect(api.sentKeys[1], api.sentKeys[2], reason: 'same key on retry');
      expect(t.outgoing, isEmpty);
      expect(t.messages, hasLength(2));
      t.dispose();
    });
    test('messages are ordered by time and merged by id', () async {
      final api = FakeMessageApi()
        ..byRelationship['r1'] = [
          HumanMessage(
            id: 'b',
            relationshipId: 'r1',
            senderUid: 'p',
            body: '2',
            createdAt: DateTime.utc(2026, 1, 2),
          ),
          HumanMessage(
            id: 'a',
            relationshipId: 'r1',
            senderUid: 'p',
            body: '1',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ];
      final t = ThreadController(api: api, relationshipId: 'r1');
      await t.list.refresh(merge: true);
      await t.list.refresh(merge: true);
      expect([for (final m in t.messages) m.id], ['a', 'b']);
      t.dispose();
    });
    test('polls only while open', () async {
      final api = FakeMessageApi();
      final t = ThreadController(
        api: api,
        relationshipId: 'r1',
        pollInterval: const Duration(milliseconds: 5),
      );
      t.startPolling();
      expect(t.isPolling, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final polled = api.listScript.calls;
      expect(polled, greaterThanOrEqualTo(2));
      t.stopPolling();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(api.listScript.calls, polled, reason: 'no polling once closed');
      t.dispose();
    });
    test('blank or over-long messages are not sent', () async {
      final api = FakeMessageApi();
      final t = ThreadController(api: api, relationshipId: 'r1');
      await t.send('   ');
      await t.send('x' * (humanMessageMaxLength + 1));
      expect(api.sentKeys, isEmpty);
      t.dispose();
    });
  });

  group('MOB2-10 session: unread counts, mark all, application outcome', () {
    test(
      'mark all loops over the per-item endpoint and stops on failure',
      () async {
        final api = FakeNotificationApi()
          ..items = [
            note('1', NotificationKind.newMessage, 'm1'),
            note('2', NotificationKind.appointmentChange, 'a1'),
            note('3', NotificationKind.assignment, 'x', read: true),
          ];
        final s = _session(notifications: api);
        await s.notifications.refresh();
        expect(s.unreadCount, 2);
        expect(s.unreadMessageNotifications, hasLength(1));
        expect(await s.markAllRead(), isNull);
        expect(s.unreadCount, 0);
        s.dispose();
      },
    );
    test('an unread application outcome re-checks capabilities once', () async {
      var refreshes = 0;
      final api = FakeNotificationApi()
        ..items = [note('1', NotificationKind.applicationState, 'c1')];
      final s = _session(
        notifications: api,
        refreshCaps: () async => refreshes++,
      );
      await s.notifications.refresh();
      await s.notifications.refresh();
      expect(refreshes, 1);
      s.dispose();
    });
    test('relationship ended → messages, appointments and patient '
        'notifications dropped; application outcomes kept', () async {
      final api = FakeNotificationApi()
        ..items = [
          note('1', NotificationKind.newMessage, 'm1'),
          note('2', NotificationKind.applicationState, 'c1'),
        ];
      final s = _session(notifications: api);
      await s.notifications.refresh();
      await s.thread('rel-1').list.refresh();
      await s.appointmentsFor('rel-1').refresh();
      expect(s.hasPatientData, isTrue);
      s.clearPatientData();
      expect(s.hasPatientData, isFalse);
      expect(s.existingThread('rel-1'), isNull);
      expect([for (final n in s.notifications.items) n.id], ['2']);
      s.dispose();
    });
  });

  group('MOB2-11 a 403 re-checks capabilities at most once per cooldown', () {
    test('never loops', () async {
      var now = DateTime(2026, 10, 19, 10);
      final auth = AccountFakeAuth(
        fakeUser: AccountFakeAuth.registered('p1', 'p@x'),
      );
      final source = ScriptedCapabilitiesSource({'p1': patientCaps});
      final c = CapabilityController(
        auth: auth,
        source: source,
        now: () => now,
      );
      await pumpEventQueue();
      expect(source.fetches, 1);
      for (var i = 0; i < 5; i++) {
        c.onForbidden();
        await pumpEventQueue();
      }
      expect(source.fetches, 2, reason: 'one re-check for a burst of 403s');
      now = now.add(const Duration(seconds: 11));
      c.onForbidden();
      await pumpEventQueue();
      expect(source.fetches, 3);
      c.dispose();
    });
    test('a re-check keeps the shell (gates default-deny); a first check '
        'or a psychologist re-check shows the full-screen check', () async {
      RootRoute route({required bool recheck}) => resolveRootRoute(
        restored: true,
        loading: false,
        signedIn: true,
        onboardingComplete: true,
        registered: true,
        capabilities: CapabilityStatus.loading,
        capabilityRecheck: recheck,
      );
      expect(route(recheck: false), RootRoute.capabilityCheck);
      expect(route(recheck: true), RootRoute.chat);
      Future<bool> recheckOf(KoiCapabilities caps) async {
        final auth = AccountFakeAuth(
          fakeUser: AccountFakeAuth.registered('x1', 'x@x'),
        );
        final source = ScriptedCapabilitiesSource({'x1': caps});
        final c = CapabilityController(auth: auth, source: source);
        expect(c.isRecheck, isFalse, reason: 'first check');
        await pumpEventQueue();
        source.gate = Completer<void>();
        c.onForbidden();
        await pumpEventQueue();
        final r = c.isRecheck;
        expect(c.effective.hasCareArea, isFalse, reason: 'still default-deny');
        source.gate!.complete();
        await pumpEventQueue();
        c.dispose();
        return r;
      }

      expect(await recheckOf(patientCaps), isTrue);
      expect(await recheckOf(psychologistCaps), isFalse);
    });
  });

  group('MOB2-12 English / Urdu table and local time', () {
    test('every string exists in both languages and is not empty', () {
      for (final k in CareText.values) {
        for (final lang in CareLang.values) {
          expect(
            CareStrings.table(lang)[k],
            isNotNull,
            reason: '${lang.name}:${k.name}',
          );
          expect(CareStrings.table(lang)[k]!.trim(), isNotEmpty);
        }
      }
      expect(CareStrings.ur.direction, TextDirection.rtl);
      expect(CareStrings.en.direction, TextDirection.ltr);
      expect(CareStrings.ur.t(CareText.safetyFooter).contains('1166'), isTrue);
    });
    test('times are shown in the phone time zone', () {
      final utc = DateTime.utc(2026, 10, 20, 5, 7);
      final local = utc.toLocal();
      final text = CareStrings.en.dateTime(utc);
      expect(
        text.endsWith(
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}',
        ),
        isTrue,
      );
      expect(text, contains('${local.day}'));
    });
  });

  group('MOB2-13 expert search (client-side, over loaded pages)', () {
    const list = MockExpertDirectoryApi.profiles;
    test('name and accepting filters', () {
      expect(filterExperts(list, query: ' psychologist b '), [list[1]]);
      expect(filterExperts(list, acceptingOnly: true), [list[0], list[2]]);
      expect(filterExperts(list, query: 'zzz'), isEmpty);
    });
  });

  group('MOB2-14 one active application per psychologist', () {
    const e = ExpertProfile(
      id: 'p',
      displayName: 'P',
      bio: '',
      acceptingNewPatients: true,
    );
    ApplyGuardKind kind(List<ConnectionRequest> apps, {Set<String>? c}) =>
        applyGuard(
          e,
          applications: apps,
          connectedPsychologists: c ?? const {},
        ).kind;
    test('rules', () {
      expect(kind(const []), ApplyGuardKind.canApply);
      expect(
        kind([
          request('r', 'p', state: ApplicationState.pendingPsychologistReview),
        ]),
        ApplyGuardKind.activeApplication,
      );
      expect(
        kind([request('r', 'p', state: ApplicationState.withdrawn)]),
        ApplyGuardKind.appliedBefore,
      );
      expect(
        kind([request('r', 'p', state: ApplicationState.accepted)]),
        ApplyGuardKind.alreadyConnected,
      );
      expect(kind(const [], c: {'p'}), ApplyGuardKind.alreadyConnected);
      expect(
        kind([request('r', 'other')]),
        ApplyGuardKind.canApply,
        reason: 'another psychologist does not block',
      );
      expect(
        applyGuard(
          const ExpertProfile(
            id: 'p',
            displayName: 'P',
            bio: '',
            acceptingNewPatients: false,
          ),
          applications: const [],
          connectedPsychologists: const {},
        ).kind,
        ApplyGuardKind.notAccepting,
      );
    });
  });

  group(
    'MOB2-15 "Simulate psychologist" only with kDebugMode AND KOI_MOCKS',
    () {
      test('gate', () {
        expect(
          simulatePsychologistMenuAllowed(debug: true, mocks: true),
          isTrue,
        );
        expect(
          simulatePsychologistMenuAllowed(debug: false, mocks: true),
          isFalse,
        );
        expect(
          simulatePsychologistMenuAllowed(debug: true, mocks: false),
          isFalse,
        );
        expect(
          simulatePsychologistMenuAllowed(debug: false, mocks: false),
          isFalse,
        );
        expect(
          simulatePsychologistMenuAllowed(),
          isFalse,
          reason: 'tests run without KOI_MOCKS',
        );
      });
    },
  );
}
