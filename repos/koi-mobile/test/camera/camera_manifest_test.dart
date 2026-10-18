import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app manifest's camera entries (Prompt 29 follow-up). Text checks
/// only: the merged manifest needs a Gradle build.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  group('ATC-M20-19 manifest: camera permission, optional camera, no '
      'storage permission', () {
    test('CAMERA is requested; RECORD_AUDIO stays for the mic', () {
      expect(
        manifest,
        contains('<uses-permission android:name="android.permission.CAMERA"/>'),
      );
      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
        ),
      );
    });

    test('the tools namespace is declared', () {
      expect(
        manifest,
        contains('xmlns:tools="http://schemas.android.com/tools"'),
      );
    });

    test('camera.any is not required (replaces the plugin\'s element)', () {
      expect(
        RegExp(
          r'<uses-feature android:name="android\.hardware\.camera\.any"\s+'
          r'android:required="false" tools:node="replace"/>',
        ).hasMatch(manifest),
        isTrue,
      );
    });

    test('WRITE_EXTERNAL_STORAGE from the plugin is removed', () {
      expect(
        RegExp(
          r'<uses-permission\s+android:name="android\.permission\.'
          r'WRITE_EXTERNAL_STORAGE"\s+tools:node="remove"/>',
        ).hasMatch(manifest),
        isTrue,
      );
      expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    });

    test('the plugin still declares what is overridden (flags a plugin '
        'upgrade that changes it)', () {
      final config = File(
        '.dart_tool/package_config.json',
      ).readAsStringSync();
      final root = RegExp(
        r'"rootUri": "file:///([^"]*camera_android_camerax-[^"]*)"',
      ).firstMatch(config)!.group(1)!;
      final plugin = File(
        '${Uri.decodeFull(root)}/android/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(plugin, contains('android.hardware.camera.any'));
      expect(plugin, contains('android.permission.WRITE_EXTERNAL_STORAGE'));
    });
  });
}
