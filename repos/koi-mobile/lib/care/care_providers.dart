import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/capabilities.dart';
import '../account/capability_controller.dart';
import '../app/providers.dart';
import '../applications/application_api.dart';
import '../appointments/appointment_api.dart';
import '../care_messages/message_api.dart';
import '../invitations/invitation_api.dart';
import '../notifications/notification_api.dart';
import '../platform/platform_config.dart';
import 'care_session.dart';
import 'mock_care_backend.dart';

/// The debug-only "Simulate psychologist" menu: kDebugMode AND KOI_MOCKS,
/// never in a release build (extra rule 1).
bool simulatePsychologistMenuAllowed({
  bool debug = kDebugMode,
  bool mocks = koiMocksEnabled,
}) => debug && mocks;

final simulatePsychologistMenuProvider = Provider<bool>(
  (ref) => simulatePsychologistMenuAllowed(),
);

/// KOI_MOCKS only: the shared demo server.
final mockCareBackendProvider = Provider<MockCareBackend>((ref) {
  final source = ref.read(capabilitiesSourceProvider);
  return MockCareBackend(
    currentUid: () => ref.read(authServiceProvider).user?.uid,
    capabilities: source is MockCapabilitiesSource ? source : null,
  );
});

/// Adapter selection, like MOB-1: mock (KOI_MOCKS) > real (KOI_PLATFORM_BASE)
/// > unavailable (a calm "Not available yet", never fake data).
T pickCareAdapter<T>({
  required bool mocks,
  required bool configured,
  required T Function() mock,
  required T Function() real,
  required T unavailable,
}) => mocks
    ? mock()
    : configured
    ? real()
    : unavailable;

final applicationApiProvider = Provider<ApplicationApi>((ref) {
  final client = ref.read(platformClientProvider);
  return pickCareAdapter<ApplicationApi>(
    mocks: koiMocksEnabled,
    configured: client.isConfigured,
    mock: () => MockApplicationApi(ref.read(mockCareBackendProvider)),
    real: () => HttpApplicationApi(client),
    unavailable: const UnavailableApplicationApi(),
  );
});

final careMessageApiProvider = Provider<CareMessageApi>((ref) {
  final client = ref.read(platformClientProvider);
  return pickCareAdapter<CareMessageApi>(
    mocks: koiMocksEnabled,
    configured: client.isConfigured,
    mock: () => MockCareMessageApi(ref.read(mockCareBackendProvider)),
    real: () => HttpCareMessageApi(client),
    unavailable: const UnavailableCareMessageApi(),
  );
});

final appointmentApiProvider = Provider<AppointmentApi>((ref) {
  final client = ref.read(platformClientProvider);
  return pickCareAdapter<AppointmentApi>(
    mocks: koiMocksEnabled,
    configured: client.isConfigured,
    mock: () => MockAppointmentApi(ref.read(mockCareBackendProvider)),
    real: () => HttpAppointmentApi(client),
    unavailable: const UnavailableAppointmentApi(),
  );
});

final notificationApiProvider = Provider<NotificationApi>((ref) {
  final client = ref.read(platformClientProvider);
  return pickCareAdapter<NotificationApi>(
    mocks: koiMocksEnabled,
    configured: client.isConfigured,
    mock: () => MockNotificationApi(ref.read(mockCareBackendProvider)),
    real: () => HttpNotificationApi(client),
    unavailable: const UnavailableNotificationApi(),
  );
});

final invitationApiProvider = Provider<InvitationApi>((ref) {
  final client = ref.read(platformClientProvider);
  return pickCareAdapter<InvitationApi>(
    mocks: koiMocksEnabled,
    configured: client.isConfigured,
    mock: () => MockInvitationApi(ref.read(mockCareBackendProvider)),
    real: () => HttpInvitationApi(client),
    unavailable: const UnavailableInvitationApi(),
  );
});

/// The signed-in REGISTERED uid, or null (anonymous / signed out).
final careUidProvider = Provider<String?>((ref) {
  final user = ref.watch(authServiceProvider.select((a) => a.user));
  return user == null || user.isAnonymous ? null : user.uid;
});

/// All MOB-2 state of the current uid. Rebuilt (and the old one disposed)
/// whenever the uid changes, so nothing leaks between accounts. When the
/// patient relationship(s) end, the professional caches are dropped at once.
final careSessionProvider = ChangeNotifierProvider<CareSession>((ref) {
  final uid = ref.watch(careUidProvider) ?? '';
  final caps = ref.read(capabilityControllerProvider);
  final session = CareSession(
    uid: uid,
    expertApi: ref.read(expertDirectoryApiProvider),
    applicationApi: ref.read(applicationApiProvider),
    messageApi: ref.read(careMessageApiProvider),
    appointmentApi: ref.read(appointmentApiProvider),
    notificationApi: ref.read(notificationApiProvider),
    refreshCapabilities: () => caps.refresh(silent: true),
  );
  var active = _activeIds(caps.effective);
  var fetchedInbox = false;
  void onCaps() {
    // Mid re-check everything reads as none (default-deny): wait for the
    // answer before dropping any cache.
    if (caps.status == CapabilityStatus.loading) return;
    final now = _activeIds(caps.effective);
    if (active.difference(now).isNotEmpty) {
      session.clearPatientData(keepRelationships: now);
    }
    active = now;
    // The bell needs its unread count once a Care area is confirmed.
    if (!fetchedInbox && caps.effective.hasCareArea) {
      fetchedInbox = true;
      unawaited(session.notifications.refresh());
    }
  }

  caps.addListener(onCaps);
  onCaps();
  final lifecycle = AppLifecycleListener(onResume: session.onResume);
  ref.onDispose(() {
    caps.removeListener(onCaps);
    lifecycle.dispose();
  });
  return session;
});

Set<String> _activeIds(KoiCapabilities c) => {
  for (final r in c.activeRelationships) r.id,
};

/// The psychologist's display name for a relationship: the contract's
/// capabilities carry only the uid, so it comes from the directory
/// (`GET /experts/{uid}`); null when that is unavailable. Fixtures that
/// still carry a name (MOB-1 shape) use it directly.
final psychologistNameProvider = FutureProvider.autoDispose
    .family<String?, RelationshipSummary>((ref, rel) async {
      ref.watch(careUidProvider);
      final known = rel.psychologistDisplayName;
      if (known != null && known.isNotEmpty) return known;
      if (rel.psychologistUid.isEmpty) return null;
      try {
        return (await ref
                .read(expertDirectoryApiProvider)
                .detail(rel.psychologistUid))
            .displayName;
      } catch (_) {
        return null;
      }
    });
