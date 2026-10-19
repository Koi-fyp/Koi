import 'package:flutter/foundation.dart';

import '../platform/platform_client.dart';

/// KOI 2.0 roles (KOI_MOBILE_TRACK_FINAL_REVIEWED.md §1). The role is ONLY
/// what the backend says; nothing in Flutter (prefs, claims cached on the
/// device, a payment marker) can grant one.
enum KoiRole {
  /// No registered privileges: signed-out, Firebase `isAnonymous`, or the
  /// capabilities could not be confirmed (default-deny).
  anonymous,
  general,

  /// General + an ACTIVE, server-verified psychologist relationship.
  patient,
  psychologist;

  static KoiRole fromWire(Object? v) => switch (v) {
    'general' => general,
    'patient' => patient,
    'psychologist' => psychologist,
    _ => anonymous, // unknown → no privileges
  };
}

/// The patient's relationship as the backend reports it. No clinical,
/// evaluation or review data: only what the patient may see.
@immutable
class RelationshipSummary {
  const RelationshipSummary({
    required this.id,
    required this.active,
    required this.psychologistDisplayName,
  });

  final String id;

  /// `status == 'active'`; anything else (ended, revoked, pending) is false.
  final bool active;
  final String psychologistDisplayName;

  static RelationshipSummary? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, Object?>();
    final id = j['id'];
    final name = j['psychologist_display_name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    return RelationshipSummary(
      id: id,
      active: j['status'] == 'active',
      psychologistDisplayName: name,
    );
  }
}

/// PROVISIONAL `GET /api/v1/me/capabilities` response (no web contract
/// yet; see KOI_MOB1_PROVISIONAL_CONTRACTS.md):
///
/// ```json
/// {"uid": "...", "role": "general|patient|psychologist",
///  "capabilities": {"expert_discovery": true, "questionnaires": true},
///  "relationship": {"id": "...", "status": "active",
///                   "psychologist_display_name": "..."}}
/// ```
///
/// Every privilege needs BOTH the right role and the server's flag; a
/// missing flag is false.
@immutable
class KoiCapabilities {
  const KoiCapabilities({
    required this.role,
    this.expertDiscovery = false,
    this.questionnaires = false,
    this.relationship,
  });

  /// Default-deny: no registered privileges at all.
  static const KoiCapabilities none = KoiCapabilities(role: KoiRole.anonymous);

  final KoiRole role;
  final bool expertDiscovery;
  final bool questionnaires;
  final RelationshipSummary? relationship;

  bool get isPsychologist => role == KoiRole.psychologist;

  /// General or patient, with the server's discovery flag.
  bool get canDiscoverExperts =>
      (role == KoiRole.general || role == KoiRole.patient) && expertDiscovery;

  /// An active relationship confirmed by the server.
  bool get isPatient =>
      role == KoiRole.patient && (relationship?.active ?? false);

  bool get canUseQuestionnaires => isPatient && questionnaires;

  /// Any registered (General / Patient) area at all.
  bool get hasCareArea => canDiscoverExperts || isPatient;

  /// Parses the response for [uid]; a response for another uid is
  /// rejected (never trust a cached / mixed-up answer).
  factory KoiCapabilities.fromJson(Object? body, {required String uid}) {
    final j = asJsonMap(body, 'capabilities');
    if (j['uid'] != uid) throw const FormatException('uid mismatch');
    final flags = j['capabilities'] is Map
        ? (j['capabilities']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return KoiCapabilities(
      role: KoiRole.fromWire(j['role']),
      expertDiscovery: flags['expert_discovery'] == true,
      questionnaires: flags['questionnaires'] == true,
      relationship: RelationshipSummary.fromJson(j['relationship']),
    );
  }
}

/// Where capabilities come from.
abstract interface class CapabilitiesSource {
  /// Demo data (KOI_MOCKS): screens show the "Demo data" badge.
  bool get isMock;

  Future<KoiCapabilities> fetch(String uid);
}

class HttpCapabilitiesSource implements CapabilitiesSource {
  HttpCapabilitiesSource(this.client);
  final PlatformClient client;

  static const String path = '/api/v1/me/capabilities';

  @override
  bool get isMock => false;

  @override
  Future<KoiCapabilities> fetch(String uid) async =>
      KoiCapabilities.fromJson(await client.getJson(path), uid: uid);
}

/// KOI_MOCKS=true only. The role comes from [role], which the debug-only
/// role picker changes; release builds keep the default.
class MockCapabilitiesSource implements CapabilitiesSource {
  MockCapabilitiesSource({KoiRole initial = KoiRole.general})
    : role = ValueNotifier(initial);

  final ValueNotifier<KoiRole> role;

  static const RelationshipSummary demoRelationship = RelationshipSummary(
    id: 'demo-relationship-1',
    active: true,
    psychologistDisplayName: 'Demo Psychologist',
  );

  @override
  bool get isMock => true;

  @override
  Future<KoiCapabilities> fetch(String uid) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return switch (role.value) {
      KoiRole.anonymous => KoiCapabilities.none,
      KoiRole.general => const KoiCapabilities(
        role: KoiRole.general,
        expertDiscovery: true,
      ),
      KoiRole.patient => const KoiCapabilities(
        role: KoiRole.patient,
        expertDiscovery: true,
        questionnaires: true,
        relationship: demoRelationship,
      ),
      KoiRole.psychologist => const KoiCapabilities(role: KoiRole.psychologist),
    };
  }
}

/// Used when KOI_PLATFORM_BASE is empty and mocks are off: nothing can be
/// confirmed, so every registered privilege stays closed.
class UnavailableCapabilitiesSource implements CapabilitiesSource {
  const UnavailableCapabilitiesSource();

  @override
  bool get isMock => false;

  @override
  Future<KoiCapabilities> fetch(String uid) =>
      Future.error(const PlatformException(PlatformErrorCode.notConfigured));
}
