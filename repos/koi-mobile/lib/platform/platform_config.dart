import 'package:flutter/foundation.dart';

import '../chat/chat_api.dart' show parseApiBase;

// KOI 2.0 platform settings (BATCH MOB-1). There is NO web contract file in
// the repo yet (KOI_WEB_TRACK_FINAL_REVIEWED.md is missing and no branch has
// these endpoints, checked 2026-10-19), so every platform endpoint in
// lib/account, lib/experts and lib/questionnaires is PROVISIONAL; the list
// lives in KOI_MOB1_PROVISIONAL_CONTRACTS.md (repo root, not committed).

/// Base URL of the KOI 2.0 platform API (`/api/v1/me/capabilities`,
/// `/api/v1/experts`, `/api/v1/patient/...`), from
/// `--dart-define=KOI_PLATFORM_BASE=...`. No default: empty = the account
/// features stay closed (default-deny) unless [koiMocksEnabled].
const String koiPlatformBase = String.fromEnvironment('KOI_PLATFORM_BASE');

/// `--dart-define=KOI_MOCKS=true`: the platform adapters use in-memory demo
/// data and every screen that shows it carries a "Demo data" badge. Never a
/// finished integration.
const bool koiMocksEnabled = bool.fromEnvironment('KOI_MOCKS');

/// The mock role picker exists only in debug builds AND with KOI_MOCKS
/// (decided 2026-10-19).
const bool koiMockRolePicker = kDebugMode && koiMocksEnabled;

/// The professional web portal, from `--dart-define=KOI_PRO_PORTAL_URL=...`.
/// The psychologist landing hides its link when this is empty or invalid.
const String koiProPortalUrl = String.fromEnvironment('KOI_PRO_PORTAL_URL');

/// [koiProPortalUrl] as an https URL, or null.
Uri? proPortalUri([String raw = koiProPortalUrl]) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri;
}

/// [koiPlatformBase] parsed like the chat base (http/https, no query).
Uri? platformBaseUri([String raw = koiPlatformBase]) => parseApiBase(raw);
