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
///
/// Contract v0.5.1 `CapabilitiesDTO.active_patient_relationships[]` carries
/// only ids; the psychologist's name is looked up separately
/// (`GET /api/v1/experts/{psychologist_uid}`, lib/care/psychologist_name.dart).
@immutable
class RelationshipSummary {
  const RelationshipSummary({
    required this.id,
    required this.active,
    this.psychologistDisplayName,
    this.organizationId = '',
    this.psychologistUid = '',
  });

  final String id;

  /// Every relationship the contract lists is active; a relationship that
  /// ended or was closed simply disappears from the list.
  final bool active;

  /// Never sent by the contract. Only test fixtures / the MOB-1 shape set it.
  final String? psychologistDisplayName;
  final String organizationId;
  final String psychologistUid;

  @override
  bool operator ==(Object other) =>
      other is RelationshipSummary &&
      other.id == id &&
      other.active == active &&
      other.psychologistDisplayName == psychologistDisplayName &&
      other.organizationId == organizationId &&
      other.psychologistUid == psychologistUid;

  @override
  int get hashCode => Object.hash(
    id,
    active,
    psychologistDisplayName,
    organizationId,
    psychologistUid,
  );

  static RelationshipSummary? fromContract(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, Object?>();
    final id = j['relationship_id'];
    final org = j['organization_id'];
    final psy = j['psychologist_uid'];
    if (id is! String || id.isEmpty || org is! String || psy is! String) {
      return null;
    }
    return RelationshipSummary(
      id: id,
      active: true,
      organizationId: org,
      psychologistUid: psy,
    );
  }
}

/// `GET /api/v1/me/capabilities`: REAL on
/// origin/feat/web-1-professional-publishing (http.ts:40 → service.ts:54),
/// contract v0.5.1 `CapabilitiesDTO` (`contract_version` "0.5.0"):
///
/// ```json
/// {"contract_version": "0.5.0", "uid": "...",
///  "account_state": "unregistered|registered|suspended|closed",
///  "authorization_revision": 3,
///  "capabilities": {"companion_account_sync": true, "expert_directory": true,
///                   "professional_workspace": false,
///                   "create_organization": false},
///  "professional_organization_ids": [],
///  "active_patient_relationships": [{"relationship_id": "...",
///      "organization_id": "...", "psychologist_uid": "..."}]}
/// ```
///
/// The contract has no `role`; mobile derives one:
/// - not `registered` → [KoiRole.anonymous] (no privileges);
/// - `professional_workspace` → [KoiRole.psychologist] (portal landing);
/// - at least one active relationship → [KoiRole.patient];
/// - otherwise → [KoiRole.general].
/// Discovery still needs the server's `expert_directory` flag. The contract
/// has no questionnaire flag: an active relationship is what allows them.
@immutable
class KoiCapabilities {
  const KoiCapabilities({
    required this.role,
    this.expertDiscovery = false,
    this.questionnaires = false,
    this.relationship,
    this.relationships = const [],
    this.authorizationRevision = 0,
  });

  /// Default-deny: no registered privileges at all.
  static const KoiCapabilities none = KoiCapabilities(role: KoiRole.anonymous);

  final KoiRole role;
  final bool expertDiscovery;
  final bool questionnaires;

  /// The first active relationship (the app shows one psychologist).
  final RelationshipSummary? relationship;

  /// Every active relationship, in server order (messages / appointments
  /// are per relationship). Empty for fixtures that only set
  /// [relationship].
  final List<RelationshipSummary> relationships;
  final int authorizationRevision;

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

  /// Active relationships (falls back to [relationship]).
  List<RelationshipSummary> get activeRelationships => !isPatient
      ? const []
      : relationships.isNotEmpty
      ? relationships
      : [relationship!];

  /// Parses the response for [uid]; a response for another uid, or of an
  /// unknown contract major/minor, is rejected (default-deny).
  factory KoiCapabilities.fromJson(Object? body, {required String uid}) {
    final j = asJsonMap(body, 'capabilities');
    if (j['uid'] != uid) throw const FormatException('uid mismatch');
    final version = j['contract_version'];
    if (version is! String || !version.startsWith('0.5.')) {
      throw const FormatException('unknown contract_version');
    }
    if (j['account_state'] != 'registered') return none;
    final flags = j['capabilities'] is Map
        ? (j['capabilities']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final rev = j['authorization_revision'];
    final rels = [
      if (j['active_patient_relationships'] case final List list)
        for (final r in list) ?RelationshipSummary.fromContract(r),
    ];
    final revision = rev is int ? rev : 0;
    if (flags['professional_workspace'] == true) {
      return KoiCapabilities(
        role: KoiRole.psychologist,
        authorizationRevision: revision,
      );
    }
    final discovery = flags['expert_directory'] == true;
    if (rels.isNotEmpty) {
      return KoiCapabilities(
        role: KoiRole.patient,
        expertDiscovery: discovery,
        questionnaires: true,
        relationship: rels.first,
        relationships: rels,
        authorizationRevision: revision,
      );
    }
    return KoiCapabilities(
      role: KoiRole.general,
      expertDiscovery: discovery,
      authorizationRevision: revision,
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
    organizationId: 'demo-org-1',
    psychologistUid: 'demo-expert-1',
  );

  /// The patient relationship the mock returns. The demo care backend
  /// (lib/care/mock_care_backend.dart) replaces it when a demo application
  /// is accepted.
  RelationshipSummary relationship = demoRelationship;

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
      KoiRole.patient => KoiCapabilities(
        role: KoiRole.patient,
        expertDiscovery: true,
        questionnaires: true,
        relationship: relationship,
        relationships: [relationship],
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
