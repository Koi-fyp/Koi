import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/info/about_screen.dart';
import 'package:koi_mobile/info/how_it_works_screen.dart';
import 'package:koi_mobile/info/info_widgets.dart';

import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

/// Sign-in that "fails" the way AuthContext does: no throw, no user.
class _FailingAuth extends FakeAuthService {
  @override
  Future<void> signInAnonymously() async {
    signInCalls++;
    set(user: null, loading: false, error: StateError('offline'));
  }
}

void main() {
  useRealFonts();

  late List<String> taps;
  InfoLinks links() => InfoLinks(
    home: () => taps.add('home'),
    faq: () => taps.add('faq'),
    about: () => taps.add('about'),
    howItWorks: () => taps.add('how'),
  );

  /// Pumps a stand-in landing page and pushes [page] on top of it, like the
  /// real landing page does.
  Future<FakeAuthService> pump(
    WidgetTester tester,
    Widget page, {
    FakeAuthService? auth,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400); // 360x800dp
    addTearDown(tester.view.reset);
    taps = [];
    final a = auth ?? FakeAuthService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesFor(a, onboardingStore()),
        child: const MaterialApp(home: Scaffold(body: Text('landing-stub'))),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return a;
  }

  Future<void> scrollThrough(WidgetTester tester, Key key) async {
    for (var i = 0; i < 30; i++) {
      await tester.drag(find.byKey(key), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  }

  /// Scrolls [f] to mid-screen (the fixed nav covers the top 64px).
  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(f);
    await tester.pump();
  }

  group('How it works', () {
    testWidgets('all web text, no CDN images, no overflow at 360dp', (
      tester,
    ) async {
      await pump(tester, HowItWorksScreen(links: links()));
      expect(find.text('Under the Hood'), findsOneWidget);
      expect(
        find.text('How KOI\nactually\nworks.', findRichText: true),
        findsOneWidget,
      );
      for (final p in HowItWorksScreen.pillars) {
        await tester.ensureVisible(find.text(p.title));
        expect(find.text(p.title), findsOneWidget);
        expect(find.text(p.subtitle.toUpperCase()), findsOneWidget);
        expect(find.text(p.desc), findsOneWidget);
        for (final pt in p.points) {
          expect(find.text(pt), findsOneWidget, reason: pt);
        }
      }
      // The one reworded line (decision 2026-10-14).
      expect(
        find.text(
          'Offline-first: conversations stored in local encrypted storage '
          'on your device',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('IndexedDB'), findsNothing);
      expect(find.byType(Image), findsNothing);
      await scrollThrough(tester, const Key('how-scroll'));
      expect(find.text('READY?'), findsOneWidget);
      expect(
        find.text(
          'Start with Firebase anonymous sign-in and choose your companion.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Start button fits inside the closing card', (tester) async {
      await pump(tester, HowItWorksScreen(links: links()));
      final button = find.byKey(const Key('how-start'));
      await tester.ensureVisible(button);
      await tester.pump(const Duration(seconds: 1));
      final card = tester.getRect(find.byKey(const Key('how-cta')));
      final b = tester.getRect(button);
      expect(b.left, greaterThanOrEqualTo(card.left));
      expect(b.right, lessThanOrEqualTo(card.right));
      final label = tester.getSize(find.text(HowItWorksScreen.startLabel));
      // "Start Talking ✦" (how-it-works/page.tsx:269) is ~113dp.
      expect(label.width, greaterThan(100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Start: signs in, then closes back to the app router', (
      tester,
    ) async {
      final auth = await pump(tester, HowItWorksScreen(links: links()));
      await tapVisible(tester, find.byKey(const Key('how-start')));
      await tester.pump(const Duration(seconds: 1));
      expect(auth.signInCalls, 1);
      expect(find.byType(HowItWorksScreen), findsNothing);
      expect(find.text('landing-stub'), findsOneWidget);
    });

    testWidgets('Start: a failed sign-in stays on the page and re-enables', (
      tester,
    ) async {
      final auth = await pump(
        tester,
        HowItWorksScreen(links: links()),
        auth: _FailingAuth(),
      );
      await tapVisible(tester, find.byKey(const Key('how-start')));
      await tester.pump(const Duration(seconds: 1));
      expect(auth.signInCalls, 1);
      expect(find.byType(HowItWorksScreen), findsOneWidget);
      expect(find.text(HowItWorksScreen.startLabel), findsOneWidget);
    });

    testWidgets('nav and footer links', (tester) async {
      await pump(tester, HowItWorksScreen(links: links()));
      await tester.tap(find.byKey(const Key('info-nav-start')));
      await tester.tap(find.byKey(const Key('info-nav-logo')));
      for (final l in ['Home', 'About', 'FAQ']) {
        await tapVisible(tester, find.byKey(Key('footer-$l')));
      }
      expect(taps, ['home', 'home', 'home', 'about', 'faq']);
    });

    testWidgets('nav shrinks to 52px after scrolling 20px', (tester) async {
      await pump(tester, HowItWorksScreen(links: links()));
      expect(tester.getSize(find.byKey(const Key('info-nav'))).height, 64);
      await tester.drag(
        find.byKey(const Key('how-scroll')),
        const Offset(0, -100),
      );
      await tester.pump(); // the 300ms height transition starts here
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getSize(find.byKey(const Key('info-nav'))).height, 52);
    });
  });

  group('About', () {
    testWidgets('all web text, no CDN images, no overflow at 360dp', (
      tester,
    ) async {
      await pump(tester, AboutScreen(links: links()));
      expect(find.text('Our Story'), findsOneWidget);
      expect(
        find.text(
          'We built KOI\nbecause we needed\nit ourselves.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      for (final t in [
        'OUR MISSION',
        'Mental health support should be as accessible as a text message.',
        for (final (_, text) in AboutScreen.missionPoints) text,
        'WHAT WE STAND FOR',
        for (final (_, title, desc) in AboutScreen.values) ...[title, desc],
        'THE PEOPLE',
        'Fatima Hasan Gilani',
        'SP23-BSE-047',
        'AI Engineer & Research',
        'Irsa Noor',
        'SP23-BSE-063',
        'Architecture & Solutions',
        'Ahmad Suleman',
        'SP23-BSE-002',
        'Web Stack & Cloud',
        'THE JOURNEY',
        for (final (year, label, desc) in AboutScreen.timeline) ...[
          year.toUpperCase(),
          label,
          desc,
        ],
      ]) {
        await tester.ensureVisible(find.text(t));
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Learn more →'), findsNothing);
      expect(find.text(AboutScreen.biographyUnavailable), findsNWidgets(3));
      expect(find.byType(Image), findsNothing);
      await scrollThrough(tester, const Key('about-scroll'));
    });

    testWidgets('team buttons are disabled "Biography unavailable"', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, AboutScreen(links: links()));
      final button = find.text(AboutScreen.biographyUnavailable).first;
      // Reveal keeps the card at opacity 0 (no semantics) until 15% shows.
      Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.getSemantics(button),
        matchesSemantics(
          label: 'Biography unavailable',
          tooltip: 'Additional biography is unavailable',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      handle.dispose();
      await tester.tap(button);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('coming soon'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('copy matches web 223e97c: no invented numbers or dates', (
      tester,
    ) async {
      expect(AboutScreen.timeline.map((t) => t.$1), [
        'Purpose',
        'Foundation',
        'Language',
        'Now',
      ]);
      final all = [
        for (final v in AboutScreen.values) v.$3,
        for (final t in AboutScreen.timeline) t.$3,
        for (final m in AboutScreen.missionPoints) m.$2,
        for (final p in HowItWorksScreen.pillars) ...[p.desc, ...p.points],
        HowItWorksScreen.startLabel,
      ].join(' | ');
      for (final banned in [
        '50,000+',
        'Lahore',
        '2024',
        '2025',
        'Thousands',
        'free',
        'Free',
        'without accounts',
        'fine-tuned',
        'No one can',
        'opt-in',
        'Colour-tinted',
        'Crisis detection',
        'Web app',
        'IndexedDB',
      ]) {
        expect(all, isNot(contains(banned)), reason: banned);
      }
      expect(all, contains('This is CSE at rest, not end-to-end encryption.'));
    });

    testWidgets('timeline line runs the full height, solid coral', (
      tester,
    ) async {
      await pump(tester, AboutScreen(links: links()));
      final line = find.byKey(const Key('timeline-line'));
      await tester.ensureVisible(line);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.getSize(line).width, 6);
      expect(tester.getSize(line).height, greaterThan(400));
      final deco =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: line,
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(deco.color, const Color(0xFFFF6B6B));
    });

    testWidgets('footer links', (tester) async {
      await pump(tester, AboutScreen(links: links()));
      for (final l in ['Home', 'How It Works', 'FAQ']) {
        await tapVisible(tester, find.byKey(Key('footer-$l')));
      }
      expect(taps, ['home', 'how', 'faq']);
    });
  });

  testWidgets('signed-in user is not required to view the pages', (
    tester,
  ) async {
    await pump(
      tester,
      AboutScreen(links: links()),
      auth: FakeAuthService(
        fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
      ),
    );
    expect(find.byType(AboutScreen), findsOneWidget);
  });
}
