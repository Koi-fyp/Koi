import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:koi_mobile/theme/koi_text.dart';

/// Proves every weight the web loads (globals.css @import) is bundled and
/// loads through google_fonts with runtime fetching disabled, i.e. offline.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KoiText.useGoogleFonts = true;
  });
  tearDown(() {
    KoiText.useGoogleFonts = false; // restore flutter_test_config default
  });

  test('ATC-M0-12 all bundled weights load offline via google_fonts', () async {
    final styles = <TextStyle>[
      for (final w in [200, 300, 400, 500, 600, 700, 800])
        KoiText.display(fontWeight: FontWeight.values[w ~/ 100 - 1]),
      for (final w in [300, 400, 500, 600, 700])
        KoiText.body(fontWeight: FontWeight.values[w ~/ 100 - 1]),
      GoogleFonts.dmSans(fontWeight: FontWeight.w300, fontStyle: FontStyle.italic),
      GoogleFonts.dmSans(fontWeight: FontWeight.w400, fontStyle: FontStyle.italic),
      // MOB-3: Urdu questionnaire wording.
      KoiText.urduQuestionnaire(),
    ];
    await GoogleFonts.pendingFonts(styles);
  });

  test('ATC-M0-12 weights outside the bundled range are clamped and still load', () async {
    // Web uses font-weight 800/900 on DM Sans text (e.g. settings and
    // progress headings); without clamping google_fonts would look for
    // DMSans-ExtraBold/Black, which are not bundled, and fail.
    final heavyBody = KoiText.body(fontWeight: FontWeight.w900);
    final heavyBody800 = KoiText.body(fontWeight: FontWeight.w800);
    final lightBody = KoiText.body(fontWeight: FontWeight.w100);
    final heavyDisplay = KoiText.display(fontWeight: FontWeight.w900);
    final lightDisplay = KoiText.display(fontWeight: FontWeight.w100);
    expect(heavyBody.fontWeight, FontWeight.w700);
    expect(heavyBody800.fontWeight, FontWeight.w700);
    expect(lightBody.fontWeight, FontWeight.w300);
    expect(heavyDisplay.fontWeight, FontWeight.w800);
    expect(lightDisplay.fontWeight, FontWeight.w200);
    expect(KoiText.body().fontWeight, isNull); // unset stays unset
    // Throws if any of them points at a font file that isn't bundled.
    await GoogleFonts.pendingFonts(
        [heavyBody, heavyBody800, lightBody, heavyDisplay, lightDisplay]);
  });

  // Reads assets/google_fonts/ on disk (flutter test's own asset copy in
  // build/ can be stale). Hashes are the expectedFileHash values in
  // google_fonts 6.3.3 lib/src/google_fonts_parts/part_b.g.dart (Bricolage)
  // and part_d.g.dart (DM Sans); MOB-3 Noto Nastaliq Urdu Regular from
  // part_n.g.dart (notoNastaliqUrdu, w400).
  test('ATC-M0-12 bundled .ttf files are the exact google_fonts files', () async {
    const expected = {
      'BricolageGrotesque-ExtraLight.ttf': '749a547b99e0f8b0c40c705460dfec9883f970a58c8b30c6f0e4c748068d5e5d',
      'BricolageGrotesque-Light.ttf': '3f40769977ea17b4ae2ad9953ecaea85a40dddcb62b3643b2e6b3f26a3c110c7',
      'BricolageGrotesque-Regular.ttf': '2d910251022c851e26d045b9202776cf98dd15af8e539ebbda16503332a2b016',
      'BricolageGrotesque-Medium.ttf': '2a573cccd8a40c7163eb815be9f0ea609b0d2a613c5d3474c077b01253fde8d5',
      'BricolageGrotesque-SemiBold.ttf': '6c6cd547cb081dee4b2a4462c3e5d72091ca69386392b3ac3a73463f244f019e',
      'BricolageGrotesque-Bold.ttf': '6ed0995ec51fc124e42efc90831a6afe3825e317f7969a599ac7d654bc2d6821',
      'BricolageGrotesque-ExtraBold.ttf': 'c56674eff2988656134508882d20ee5f74974787bcda3ba0eff27eed54576957',
      'DMSans-Light.ttf': '085c8cb749d718ed2e3a0b4d66434f56452ce665bce80a72cf0bfa54d3b1b483',
      'DMSans-Regular.ttf': '2dbeb0e218984395ccb1b649dbe39bfecf9da420bf69fdc2da2860c2c9dc3324',
      'DMSans-Medium.ttf': 'cd8be6a6d9a5579d829e3f4902d7d9acdaa01230bac60a024764c13afc6a049c',
      'DMSans-SemiBold.ttf': 'b0a9fe8b3a029cfaf00e31437c32a57e8adead3cade26ad1c6637a4908f4278e',
      'DMSans-Bold.ttf': '9909c4fcfbfe7b2c4a658b8d74eeb3ed38401a31cd4a3854546369c174f41440',
      'DMSans-LightItalic.ttf': 'd8723f525f666d25b045dbc192d20d1c10743a75761ed84dc5ec5da1bea72bc6',
      'DMSans-Italic.ttf': '7693a13cb485db129b413d4bd1b2a18f408dd966fa88d406598d951fa11f8aed',
      'NotoNastaliqUrdu-Regular.ttf': 'd2aacf1112ffb91ed5fd97d9326dfbb3358dbeede2fb1d720b6b740e378c1a72',
    };
    final onDisk = Directory('assets/google_fonts')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((n) => n.endsWith('.ttf'))
        .toSet();
    expect(onDisk, expected.keys.toSet());
    for (final MapEntry(key: name, value: hash) in expected.entries) {
      final bytes = File('assets/google_fonts/$name').readAsBytesSync();
      final digest = await Sha256().hash(bytes);
      final hex = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(hex, hash, reason: name);
    }
  });

  test('ATC-M0-12 OFL license files are bundled', () async {
    for (final file in [
      'OFL-BricolageGrotesque.txt',
      'OFL-DMSans.txt',
      'OFL-NotoNastaliqUrdu.txt',
    ]) {
      final text = await rootBundle.loadString('assets/google_fonts/$file');
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
    }
  });
}
