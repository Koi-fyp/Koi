import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:koi_mobile/theme/koi_text.dart';

/// Loads the bundled DM Sans / Bricolage Grotesque into the test engine for
/// the whole file, so layout uses real glyph widths instead of the square
/// test font (which makes every label far too wide for a 360dp phone).
void useRealFonts() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    KoiText.useGoogleFonts = true;
    await GoogleFonts.pendingFonts([
      for (final w in [FontWeight.w600, FontWeight.w700, FontWeight.w800])
        KoiText.display(fontWeight: w),
      for (final w in [
        FontWeight.w400,
        FontWeight.w500,
        FontWeight.w600,
        FontWeight.w700,
      ])
        KoiText.body(fontWeight: w),
    ]);
  });
  // Restore the flutter_test_config.dart default.
  tearDownAll(() => KoiText.useGoogleFonts = false);
}
