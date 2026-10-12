import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/theme/koi_motion.dart';

double _dy(WidgetTester tester) => tester
    .widget<Transform>(find.descendant(
        of: find.byType(KoiFloatY), matching: find.byType(Transform)))
    .transform
    .getTranslation()
    .y;

void main() {
  testWidgets('float-mid waits its 0.7s delay, then reaches -12px at 50%',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: KoiFloatY(spec: KoiMotion.floatMid, child: SizedBox()),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_dy(tester), 0); // still in the delay

    await tester.pump(const Duration(milliseconds: 100)); // delay ends
    await tester.pump(const Duration(seconds: 2)); // 50% of 4s
    expect(_dy(tester), closeTo(-12, 0.01));
  });

  testWidgets('disposing during the delay leaves no pending timer',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: KoiFloatY(spec: KoiMotion.floatFast, child: SizedBox()),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    // The test framework fails the test if a timer is still pending here.
  });

  testWidgets('fade-up starts at the `from` state (opacity 0, +20px)',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: KoiFadeUp(child: SizedBox()),
    ));
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });
}
