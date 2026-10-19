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
        KoiDestination.notifications:
      if (!registered) return LinkDecision.signIn;
      if (status == CapabilityStatus.loading) return LinkDecision.wait;
      final ok = switch (d) {
        KoiDestination.experts ||
        KoiDestination.expert => caps.canDiscoverExperts,
        KoiDestination.care => caps.hasCareArea,
        KoiDestination.questionnaires ||
        KoiDestination.questionnaire => caps.canUseQuestionnaires,
        _ => caps.isPatient,
      };
      return ok ? LinkDecision.allow : LinkDecision.deny;
  }
}
