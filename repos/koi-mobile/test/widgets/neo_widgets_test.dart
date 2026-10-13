import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/theme/koi_colors.dart';
import 'package:koi_mobile/widgets/neo_button.dart';
import 'package:koi_mobile/widgets/neo_card.dart';
import 'package:koi_mobile/widgets/neo_input.dart';
import 'package:koi_mobile/widgets/neo_spinner.dart';
import 'package:koi_mobile/widgets/outer_shadow.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

ShapeDecoration _buttonDecoration(WidgetTester tester) => tester
    .widgetList<Container>(find.descendant(
        of: find.byType(NeoButton), matching: find.byType(Container)))
    .firstWhere((c) => c.decoration is ShapeDecoration)
    .decoration! as ShapeDecoration;

/// The shadow offset, wherever NeoButton paints it: on the decoration
/// (opaque variants) or outside-only via the painter (ghost).
Offset _shadowOffset(WidgetTester tester) {
  final shadows = _buttonDecoration(tester).shadows;
  if (shadows != null) return shadows.single.offset;
  return tester
      .widgetList<CustomPaint>(find.descendant(
          of: find.byType(NeoButton), matching: find.byType(CustomPaint)))
      .map((c) => c.painter)
      .whereType<OuterStadiumShadowPainter>()
      .single
      .offset;
}

void main() {
  group('NeoButton', () {
    testWidgets('variant colours and resting shadows match globals.css',
        (tester) async {
      const expected = {
        NeoButtonVariant.primary: (KoiColors.neoBlue, 4.0),
        NeoButtonVariant.secondary: (KoiColors.neoYellow, 4.0),
        NeoButtonVariant.ghost: (Color(0x00000000), 3.0),
        NeoButtonVariant.danger: (KoiColors.danger, 4.0),
      };
      for (final MapEntry(key: variant, value: (color, shadow))
          in expected.entries) {
        await tester.pumpWidget(_wrap(NeoButton(
            variant: variant, onPressed: () {}, child: const Text('x'))));
        // The shadow tweens from the previous variant's value.
        await tester.pumpAndSettle();
        final d = _buttonDecoration(tester);
        expect(d.color, color, reason: '$variant');
        expect(_shadowOffset(tester), Offset(shadow, shadow));
        // Transparent fill: no Flutter BoxShadow under it (it would show
        // through as a solid block; web's CSS shadow never does).
        if (variant == NeoButtonVariant.ghost) expect(d.shadows, isNull);
        final side = (d.shape as StadiumBorder).side;
        expect(side.width, 2.5);
        expect(side.color, KoiColors.neoBlack);
      }
    });

    testWidgets('tap calls onPressed; press shows the :active state',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(NeoButton(
          onPressed: () => taps++, child: const Text('Go'))));

      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Go')));
      await tester.pumpAndSettle();
      expect(_buttonDecoration(tester).shadows!.single.offset,
          const Offset(2, 2));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(_buttonDecoration(tester).shadows!.single.offset,
          const Offset(4, 4));
    });

    testWidgets('disabled: 0.5 opacity and no callback', (tester) async {
      await tester.pumpWidget(
          _wrap(const NeoButton(onPressed: null, child: Text('Off'))));
      final opacity = tester.widget<Opacity>(find
          .ancestor(of: find.text('Off'), matching: find.byType(Opacity))
          .first);
      expect(opacity.opacity, 0.5);
    });

    testWidgets('loading shows spinner + "Loading…" and blocks taps',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(NeoButton(
          loading: true, onPressed: () => taps++, child: const Text('Save'))));
      expect(find.byType(NeoSpinner), findsOneWidget);
      expect(find.text('Loading…'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      await tester.tap(find.byType(NeoButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(taps, 0);
    });

    testWidgets('label uses display font 700 16px', (tester) async {
      await tester.pumpWidget(
          _wrap(NeoButton(onPressed: () {}, child: const Text('Go'))));
      final style = DefaultTextStyle.of(tester.element(find.text('Go'))).style;
      expect(style.fontFamily, 'Bricolage Grotesque');
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontSize, 16);
      expect(style.color, KoiColors.neoWhite);
    });
  });

  group('NeoCard', () {
    testWidgets('variants match .neo-card / --yellow / --elevated',
        (tester) async {
      const expected = {
        NeoCardVariant.normal: (KoiColors.neoWhite, 6.0),
        NeoCardVariant.yellow: (KoiColors.neoYellow, 5.0),
        NeoCardVariant.elevated: (KoiColors.neoWhite, 8.0),
      };
      for (final MapEntry(key: variant, value: (color, shadow))
          in expected.entries) {
        await tester.pumpWidget(
            _wrap(NeoCard(variant: variant, child: const Text('c'))));
        final d = tester
            .widget<Container>(find.descendant(
                of: find.byType(NeoCard), matching: find.byType(Container)))
            .decoration! as BoxDecoration;
        expect(d.color, color);
        expect(d.boxShadow!.single.offset, Offset(shadow, shadow));
        expect((d.border! as Border).top.width, 2.5);
        expect(d.borderRadius, const BorderRadius.all(Radius.circular(20)));
      }
    });
  });

  group('NeoInput', () {
    BoxDecoration fieldDecoration(WidgetTester tester) => tester
        .widget<AnimatedContainer>(find.descendant(
            of: find.byType(NeoInput),
            matching: find.byType(AnimatedContainer)))
        .decoration! as BoxDecoration;

    testWidgets('shows label, placeholder and error text', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox(
          width: 300,
          child: NeoInput(
              label: 'Name', placeholder: 'Type here', error: 'Required'))));
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Type here'), findsOneWidget);
      final error = tester.widget<Text>(find.text('Required'));
      expect(error.style!.color, KoiColors.danger);
      expect(error.style!.fontSize, 12);
    });

    testWidgets('empty label/error are hidden (JS truthiness)', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox(
          width: 300, child: NeoInput(label: '', error: ''))));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('focus: blue border + focus ring', (tester) async {
      await tester.pumpWidget(_wrap(
          const SizedBox(width: 300, child: NeoInput(placeholder: 'p'))));
      var d = fieldDecoration(tester);
      expect((d.border! as Border).top.color, KoiColors.neoBlack);
      expect(d.boxShadow, isEmpty);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      d = fieldDecoration(tester);
      expect((d.border! as Border).top.color, KoiColors.neoBlue);
      expect(d.boxShadow!.single.spreadRadius, 3);
      expect(d.borderRadius, const BorderRadius.all(Radius.circular(12)));
    });

    testWidgets('typing reports changes; multiline is a textarea',
        (tester) async {
      String? last;
      await tester.pumpWidget(_wrap(SizedBox(
          width: 300,
          child: NeoInput(multiline: true, onChanged: (v) => last = v))));
      await tester.enterText(find.byType(TextField), 'hello');
      expect(last, 'hello');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.minLines, 2);
      expect(field.maxLines, isNull);
    });
  });
}
