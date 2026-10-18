import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/dev/design_gallery.dart';
import 'package:koi_mobile/main.dart';
import 'package:koi_mobile/widgets/neo_button.dart';

void main() {
  test('ATC-M0-17 gallery is off unless --dart-define=KOI_DESIGN_GALLERY=true', () {
    expect(showDesignGallery, isFalse);
  });

  testWidgets('ATC-M0-17 gallery renders every section without errors', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Design Gallery (debug)'), findsOneWidget);
    for (final section in [
      'Colours',
      'Shadows',
      'Radii',
      'Text',
      'Motion',
      'NeoButton',
      'NeoCard',
      'NeoInput',
    ]) {
      await tester.scrollUntilVisible(find.text(section), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(section), findsOneWidget);
      if (section == 'NeoButton') {
        // Check while on screen; ListView disposes off-screen children.
        await tester.scrollUntilVisible(find.text('fullWidth'), 300,
            scrollable: find.byType(Scrollable).first);
        expect(find.byType(NeoButton), findsWidgets);
      }
    }
    expect(tester.takeException(), isNull);
  });
}
