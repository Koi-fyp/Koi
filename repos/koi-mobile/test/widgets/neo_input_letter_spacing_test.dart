import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/theme/koi_theme.dart';
import 'package:koi_mobile/widgets/neo_input.dart';

/// globals.css `.neo-input` and NeoInput.tsx set no letter-spacing (CSS
/// `normal` = 0). Under the app's Material 3 theme, a TextField style without
/// letterSpacing inherits bodyLarge's 0.5 and Text inherits bodyMedium's
/// 0.25, so every part of NeoInput must set 0 explicitly.
void main() {
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: KoiTheme.light(), // the real app theme, which caused the leak
      home: const Scaffold(
        body: NeoInput(
          label: 'Label',
          error: 'Error',
          placeholder: 'Placeholder',
        ),
      ),
    ),
  );

  /// The style Flutter actually lays [text] out with (DefaultTextStyle and
  /// theme merged in), for a Text widget.
  double? renderedSpacing(WidgetTester tester, String text) {
    final rich = tester.widget<RichText>(
      find.descendant(
        of: find.byType(NeoInput),
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == text,
        ),
      ),
    );
    return rich.text.style?.letterSpacing;
  }

  testWidgets('ATC-M0-15 typed text: letterSpacing 0 (theme bodyLarge is 0.5)', (
    tester,
  ) async {
    await pump(tester);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.style.letterSpacing, 0);
  });

  testWidgets('ATC-M0-15 placeholder, label and error: letterSpacing 0', (tester) async {
    await pump(tester);
    for (final t in ['Placeholder', 'Label', 'Error']) {
      expect(renderedSpacing(tester, t), 0, reason: t);
    }
  });
}
