import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/app/app_version.dart';

void main() {
  test('koiAppVersion is the pubspec.yaml version (no build number)', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final version = line.substring('version:'.length).trim().split('+').first;
    expect(koiAppVersion, version);
  });
}
