import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/shell/nav_icons.dart';
import 'package:koi_mobile/shell/svg_path.dart';

void main() {
  bool near(Rect a, Rect b) =>
      (a.left - b.left).abs() < 0.01 &&
      (a.top - b.top).abs() < 0.01 &&
      (a.right - b.right).abs() < 0.01 &&
      (a.bottom - b.bottom).abs() < 0.01;

  test('relative lines, H/V and close', () {
    final p = parseSvgPath('M2 3h4v5l-6 0z');
    expect(near(p.getBounds(), const Rect.fromLTRB(0, 3, 6, 8)), isTrue);
  });

  test('compact numbers like ".5.5" and "1-4" tokenize correctly', () {
    final p = parseSvgPath('M0 0l.5.5L1-4');
    expect(near(p.getBounds(), const Rect.fromLTRB(0, -4, 1, 0.5)), isTrue);
  });

  test('arc: half circle radius 2 bulges by 2', () {
    // From (0,0) to (4,0) with sweep=1 (clockwise, y-down) bulges upward.
    final p = parseSvgPath('M0 0A2 2 0 0 1 4 0');
    expect(near(p.getBounds(), const Rect.fromLTRB(0, -2, 4, 0)), isTrue);
  });

  test('web icons have the expected extents in the 24x24 viewBox', () {
    // ChatIcon: x 3..21, y 3..21 (bubble with its tail at (3,21)).
    expect(
      near(chatIconPath.getBounds(), const Rect.fromLTRB(3, 3, 21, 21)),
      isTrue,
    );
    // ProgressIcon polyline: x 2..22, y 3..21.
    expect(
      near(progressIconPath.getBounds(), const Rect.fromLTRB(2, 3, 22, 21)),
      isTrue,
    );
    // SettingsIcon gear: the "a2 2 0 0 1 0-4" end caps reach x/y 1 and 23.
    expect(
      near(settingsIconPath.getBounds(), const Rect.fromLTRB(1, 1, 23, 23)),
      isTrue,
    );
    // Chevron 6 9 12 15 18 9.
    expect(
      near(chevronDownPath.getBounds(), const Rect.fromLTRB(6, 9, 18, 15)),
      isTrue,
    );
  });

  test('unsupported commands fail loudly', () {
    expect(() => parseSvgPath('M0 0Q1 1 2 2'), throwsFormatException);
    expect(() => parseSvgPolyline('1 2 3'), throwsFormatException);
  });
}
