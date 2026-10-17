import 'package:flutter/foundation.dart';

import 'avatar_state.dart';

/// `--dart-define=KOI_AVATAR_URL=...`: empty = placeholder image, `mock` =
/// the bundled debug mock page, otherwise the HTTPS avatar host page
/// (feat/avatar-webview-host: `/avatar-host`).
const String koiAvatarUrl = String.fromEnvironment('KOI_AVATAR_URL');

enum AvatarSourceKind { placeholder, mock, remote }

/// Where the avatar comes from, and which pages the WebView may show.
@immutable
class AvatarSource {
  const AvatarSource._(this.kind, [this.url]);

  static const AvatarSource placeholder = AvatarSource._(
    AvatarSourceKind.placeholder,
  );
  static const AvatarSource mock = AvatarSource._(AvatarSourceKind.mock);

  /// The avatar host page at [url] (HTTPS only).
  factory AvatarSource.remote(Uri url) {
    if (!isAllowedRemote(url)) {
      throw ArgumentError.value(url, 'url', 'must be an https URL');
    }
    return AvatarSource._(AvatarSourceKind.remote, url.removeFragment());
  }

  /// Reads a KOI_AVATAR_URL value. `mock` only works in debug builds; an
  /// unusable value falls back to the placeholder.
  static AvatarSource parse(String raw, {bool debug = kDebugMode}) {
    final value = raw.trim();
    if (value.isEmpty) return placeholder;
    if (value == 'mock') return debug ? mock : placeholder;
    final uri = Uri.tryParse(value);
    if (uri != null && isAllowedRemote(uri)) return AvatarSource.remote(uri);
    debugPrint('KOI: KOI_AVATAR_URL is not an https URL; using placeholder');
    return placeholder;
  }

  static bool isAllowedRemote(Uri uri) =>
      uri.scheme == 'https' && uri.host.isNotEmpty;

  /// The mock page, a Flutter asset (debug only; see assets/avatar_mock/).
  static const String mockAsset = 'assets/avatar_mock/mock_avatar.html';

  final AvatarSourceKind kind;

  /// The avatar host page (remote only), without a fragment.
  final Uri? url;

  bool get usesWebView => kind != AvatarSourceKind.placeholder;

  /// The page to load for [avatar]: the host URL with `?model=male|female`
  /// (the only way the host picks a model, app/avatar-host/page.tsx), any
  /// other query parameters kept.
  Uri pageUrl(AvatarType avatar) {
    final base = url;
    if (base == null) throw StateError('$kind has no URL');
    return base.replace(
      queryParameters: {...base.queryParameters, 'model': avatar.model},
    );
  }

  /// Navigation policy: only pages of the avatar's own origin (remote:
  /// same scheme, host and port; mock: the mock asset file itself).
  bool allowsNavigation(String target) {
    final uri = Uri.tryParse(target);
    if (uri == null) return false;
    switch (kind) {
      case AvatarSourceKind.placeholder:
        return false;
      case AvatarSourceKind.mock:
        return uri.scheme == 'file' && uri.path.endsWith('/$mockAsset');
      case AvatarSourceKind.remote:
        final base = url!;
        return uri.scheme == base.scheme &&
            uri.host.toLowerCase() == base.host.toLowerCase() &&
            uri.port == base.port &&
            uri.userInfo.isEmpty;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AvatarSource && other.kind == kind && other.url == url;

  @override
  int get hashCode => Object.hash(kind, url);

  @override
  String toString() =>
      'AvatarSource(${kind.name}${url == null ? '' : ' $url'})';
}
