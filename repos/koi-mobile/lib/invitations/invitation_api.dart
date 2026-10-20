import 'package:flutter/foundation.dart';

import '../applications/application_api.dart' show careConsentVersion;
import '../care/care_api_support.dart';
import '../platform/platform_client.dart';

// Patient invitations (MOB-4). REAL, contract v0.5.2
// (origin/handoff/koi-web-1-to-5-2026-10-20, read with git show only):
// `POST /api/v1/patient-invitations/{token}/redeem`
// (route → lifecycle-http.ts:28 → lifecycle.ts:106-127).
//
// THE TOKEN IS A SECRET. It is never logged, printed, put in an exception
// message, saved on the device or kept after the call: it lives only in
// the text field and in the one request.

/// The server's token format (lifecycle.ts:107). Checked on the phone first
/// so a typo never reaches the network.
final RegExp invitationTokenPattern = RegExp(r'^[A-Za-z0-9_-]{43,128}$');

/// The token in what the user pasted: the code itself, or the web's
/// single-use link `…/patient#invite=TOKEN` (PatientWorkspace.tsx:35,
/// PatientManagement.tsx:46). Spaces and line breaks from copying are
/// dropped. Null when it is neither.
String? parseInvitationToken(String input) {
  var v = input.replaceAll(RegExp(r'\s'), '');
  final hash = v.indexOf('#');
  if (hash >= 0) {
    String? token;
    for (final part in v.substring(hash + 1).split('&')) {
      if (part.startsWith('invite=')) token = part.substring(7);
    }
    if (token == null) return null;
    v = token;
  }
  return invitationTokenPattern.hasMatch(v) ? v : null;
}

/// `RelationshipAckDTO`: exactly `{relationship_id, organization_id,
/// state: "active"}`. Nothing else is read.
@immutable
class InvitationAck {
  const InvitationAck({
    required this.relationshipId,
    required this.organizationId,
  });

  final String relationshipId;
  final String organizationId;

  factory InvitationAck.fromJson(Object? v) {
    final j = asJsonMap(v, 'relationship ack');
    if (j['state'] != 'active') throw const FormatException('Bad state');
    return InvitationAck(
      relationshipId: reqString(j, 'relationship_id'),
      organizationId: reqString(j, 'organization_id'),
    );
  }
}

abstract interface class InvitationApi {
  bool get isMock;

  /// Needs a registered General account (lifecycle.ts:113) and a sign-in
  /// within 5 minutes (service.ts:23). One user action = one
  /// [idempotencyKey], reused on retry.
  Future<InvitationAck> redeem(String token, {required String idempotencyKey});
}

class HttpInvitationApi implements InvitationApi {
  HttpInvitationApi(this.client);
  final PlatformClient client;

  @override
  bool get isMock => false;

  @override
  Future<InvitationAck> redeem(
    String token, {
    required String idempotencyKey,
  }) async => InvitationAck.fromJson(
    await client.sendJson(
      'POST',
      '/api/v1/patient-invitations/${Uri.encodeComponent(token)}/redeem',
      {'consent_version': careConsentVersion},
      idempotencyKey: idempotencyKey,
    ),
  );
}

class UnavailableInvitationApi implements InvitationApi {
  const UnavailableInvitationApi();

  @override
  bool get isMock => false;
  @override
  Future<InvitationAck> redeem(
    String token, {
    required String idempotencyKey,
  }) => careNotConfigured();
}

/// What the redeem screen says about a failure. The server answers 409 for
/// an expired, revoked AND an already used invitation alike
/// (lifecycle.ts:120), so they share one message.
enum InvitationFailure {
  /// 422: not a valid code (also checked on the phone).
  format,

  /// 404: unknown, or meant for another account.
  notFound,

  /// 409: expired, cancelled or already used.
  used,

  /// 403: no General access, or the practice is not active.
  denied,
  reauth,
  rateLimited,
  offline,
  notAvailable,
  other,
}

InvitationFailure invitationFailureOf(Object e) {
  if (e is PlatformException && e.code == PlatformErrorCode.invalid) {
    return InvitationFailure.format;
  }
  return switch (careFailureOf(e)) {
    CareFailure.gone => InvitationFailure.notFound,
    CareFailure.conflict => InvitationFailure.used,
    CareFailure.denied => InvitationFailure.denied,
    CareFailure.reauth => InvitationFailure.reauth,
    CareFailure.rateLimited => InvitationFailure.rateLimited,
    CareFailure.offline => InvitationFailure.offline,
    CareFailure.notAvailable => InvitationFailure.notAvailable,
    CareFailure.other => InvitationFailure.other,
  };
}
