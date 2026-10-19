import 'package:flutter/foundation.dart';

import '../platform/platform_client.dart';

/// A discoverable psychologist, as the AUTHORIZED directory API returns it
/// (KOI_MOBILE_TRACK_FINAL_REVIEWED.md §7 fields only). PROVISIONAL shape.
@immutable
class ExpertProfile {
  const ExpertProfile({
    required this.id,
    required this.displayName,
    required this.description,
    required this.languages,
    required this.modality,
    required this.acceptingNewPatients,
  });

  final String id;
  final String displayName;

  /// The approved professional description.
  final String description;
  final List<String> languages;

  /// General session modality, e.g. "Online" (server wording).
  final String modality;
  final bool acceptingNewPatients;

  factory ExpertProfile.fromJson(Object? v) {
    final j = asJsonMap(v, 'expert');
    final langs = j['languages'];
    final modality = j['session_modality'];
    final description = j['description'];
    return ExpertProfile(
      id: reqString(j, 'id'),
      displayName: reqString(j, 'display_name'),
      description: description is String ? description : '',
      languages: [
        if (langs is List)
          for (final l in langs)
            if (l is String) l,
      ],
      modality: modality is String ? modality : '',
      acceptingNewPatients: j['accepting_new_patients'] == true,
    );
  }
}

/// Read-only expert discovery for General / Patient users. Applications
/// come in a later batch. Never a client-side unrestricted Firestore read.
abstract interface class ExpertDirectoryApi {
  bool get isMock;
  Future<List<ExpertProfile>> list();
  Future<ExpertProfile> detail(String id);
}

class HttpExpertDirectoryApi implements ExpertDirectoryApi {
  HttpExpertDirectoryApi(this.client);
  final PlatformClient client;

  @override
  bool get isMock => false;

  @override
  Future<List<ExpertProfile>> list() async {
    final j = asJsonMap(await client.getJson('/api/v1/experts'));
    return [
      for (final e in asJsonList(j['experts'], 'experts'))
        ExpertProfile.fromJson(e),
    ];
  }

  @override
  Future<ExpertProfile> detail(String id) async => ExpertProfile.fromJson(
    await client.getJson('/api/v1/experts/${Uri.encodeComponent(id)}'),
  );
}

class UnavailableExpertDirectoryApi implements ExpertDirectoryApi {
  const UnavailableExpertDirectoryApi();

  @override
  bool get isMock => false;
  @override
  Future<List<ExpertProfile>> list() =>
      Future.error(const PlatformException(PlatformErrorCode.notConfigured));
  @override
  Future<ExpertProfile> detail(String id) =>
      Future.error(const PlatformException(PlatformErrorCode.notConfigured));
}

/// KOI_MOCKS=true only: fictional placeholder profiles.
class MockExpertDirectoryApi implements ExpertDirectoryApi {
  MockExpertDirectoryApi({this.latency = const Duration(milliseconds: 500)});

  final Duration latency;

  static const List<ExpertProfile> profiles = [
    ExpertProfile(
      id: 'demo-expert-1',
      displayName: 'Demo Psychologist A',
      description: 'Placeholder profile text for development.',
      languages: ['English', 'Urdu'],
      modality: 'Online',
      acceptingNewPatients: true,
    ),
    ExpertProfile(
      id: 'demo-expert-2',
      displayName: 'Demo Psychologist B',
      description: 'Placeholder profile text for development.',
      languages: ['Urdu'],
      modality: 'Online',
      acceptingNewPatients: false,
    ),
  ];

  @override
  bool get isMock => true;

  @override
  Future<List<ExpertProfile>> list() async {
    await Future<void>.delayed(latency);
    return profiles;
  }

  @override
  Future<ExpertProfile> detail(String id) async {
    await Future<void>.delayed(latency);
    return profiles.firstWhere(
      (p) => p.id == id,
      orElse: () => throw const PlatformException(PlatformErrorCode.notFound),
    );
  }
}
