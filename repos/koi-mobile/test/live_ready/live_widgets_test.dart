import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/account_settings.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/app/root_router.dart';
import 'package:koi_mobile/landing/koi_footer.dart';
import 'package:koi_mobile/platform/platform_client.dart';

import '../support/mob1_fakes.dart';
import '../support/real_fonts.dart';

Future<void> _pumpApp(WidgetTester tester, Mob1Harness h) async {
  await h.secrets.setLinkedSecret(h.auth.user!.uid, 'pw'); // no unlock
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3; // 360 x 800 dp
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      child: const MaterialApp(home: RootRouter()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('nav-tab-settings')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.ensureVisible(find.byKey(const Key('row-account')));
  await tester.pump();
}

Finder _inRow(String text) => find.descendant(
  of: find.byKey(const Key('row-account')),
  matching: find.text(text),
);

void main() {
  useRealFonts();

  group('LIVE-11 Settings → Account row for signed-in users', () {
    testWidgets('Care confirmed: "Signed in as <email>", no second line', (
      tester,
    ) async {
      final h = Mob1Harness(
        user: AccountFakeAuth.registered('g1', 'g@x'),
        caps: {'g1': generalCaps},
      );
      await _pumpApp(tester, h);
      await _openSettings(tester);
      expect(_inRow('Signed in as g@x'), findsOneWidget);
      expect(_inRow(accountNoCareText), findsNothing);
    });

    testWidgets(
      'capabilities unavailable: note shown; tap opens the Care tab',
      (tester) async {
        final h = Mob1Harness(user: AccountFakeAuth.registered('g1', 'g@x'));
        h.source.error = const PlatformException(PlatformErrorCode.network);
        await _pumpApp(tester, h);
        await _openSettings(tester);
        expect(_inRow('Signed in as g@x'), findsOneWidget);
        expect(_inRow(accountNoCareText), findsOneWidget);
        await tester.tap(find.byKey(const Key('row-account')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(const Key('care-unavailable')), findsOneWidget);
        expect(find.byKey(const Key('row-account')), findsNothing);
      },
    );

    testWidgets('not set up for Care: note shown; tap → "not set up" page', (
      tester,
    ) async {
      final h = Mob1Harness(
        user: AccountFakeAuth.registered('u1', 'new@x'),
        caps: {
          'u1': const KoiCapabilities(
            role: KoiRole.general, // every flag off (MOB-4 fixture)
            accountState: AccountState.registered,
          ),
        },
      );
      await _pumpApp(tester, h);
      await _openSettings(tester);
      expect(_inRow('Signed in as new@x'), findsOneWidget);
      expect(_inRow(accountNoCareText), findsOneWidget);
      await tester.tap(find.byKey(const Key('row-account')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('care-not-set-up')), findsOneWidget);
    });

    testWidgets('a long email wraps at 320 dp (no overflow)', (tester) async {
      final h = Mob1Harness(
        user: AccountFakeAuth.registered(
          'g1',
          'a.very.long.address.for.testing@example-domain.com',
        ),
      );
      h.source.error = const PlatformException(PlatformErrorCode.network);
      await h.secrets.setLinkedSecret('g1', 'pw');
      tester.view.physicalSize = const Size(960, 2400); // 320 dp
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          child: const MaterialApp(home: RootRouter()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await _openSettings(tester);
      expect(tester.takeException(), isNull);
      expect(_inRow(accountNoCareText), findsOneWidget);
    });
  });

  group('LIVE-12 landing footer at 320 dp', () {
    for (final width in [320.0, 360.0]) {
      testWidgets('no overflow at ${width.toInt()} dp, same links', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width * 3, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: KoiFooter(
                  links: [
                    ('About', () {}),
                    ('How It Works', () {}),
                    ('FAQ', () {}),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final l in ['About', 'How It Works', 'FAQ']) {
          expect(find.byKey(Key('footer-$l')), findsOneWidget);
        }
        expect(
          find.text('Anonymous sign-in · Encrypted local history'),
          findsOneWidget,
        );
      });
    }
  });
}
