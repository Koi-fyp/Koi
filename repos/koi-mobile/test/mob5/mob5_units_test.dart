import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/account/capability_controller.dart';
import 'package:koi_mobile/account/destinations.dart';
import 'package:koi_mobile/applications/application_labels.dart';
import 'package:koi_mobile/applications/application_models.dart';
import 'package:koi_mobile/care/care_providers.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/theme/koi_colors.dart';

import '../support/mob1_fakes.dart';

// MOB-5 units: the web's care-state.ts labels, the optional
// organization_id, the info-only destination, the one-time "ended" notice,
// the strings, and the debug-only demo controls.

const _rel = RelationshipSummary(
  id: 'rel-1',
  active: true,
  organizationId: 'org-1',
  psychologistUid: 'psy-1',
);

const _patient = KoiCapabilities(
  role: KoiRole.patient,
  expertDiscovery: true,
  questionnaires: true,
  relationship: _rel,
);

ConnectionRequest _app(ApplicationState state, {String? org = 'org-1'}) =>
    ConnectionRequest(
      id: 'r1',
      psychologistUid: 'psy-1',
      organizationId: org,
      state: state,
      demoPayment: DemoPaymentState.pending,
      revision: 1,
      createdAt: DateTime.utc(2026, 10, 21),
      updatedAt: DateTime.utc(2026, 10, 21),
    );

Map<String, Object?> _wire(Object? org, {bool include = true}) => {
  'id': 'r1',
  'psychologist_uid': 'psy-1',
  'state': 'accepted',
  'demo_payment_state': 'demo_completed',
  'revision': 3,
  'created_at': '2026-10-21T08:00:00.000Z',
  'updated_at': '2026-10-21T09:00:00.000Z',
  if (include) 'organization_id': org,
};

void main() {
  const en = CareStrings.en;

  test('MOB5-01 every application label is the web care-state.ts text, '
      'word for word', () {
    // origin/feat/koi2-ui-overhaul f9ed940 lib/platform/care-state.ts.
    const web = {
      ApplicationState.requested: 'Application submitted',
      ApplicationState.awaitingDemoPayment: 'Demo step required',
      ApplicationState.pendingPsychologistReview: 'Waiting for practice review',
      ApplicationState.rejected: 'Application declined',
      ApplicationState.withdrawn: 'Application withdrawn',
    };
    for (final e in web.entries) {
      expect(applicationLabel(en, _app(e.key), _patient), e.value);
      expect(applicationLabel(en, _app(e.key), generalCaps), e.value);
    }
    expect(
      applicationLabel(en, _app(ApplicationState.accepted), _patient),
      'Application accepted · Your care is active',
    );
    expect(
      applicationLabel(en, _app(ApplicationState.accepted), generalCaps),
      'Application accepted previously',
    );
  });

  test('MOB5-02 "care is active" needs the SAME practice and psychologist in '
      'the confirmed capabilities; without organization_id the psychologist '
      'alone is matched', () {
    final accepted = _app(ApplicationState.accepted);
    expect(acceptedIntoActiveCare(accepted, _patient), isTrue);
    expect(
      acceptedIntoActiveCare(
        _app(ApplicationState.accepted, org: 'org-OTHER'),
        _patient,
      ),
      isFalse,
      reason: 'another practice of the same psychologist',
    );
    expect(
      acceptedIntoActiveCare(
        _app(ApplicationState.accepted, org: null),
        _patient,
      ),
      isTrue,
      reason: 'fallback: psychologist_uid',
    );
    const otherPsy = KoiCapabilities(
      role: KoiRole.patient,
      expertDiscovery: true,
      relationship: RelationshipSummary(
        id: 'rel-2',
        active: true,
        organizationId: 'org-1',
        psychologistUid: 'psy-2',
      ),
    );
    expect(acceptedIntoActiveCare(accepted, otherPsy), isFalse);
    expect(acceptedIntoActiveCare(accepted, KoiCapabilities.none), isFalse);
    // A relationship object without the patient role grants nothing.
    const notPatient = KoiCapabilities(
      role: KoiRole.general,
      expertDiscovery: true,
      relationship: _rel,
    );
    expect(acceptedIntoActiveCare(accepted, notPatient), isFalse);
    expect(
      acceptedIntoActiveCare(_app(ApplicationState.requested), _patient),
      isFalse,
    );
    expect(applicationChipColor(accepted, _patient), KoiColors.neoMint);
    expect(applicationChipColor(accepted, generalCaps), KoiColors.neoGray);
  });

  test('MOB5-03 organization_id is optional and tolerant (absent, null, '
      'empty, not a string → null); nothing else changes', () {
    expect(ConnectionRequest.fromJson(_wire('org-9')).organizationId, 'org-9');
    for (final w in [
      _wire(null, include: false),
      _wire(null),
      _wire(''),
      _wire(42),
      _wire(const {'x': 1}),
    ]) {
      final r = ConnectionRequest.fromJson(w);
      expect(r.organizationId, isNull);
      expect(r.state, ApplicationState.accepted);
      expect(r.revision, 3);
    }
  });

  test('MOB5-04 helper lines per state (PatientWorkspace.tsx / '
      'PracticeApplication.tsx)', () {
    expect(
      applicationNote(
        _app(ApplicationState.pendingPsychologistReview),
        _patient,
      ),
      CareText.m5PendingReviewNote,
    );
    expect(
      applicationNote(_app(ApplicationState.accepted), _patient),
      CareText.m5AcceptedActiveNote,
    );
    expect(
      applicationNote(_app(ApplicationState.accepted), generalCaps),
      CareText.m5AcceptedPreviousNote,
    );
    expect(
      applicationNote(_app(ApplicationState.rejected), generalCaps),
      CareText.declinedNote,
    );
    for (final s in [
      ApplicationState.requested,
      ApplicationState.awaitingDemoPayment,
      ApplicationState.withdrawn,
    ]) {
      expect(applicationNote(_app(s), generalCaps), isNull);
    }
    expect(
      en.t(CareText.m5PendingReviewNote),
      'Your demo step is complete. The practice will accept or decline your '
      'application. Check notifications for updates.',
    );
    expect(
      en.t(CareText.m5AcceptedPreviousNote),
      'This application was accepted previously. No active care relationship '
      'is currently available for this practice. Application history does '
      'not grant patient access.',
    );
  });

  test('MOB5-05 "Become a Psychologist" is allowed only with a confirmed '
      'Care area and is never reachable from a link', () {
    LinkDecision d(CapabilityStatus s, KoiCapabilities c) => decideDestination(
      KoiDestination.becomePsychologist,
      status: s,
      caps: c,
    );
    expect(
      d(CapabilityStatus.anonymous, KoiCapabilities.none),
      LinkDecision.signIn,
    );
    expect(
      d(CapabilityStatus.loading, KoiCapabilities.none),
      LinkDecision.wait,
    );
    expect(d(CapabilityStatus.ready, generalCaps), LinkDecision.allow);
    expect(d(CapabilityStatus.ready, _patient), LinkDecision.allow);
    expect(d(CapabilityStatus.ready, psychologistCaps), LinkDecision.deny);
    expect(
      d(
        CapabilityStatus.ready,
        const KoiCapabilities(
          role: KoiRole.anonymous,
          accountState: AccountState.unregistered,
        ),
      ),
      LinkDecision.deny,
    );
    for (final link in [
      'koi://care/become-psychologist',
      'koi://become-psychologist',
      'koi://care/psychologist/register',
    ]) {
      expect(
        parseKoiLink(Uri.parse(link)).destination,
        isNot(KoiDestination.becomePsychologist),
      );
    }
  });

  test('MOB5-06 the "previous care relationship has ended" notice: after '
      'the access-ended screen, once, dismissable; cleared by a new '
      'relationship and by an account change', () async {
    final auth = AccountFakeAuth(
      fakeUser: AccountFakeAuth.registered('p1', 'p@x'),
    );
    final source = ScriptedCapabilitiesSource({'p1': patientCaps});
    final c = CapabilityController(auth: auth, source: source);
    await pumpEventQueue();
    expect(c.effective.isPatient, isTrue);
    expect(c.endedNotice, isFalse);

    source.byUid['p1'] = generalCaps;
    await c.refresh();
    expect(c.accessEnded, isTrue);
    expect(c.endedNotice, isFalse, reason: 'not while the screen shows');
    c.acknowledgeAccessEnded();
    expect(c.endedNotice, isTrue);
    await c.refresh();
    expect(c.endedNotice, isTrue, reason: 'stays until dismissed');
    c.dismissEndedNotice();
    expect(c.endedNotice, isFalse);
    await c.refresh();
    expect(c.endedNotice, isFalse, reason: 'shown once');

    // Ended again, then a new relationship: the notice goes.
    source.byUid['p1'] = patientCaps;
    await c.refresh();
    source.byUid['p1'] = generalCaps;
    await c.refresh();
    c.acknowledgeAccessEnded();
    expect(c.endedNotice, isTrue);
    source.byUid['p1'] = patientCaps;
    await c.refresh();
    expect(c.endedNotice, isFalse);

    // Ended, then another account signs in: never carried over.
    source.byUid['p1'] = generalCaps;
    await c.refresh();
    c.acknowledgeAccessEnded();
    expect(c.endedNotice, isTrue);
    source.byUid['g2'] = generalCaps;
    auth.set(user: AccountFakeAuth.registered('g2', 'g2@x'));
    await pumpEventQueue();
    expect(c.endedNotice, isFalse);
    c.dispose();
  });

  test('MOB5-07 every MOB-5 string exists in English and Urdu; the removed '
      '"pull down" accepted note is gone', () {
    final m5 = CareText.values.where((k) => k.name.startsWith('m5'));
    expect(m5.length, 24);
    for (final k in [
      ...m5,
      CareText.findExpert,
      CareText.findExpertSub,
      CareText.myApplications,
      CareText.notificationsSub,
      CareText.stateRequested,
      CareText.stateAwaitingPayment,
      CareText.statePendingReview,
      CareText.stateAccepted,
      CareText.stateDeclined,
      CareText.stateWithdrawn,
    ]) {
      expect(CareStrings.table(CareLang.en)[k], isNotEmpty, reason: k.name);
      expect(CareStrings.table(CareLang.ur)[k], isNotEmpty, reason: k.name);
      expect(
        CareStrings.table(CareLang.ur)[k],
        isNot(CareStrings.table(CareLang.en)[k]),
        reason: '${k.name} is translated',
      );
    }
    expect(CareText.values.map((k) => k.name), isNot(contains('acceptedNote')));
    expect(en.t(CareText.m5CareHome), 'Care Home');
    expect(en.t(CareText.m5MyCare), 'My Care');
    expect(en.t(CareText.findExpert), 'Find a Psychologist');
    expect(en.t(CareText.myApplications), 'My Applications');
    expect(
      en.t(CareText.m5BecomeBody),
      'Psychologist accounts are created and verified on the KOI website.',
    );
    expect(en.awaitingCount(2), '2 awaiting completion');
  });

  test('MOB5-08 the Simulate menu needs debug AND KOI_MOCKS: never in a '
      'release or a normal (non-mock) build; the demo badge follows the '
      'mock source only', () {
    expect(simulatePsychologistMenuAllowed(debug: true, mocks: true), isTrue);
    expect(simulatePsychologistMenuAllowed(debug: false, mocks: true), isFalse);
    expect(simulatePsychologistMenuAllowed(debug: true, mocks: false), isFalse);
    expect(
      simulatePsychologistMenuAllowed(debug: false, mocks: false),
      isFalse,
    );
    // Test builds have no KOI_MOCKS: the real provider value is false.
    expect(simulatePsychologistMenuAllowed(), isFalse);
    expect(ScriptedCapabilitiesSource().isMock, isFalse);
    expect(MockCapabilitiesSource().isMock, isTrue);
  });
}
