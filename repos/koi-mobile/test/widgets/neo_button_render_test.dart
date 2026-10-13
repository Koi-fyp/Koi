import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/theme/koi_colors.dart';
import 'package:koi_mobile/widgets/neo_button.dart';

/// Renders NeoButtons to real pixels and samples them. Guards against the
/// ghost bug found on device (2026-10-13): Flutter painted the hard shadow
/// under the transparent fill, so the button became a solid black box with
/// black (invisible) text. Web's `.neo-btn-ghost` shows the page through
/// its fill and the shadow only outside it.
void main() {
  const page = KoiColors.background; // #ffe5d9

  Future<(ui.Image, Rect)> render(
    WidgetTester tester,
    NeoButtonVariant variant, {
    bool pressed = false,
  }) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: page,
            child: Center(
              child: NeoButton(
                key: const Key('b'),
                variant: variant,
                onPressed: () {},
                child: const Text('Cancel'),
              ),
            ),
          ),
        ),
      ),
    );
    if (pressed) {
      await tester.startGesture(tester.getCenter(find.byKey(const Key('b'))));
      await tester.pump(const Duration(milliseconds: 200));
    }
    final rect = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('b')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final ro =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = (await tester.runAsync(() => ro.toImage()))!;
    return (image, rect);
  }

  Future<Color> pixel(WidgetTester tester, ui.Image image, Offset at) async {
    final data = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    final i = (at.dy.round() * image.width + at.dx.round()) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }

  /// Inside the button, past the 2.5px border but before the 28px padding
  /// where the label starts, so only the fill is sampled.
  Offset fillPoint(Rect r) => Offset(r.left + 14, r.center.dy);

  testWidgets('ghost: page shows through the fill; shadow only outside', (
    tester,
  ) async {
    final (image, r) = await render(tester, NeoButtonVariant.ghost);
    expect(await pixel(tester, image, fillPoint(r)), page);
    // 3px shadow: just below the bottom edge and right of the right edge.
    expect(
      await pixel(tester, image, Offset(r.center.dx, r.bottom + 1.5)),
      KoiColors.neoBlack,
    );
    expect(
      await pixel(tester, image, Offset(r.right + 1.5, r.center.dy)),
      KoiColors.neoBlack,
    );
    // Nothing above / left (shadow is offset +x, +y only).
    expect(await pixel(tester, image, Offset(r.center.dx, r.top - 1.5)), page);
    image.dispose();
  });

  testWidgets('ghost pressed (:active 1px shadow): fill still see-through', (
    tester,
  ) async {
    final (image, r) = await render(
      tester,
      NeoButtonVariant.ghost,
      pressed: true,
    );
    expect(await pixel(tester, image, fillPoint(r)), page);
    expect(
      await pixel(tester, image, Offset(r.center.dx, r.bottom + 0.5)),
      KoiColors.neoBlack,
    );
    image.dispose();
  });

  testWidgets('opaque variants keep their fill colour', (tester) async {
    for (final (v, c) in [
      (NeoButtonVariant.primary, KoiColors.neoBlue),
      (NeoButtonVariant.secondary, KoiColors.neoYellow),
      (NeoButtonVariant.danger, KoiColors.danger),
    ]) {
      final (image, r) = await render(tester, v);
      expect(await pixel(tester, image, fillPoint(r)), c, reason: '$v');
      expect(
        await pixel(tester, image, Offset(r.center.dx, r.bottom + 2)),
        KoiColors.neoBlack,
        reason: '$v shadow',
      );
      image.dispose();
    }
  });
}
