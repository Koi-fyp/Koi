import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/landing/color_grid.dart';
import 'package:koi_mobile/landing/landing_screen.dart';
import 'package:koi_mobile/info/about_screen.dart';
import 'package:koi_mobile/info/how_it_works_screen.dart';

import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

void main() {
  useRealFonts();

  Future<FakeAuthService> pumpLanding(
    WidgetTester tester, {
    Object? error,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400); // 360x800dp
    addTearDown(tester.view.reset);
    final auth = FakeAuthService(fakeError: error);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesFor(auth, onboardingStore()),
        child: const MaterialApp(home: LandingScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 2)); // hero staggers done
    return auth;
  }

  final scroll = find.byKey(const Key('landing-scroll'));

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(
      f,
      300,
      scrollable: find.descendant(
        of: scroll,
        matching: find.byType(Scrollable),
      ),
    );
    // Keep the target out from under the fixed nav (64dp + status bar).
    if (tester.getRect(f).top < 140) {
      await tester.drag(scroll, const Offset(0, 160));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1)); // reveal animations
  }

  testWidgets('every section renders at 360dp without overflow', (
    tester,
  ) async {
    await pumpLanding(tester);
    expect(tester.takeException(), isNull);

    expect(find.text('AI Companion · Free to use'), findsOneWidget);
    expect(find.byKey(const Key('hero-title')), findsOneWidget);
    expect(find.text(LandingScreen.startLabel), findsOneWidget);
    expect(find.text('No account · No credit card'), findsOneWidget);
    expect(find.text('Get Started →'), findsOneWidget);

    for (final f in [
      find.text('THINK'),
      find.text('🐟 Meet KOI'),
      find.text('Conversations possible'),
      find.text('WHY KOI'),
      for (final (_, title, _) in LandingScreen.features) find.text(title),
      find.text('GOT QUESTIONS'),
      for (final q in LandingScreen.faqs) find.text(q.q),
      find.text('How We Do It →'),
      find.text('Talk to KOI ✦'),
      find.text('Private · No account · Always free'),
      find.text('© 2025 KOI · All rights reserved'),
      find.text('Built with care in Pakistan 🇵🇰'),
    ]) {
      await scrollTo(tester, f);
      expect(f, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('BLOCKS: 10 blocks with web colours, labels and heights', (
    tester,
  ) async {
    expect(ColorGrid.blocks.map((b) => b.label), [
      'Think',
      'Feel',
      'Grow',
      'Talk',
      'Learn',
      'Rest',
      'Dream',
      'Reflect',
      'Connect',
      'Explore',
    ]);
    expect(
      [for (var i = 0; i < 4; i++) ColorGrid.heightFor(i)],
      [110, 90, 100, 110],
    );
    await pumpLanding(tester);
    for (final b in ColorGrid.blocks) {
      expect(find.text(b.label.toUpperCase()), findsOneWidget);
    }
  });

  testWidgets('hero CTA signs in; error state shows web copy', (tester) async {
    final auth = await pumpLanding(tester);
    await tester.tap(find.byKey(const Key('landing-start')));
    await tester.pump();
    expect(auth.signInCalls, 1);
  });

  testWidgets('error state', (tester) async {
    await pumpLanding(tester, error: Exception('offline'));
    expect(find.text(LandingScreen.errorText), findsOneWidget);
    expect(find.text(LandingScreen.retryLabel), findsOneWidget);
  });

  testWidgets('nav shrinks to 52dp once scrolled past 20px', (tester) async {
    await pumpLanding(tester);
    final nav = find.byKey(const Key('landing-nav'));
    final top = MediaQuery.paddingOf(tester.element(nav)).top;
    expect(tester.getSize(nav).height, 64 + top);
    await tester.drag(scroll, const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(nav).height, 52 + top);
  });

  testWidgets('FAQ: one open at a time, tap again closes', (tester) async {
    await pumpLanding(tester);
    final q0 = find.byKey(const Key('faq-0'));
    await scrollTo(tester, q0);
    final answer0 = find.text(LandingScreen.faqs[0].a);
    double h(Finder f) => tester
        .getSize(find.ancestor(of: f, matching: find.byType(ClipRect)).first)
        .height;
    expect(h(answer0), 0);

    await tester.tap(q0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(h(answer0), greaterThan(50));

    await tester.tap(find.byKey(const Key('faq-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(h(answer0), 0);
    expect(h(find.text(LandingScreen.faqs[1].a)), greaterThan(50));

    await tester.tap(find.byKey(const Key('faq-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(h(find.text(LandingScreen.faqs[1].a)), 0);
  });

  testWidgets('How We Do It / About open the info pages', (tester) async {
    await pumpLanding(tester);
    final how = find.byKey(const Key('landing-how-it-works'));
    await scrollTo(tester, how);
    await tester.tap(how);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HowItWorksScreen), findsOneWidget);
    // The KOI logo is web's <Link href="/">: back to the landing page.
    await tester.tap(find.byKey(const Key('info-nav-logo')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HowItWorksScreen), findsNothing);

    final about = find.byKey(const Key('footer-About'));
    await scrollTo(tester, about);
    await tester.tap(about);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AboutScreen), findsOneWidget);
  });

  testWidgets('About → FAQ link returns here and scrolls to the FAQ', (
    tester,
  ) async {
    await pumpLanding(tester);
    final about = find.byKey(const Key('footer-About'));
    await scrollTo(tester, about);
    await tester.tap(about);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AboutScreen), findsOneWidget);

    final faq = find.byKey(const Key('footer-FAQ'));
    // Mid-screen, clear of the fixed nav.
    Scrollable.ensureVisible(tester.element(faq), alignment: 0.5);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(faq);
    await tester.pump();
    // Pop, then the 0.5s smooth scroll to #faq, frame by frame.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(AboutScreen), findsNothing);
    final q = tester.getRect(find.text(LandingScreen.faqs.first.q));
    expect(q.top, greaterThanOrEqualTo(0));
    expect(
      q.bottom,
      lessThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      ),
    );
  });
}
