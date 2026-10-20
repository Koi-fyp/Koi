import 'capabilities.dart';
import 'capability_controller.dart';

/// Every place a link (or a notification later) can point to. The app has
/// no OS deep-link intake yet; Care navigation and any future intake go
/// through [decideDestination], so the guard is the same everywhere.
enum KoiDestination {
  companion,
  signIn,
  experts,
  expert,
  care,
  myPsychologist,
  questionnaires,
  questionnaire,
  messages,
  appointments,
  notifications,
  proPortal,

  /// MOB-2: the applicant's own connection requests (General / Patient).
  applications,
  application,

  /// MOB-2: one professional message thread / one appointment (Patient).
  messageThread,
  appointment,

  /// MOB-4: "I have an invitation code" (General / Patient). Deliberately
  /// NOT reachable from a `koi://` link: a link would carry the token.
  invitation,
}

/// `koi://experts/{id}`, `koi://care/questionnaires/{attemptId}`, ...
/// Unknown links go to the companion (never an error page that leaks).
({KoiDestination destination, String? id}) parseKoiLink(Uri uri) {
  final parts = [
    if (uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments.where((s) => s.isNotEmpty),
  ];
  String? at(int i) => parts.length > i ? parts[i] : null;
  return switch (parts) {
    ['experts'] => (destination: KoiDestination.experts, id: null),
    ['experts', _] => (destination: KoiDestination.expert, id: at(1)),
    ['care'] => (destination: KoiDestination.care, id: null),
    ['care', 'psychologist'] => (
      destination: KoiDestination.myPsychologist,
      id: null,
    ),
    ['care', 'questionnaires'] => (
      destination: KoiDestination.questionnaires,
      id: null,
    ),
    ['care', 'questionnaires', _] => (
      destination: KoiDestination.questionnaire,
      id: at(2),
    ),
    ['care', 'messages'] => (destination: KoiDestination.messages, id: null),
    ['care', 'messages', _] => (
      destination: KoiDestination.messageThread,
      id: at(2),
    ),
    ['care', 'appointments', _] => (
      destination: KoiDestination.appointment,
      id: at(2),
    ),
    ['care', 'applications'] => (
      destination: KoiDestination.applications,
      id: null,
    ),
    ['care', 'applications', _] => (
      destination: KoiDestination.application,
      id: at(2),
    ),
    ['care', 'appointments'] => (
      destination: KoiDestination.appointments,
      id: null,
    ),
    ['care', 'notifications'] => (
      destination: KoiDestination.notifications,
      id: null,
    ),
    ['portal'] => (destination: KoiDestination.proPortal, id: null),
    ['sign-in'] => (destination: KoiDestination.signIn, id: null),
    _ => (destination: KoiDestination.companion, id: null),
  };
}

enum LinkDecision {
  /// Open it.
  allow,

  /// Capabilities are still being confirmed: hold the link, show nothing
  /// protected.
  wait,

  /// Not for this account: open the companion (or the psychologist
  /// landing) instead.
  deny,

  /// Needs a registered account: offer sign in.
  signIn,
}

/// The single route guard. Client hiding never replaces the backend's own
/// authorization; this only keeps screens from appearing.
LinkDecision decideDestination(
  KoiDestination d, {
  required CapabilityStatus status,
  required KoiCapabilities caps,
}) {
  final registered =
      status == CapabilityStatus.loading ||
      status == CapabilityStatus.ready ||
      status == CapabilityStatus.unavailable;
  switch (d) {
    case KoiDestination.companion:
      return caps.isPsychologist ? LinkDecision.deny : LinkDecision.allow;
    case KoiDestination.signIn:
      return registered ? LinkDecision.deny : LinkDecision.allow;
    case KoiDestination.proPortal:
      if (status == CapabilityStatus.loading) return LinkDecision.wait;
      return caps.isPsychologist ? LinkDecision.allow : LinkDecision.deny;
    case KoiDestination.experts ||
        KoiDestination.expert ||
        KoiDestination.care ||
        KoiDestination.myPsychologist ||
        KoiDestination.questionnaires ||
        KoiDestination.questionnaire ||
        KoiDestination.messages ||
        KoiDestination.appointments ||
        KoiDestination.notifications ||
        KoiDestination.applications ||
        KoiDestination.application ||
        KoiDestination.messageThread ||
        KoiDestination.appointment ||
        KoiDestination.invitation:
      if (!registered) return LinkDecision.signIn;
      if (status == CapabilityStatus.loading) return LinkDecision.wait;
      final ok = switch (d) {
        KoiDestination.experts ||
        KoiDestination.expert => caps.canDiscoverExperts,
        // MOB-4: redeem needs General access (lifecycle.ts:113), which a
        // confirmed Care area implies.
        KoiDestination.care || KoiDestination.invitation => caps.hasCareArea,
        KoiDestination.questionnaires ||
        KoiDestination.questionnaire => caps.canUseQuestionnaires,
        // MOB-2: application outcomes reach General users too.
        KoiDestination.notifications => caps.hasCareArea,
        KoiDestination.applications ||
        KoiDestination.application => caps.canDiscoverExperts,
        _ => caps.isPatient,
      };
      return ok ? LinkDecision.allow : LinkDecision.deny;
  }
}
