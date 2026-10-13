import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/screens/splash_screen.dart';
import 'package:koi_mobile/theme/koi_colors.dart';

void main() {
  testWidgets('splash matches (authenticated)/layout.tsx', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    final logo = find.byKey(const Key('splash-logo'));
    expect(tester.getSize(logo), const Size(44, 44));
    final box = (tester.widget<Container>(logo).decoration as BoxDecoration);
    expect(box.color, KoiColors.neoBlue);
    expect(box.borderRadius, BorderRadius.circular(10));
    expect((box.border as Border).top.width, 2.5);
    expect((box.border as Border).top.color, KoiColors.neoBlack);
    expect(box.boxShadow!.single.offset, const Offset(4, 4));
    expect(box.boxShadow!.single.blurRadius, 0);

    final k = tester.widget<Text>(find.text('K'));
    expect(k.style!.fontSize, 19.2);
    expect(k.style!.fontWeight, FontWeight.w800);
    expect(k.style!.color, KoiColors.neoWhite);

    // fadeUp 0.4s: invisible at start, fully visible after 400ms.
    double opacity() => tester
        .widget<Opacity>(
          find.ancestor(of: logo, matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(opacity(), 1);
  });
}
