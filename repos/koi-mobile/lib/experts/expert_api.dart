import 'package:flutter/foundation.dart';

import '../care/care_api_support.dart';
import '../platform/platform_client.dart';

/// A discoverable psychologist: contract v0.5.2 `ExpertDTO`, exactly
/// `{id, display_name, bio, accepting_new_patients}`. `id` is the
/// psychologist's uid (what an application targets). Any other field the
/// server sends is ignored; there are no specialties, languages,
/// qualifications or availability in the contract (decision C).
@immutable
class ExpertProfile {
  const ExpertProfile({
    required this.id,
    required this.displayName,
    required this.bio,
    required this.acceptingNewPatients,
  });

  final String id;
  final String displayName;

  /// The approved professional description.
  final String bio;
  final bool acceptingNewPatients;

  factory ExpertProfile.fromJson(Object? v) {
    final j = asJsonMap(v, 'expert');
    final bio = j['bio'];
    return ExpertProfile(
      id: reqString(j, 'id'),
      displayName: reqString(j, 'display_name'),
      bio: bio is String ? bio : '',
      acceptingNewPatients: j['accepting_new_patients'] == true,
    );
  }
}

/// Expert discovery for General / Patient users. Never a client-side
/// unrestricted Firestore read.
abstract interface class ExpertDirectoryApi {
  bool get isMock;
  Future<ApiPage<ExpertProfile>> list({String? cursor});
  Future<ExpertProfile> detail(String id);
}

// REAL, contract v0.5.2 (origin/handoff/koi-web-1-to-5-2026-10-20, read
// with git show only; openapi x-status is stale): GET /api/v1/experts and
// /api/v1/experts/{uid} → community-http.ts:29-30 → community.ts:79-94.
// Needs General access (403 otherwise). Hidden profiles are dropped from a
// page, so a page may be empty with a next cursor (CareList skips it).
class HttpExpertDirectoryApi implements ExpertDirectoryApi {
  HttpExpertDirectoryApi(this.client);
  final PlatformClient client;

  static const String path = '/api/v1/experts';

  @override
  bool get isMock => false;

  @override
  Future<ApiPage<ExpertProfile>> list({String? cursor}) async => parseApiPage(
    await client.getJson(path, query: pageQuery(cursor: cursor)),
    ExpertProfile.fromJson,
  );

  @override
  Future<ExpertProfile> detail(String id) async => ExpertProfile.fromJson(
    await client.getJson('$path/${Uri.encodeComponent(id)}'),
  );
}

class UnavailableExpertDirectoryApi implements ExpertDirectoryApi {
  const UnavailableExpertDirectoryApi();

  @override
  bool get isMock => false;
  @override
  Future<ApiPage<ExpertProfile>> list({String? cursor}) => careNotConfigured();
  @override
  Future<ExpertProfile> detail(String id) => careNotConfigured();
}

/// KOI_MOCKS=true only: fictional placeholder profiles, 2 per page so the
/// lazy loading can be seen.
class MockExpertDirectoryApi implements ExpertDirectoryApi {
  MockExpertDirectoryApi({
    this.latency = const Duration(milliseconds: 500),
    this.pageSize = 2,
  });

  final Duration latency;
  final int pageSize;

  static const List<ExpertProfile> profiles = [
    ExpertProfile(
      id: 'demo-expert-1',
      displayName: 'Demo Psychologist A',
      bio: 'Placeholder profile text for development.',
      acceptingNewPatients: true,
    ),
    ExpertProfile(
      id: 'demo-expert-2',
      displayName: 'Demo Psychologist B',
      bio: 'Placeholder profile text for development.',
      acceptingNewPatients: false,
    ),
    ExpertProfile(
      id: 'demo-expert-3',
      displayName: 'Demo Psychologist C',
      bio: 'Placeholder profile text for development.',
      acceptingNewPatients: true,
    ),
  ];

  @override
  bool get isMock => true;

  @override
  Future<ApiPage<ExpertProfile>> list({String? cursor}) async {
    await Future<void>.delayed(latency);
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + pageSize).clamp(0, profiles.length);
    return ApiPage(
      profiles.sublist(start, end),
      end < profiles.length ? '$end' : null,
    );
  }

  @override
  Future<ExpertProfile> detail(String id) async {
    await Future<void>.delayed(latency);
    return profiles.firstWhere(
      (p) => p.id == id,
      orElse: () => throw const PlatformException(
        PlatformErrorCode.notFound,
        body: {'code': 'not_found', 'request_id': 'mock'},
      ),
    );
  }
}
