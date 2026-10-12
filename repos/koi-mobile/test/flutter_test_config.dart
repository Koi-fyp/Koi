import 'dart:async';

import 'package:koi_mobile/theme/koi_text.dart';

/// Runs before every test file. google_fonts cannot fetch fonts inside
/// `flutter test`, so text styles use the plain family names instead.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  KoiText.useGoogleFonts = false;
  await testMain();
}
