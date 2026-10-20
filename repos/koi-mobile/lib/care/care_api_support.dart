import 'dart:math';

import 'package:flutter/foundation.dart';

import '../platform/platform_client.dart';
import 'care_strings.dart';

// Shared by the MOB-2 adapters (experts, applications, professional
// messages, appointments, notifications). Wire shapes: contract v0.5.2
// (origin/handoff/koi-web-1-to-5-2026-10-20
// repos/koi-backend/nextjs_app/contracts/v0.5.2/contracts.schema.json;
// these definitions are unchanged since v0.5.1), read with git show only.
// Every list is `{items: [...], next_cursor}` with `limit` (default 25,
// max 100) and an opaque, signed `cursor` that expires after 15 minutes.

/// One page of a contract list.
@immutable
class ApiPage<T> {
  const ApiPage(this.items, this.nextCursor);
  final List<T> items;

  /// Opaque, signed by the server; null = no more pages.
  final String? nextCursor;
}

/// Parses `{items, next_cursor}`. An item that does not parse (unknown
/// kind / state, missing field) is SKIPPED, never shown half-read.
ApiPage<T> parseApiPage<T>(Object? body, T? Function(Object? item) parse) {
  final j = asJsonMap(body, 'page');
  final items = <T>[];
  for (final raw in asJsonList(j['items'], 'items')) {
    try {
      final v = parse(raw);
      if (v != null) items.add(v);
    } on FormatException {
      // Ignored safely (contract: unknown types must not break the list).
    }
  }
  final next = j['next_cursor'];
  return ApiPage(items, next is String && next.isNotEmpty ? next : null);
}

/// MOB-4: the contract's largest page (`limit` 1-100, community.ts:184),
/// used by the lists that read every page (messages, appointments).
const int carePageLimitAll = 100;

/// At most this many pages of [carePageLimitAll]: 1,000 items, then the
/// screen says only part could be loaded (decision 2026-10-21).
const int careMaxPages = 10;

Map<String, String> pageQuery({String? cursor, int limit = 25}) => {
  'limit': '$limit',
  'cursor': ?cursor,
};

/// The contract timestamp (RFC 3339, UTC). A bad value is a format error.
DateTime reqTime(Map<String, Object?> j, String key) {
  final v = DateTime.tryParse(reqString(j, key));
  if (v == null) throw FormatException('Bad $key');
  return v.toUtc();
}

DateTime? optTime(Map<String, Object?> j, String key) {
  final v = j[key];
  return v is String ? DateTime.tryParse(v)?.toUtc() : null;
}

/// A new `Idempotency-Key` (random uuid v4, the same format as the chat's
/// uuidV4, kept here so no Care code depends on lib/chat) for ONE user
/// action. Retrying that same action reuses it.
String newIdempotencyKey([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// What a Care screen does with a failed call.
enum CareFailure {
  /// The endpoint does not exist on this server (404/405 without a contract
  /// ErrorDTO body), or KOI_PLATFORM_BASE is not set and mocks are off:
  /// a calm "Not available yet", never fake data.
  notAvailable,
  offline,

  /// 403: capabilities are re-checked by the platform client.
  denied,

  /// A contract 404 `not_found` for one resource.
  gone,

  /// Recent sign-in needed (mutation 401). Never a revocation.
  reauth,
  rateLimited,
  conflict,
  other,
}

CareFailure careFailureOf(Object e) {
  if (e is! PlatformException) return CareFailure.other;
  return switch (e.code) {
    PlatformErrorCode.notConfigured => CareFailure.notAvailable,
    PlatformErrorCode.notFound when e.contractCode == null =>
      CareFailure.notAvailable,
    PlatformErrorCode.server when e.status == 405 && e.contractCode == null =>
      CareFailure.notAvailable,
    PlatformErrorCode.notFound => CareFailure.gone,
    PlatformErrorCode.network ||
    PlatformErrorCode.timeout => CareFailure.offline,
    PlatformErrorCode.forbidden => CareFailure.denied,
    PlatformErrorCode.reauthRequired => CareFailure.reauth,
    PlatformErrorCode.rateLimited => CareFailure.rateLimited,
    PlatformErrorCode.conflict ||
    PlatformErrorCode.revisionConflict => CareFailure.conflict,
    _ => CareFailure.other,
  };
}

String careFailureText(CareStrings s, Object e) => switch (careFailureOf(e)) {
  CareFailure.notAvailable => s.t(CareText.notAvailableYet),
  CareFailure.offline => s.t(CareText.offline),
  CareFailure.denied || CareFailure.gone => s.t(CareText.noLongerAvailable),
  CareFailure.rateLimited => s.t(CareText.rateLimited),
  _ => s.t(CareText.genericError),
};

/// Used when KOI_PLATFORM_BASE is empty and mocks are off.
Future<T> careNotConfigured<T>() =>
    Future.error(const PlatformException(PlatformErrorCode.notConfigured));
