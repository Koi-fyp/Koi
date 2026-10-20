import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/auth_entry_widgets.dart';
import '../care/care_strings.dart';
import '../app/providers.dart';
import '../core/auth/auth_service.dart';
import '../onboarding/step_layout.dart';
import '../info/about_screen.dart';
import '../info/how_it_works_screen.dart';
import '../info/info_widgets.dart' show InfoLinks;
import '../theme/koi_colors.dart';
import '../theme/koi_motion.dart';
import '../theme/koi_text.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_spinner.dart';
import 'color_grid.dart';
import 'faq_accordion.dart';
import 'koi_footer.dart';
import 'reveal.dart';

/// Landing page. Mirrors repos/koi-backend/nextjs_app/src/app/page.tsx at
/// phone width, i.e. with the web's own small-screen classes (no sm:/md:/lg:
/// variants): one column, desktop nav links hidden (`hidden md:flex`).
///
/// Background: solid #ffe5d9; the `.grain` / `.page-bg` CDN images are not
/// loaded (Q10).
///
/// Tailwind: 1 unit = 4px; v3.4.19 defaults (text-xs .75rem/1rem, text-sm
/// .875rem/1.25rem, text-base 1rem/1.5rem, text-lg 1.125rem/1.75rem, text-3xl
/// 1.875rem/2.25rem, text-4xl 2.25rem/2.5rem, leading-tight 1.25,
/// leading-relaxed 1.625, tracking-widest .1em, tracking-tight -.025em,
/// gray-400 #9ca3af, gray-500 #6b7280, gray-600 #4b5563, red-500 #ef4444).
/// Text without a font class is body DM Sans, loaded 300–700, so font-black
/// renders at 700.
class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({super.key});

  static const List<(String, String, String)> features = [
    (
      '🧠',
      'Remembers You',
      'Uses recent context and restores saved local history.',
    ),
    (
      '⚡',
      'Streaming Replies',
      'Replies stream when the service is available; connection can take time.',
    ),
    (
      '🔒',
      'Encrypted Storage',
      'History is encrypted locally. Inference processes the text you send.',
    ),
    (
      '🎯',
      'Text Companion',
      'Text conversation requires connectivity and service availability.',
    ),
  ];

  static const List<Faq> faqs = [
    Faq(
      'Is KOI a replacement for therapy?',
      'No. KOI is an AI companion designed for everyday emotional support, reflection, and connection — not clinical treatment. If you are experiencing a mental health crisis, please reach out to a qualified professional or a crisis helpline.',
    ),
    Faq(
      'Do I need to create an account?',
      'KOI uses Firebase anonymous sign-in. No email is required. Saved history is encrypted on this device.',
    ),
    Faq(
      'How is my data kept private?',
      'Saved content uses AES-256-GCM client-side encryption. Inference receives readable prompts and recent context. This is not end-to-end encryption.',
    ),
    Faq(
      'What languages does KOI support?',
      'You can save an English or Urdu preference during onboarding. Interface translation and reply language are not guaranteed.',
    ),
    Faq(
      'How does KOI detect how I am feeling?',
      'The service supplies companion expression metadata. Avatar animations are not a diagnosis or a mental-health measurement.',
    ),
    Faq(
      'Can I use KOI during a crisis?',
      'KOI can display service-supplied safety information. It is not an emergency service and cannot guarantee detection or immediate help. Contact a trusted local emergency provider when needed.',
    ),
    Faq(
      'Is KOI available offline?',
      // app/page.tsx:57 says "when browser storage and encryption are
      // available" and "Messages are not automatically resent". Mobile has no
      // browser and still queues offline messages (G18 open), so those two
      // parts are reworded / kept from the old copy (decision 2026-10-18).
      'Saved history may be restored when device storage and encryption are available. New replies require a connection. Messages composed offline will be queued and sent automatically when you reconnect.',
    ),
  ];

  // Hero CTA strings
  static const String startLabel = 'Start Talking ✦';
  static const String startingLabel = 'Getting ready…';
  static const String errorText =
      'Sign-in could not connect. Check your network and try again.';

  /// Mobile-only (approved 2026-10-17): Firebase anonymous sign-in is turned
  /// off in the console.
  static const String anonymousDisabledText =
      'Sign-in is turned off for this app right now. Please try again later.';

  static String errorTextFor(Object? error) =>
      error is AnonymousSignInDisabledError ? anonymousDisabledText : errorText;
  static const String retryLabel = 'Try Again';
  static const String retryingLabel = 'Connecting…';

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

const Color _gray400 = Color(0xFF9CA3AF);
const Color _gray500 = Color(0xFF6B7280);
const Color _gray600 = Color(0xFF4B5563);

class _LandingScreenState extends ConsumerState<LandingScreen> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _faqKey = GlobalKey();
  bool _starting = false; // useState(false)
  bool _scrolled = false; // window.scrollY > 20

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final s = _scroll.offset > 20;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // handleGetStarted. Web only resets `starting` if signInAnonymously()
  // throws; AuthContext never rethrows. Mirrored as-is.
  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await ref.read(authServiceProvider).signInAnonymously();
    } catch (_) {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  /// Back to this page (web `<Link href="/">`): pops About / How it works.
  void _popToLanding() =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  /// Links used by the About and How it works pages.
  late final InfoLinks _infoLinks = InfoLinks(
    home: _popToLanding,
    faq: () {
      // `/#faq`: back to the landing page, then scroll to the FAQ.
      _popToLanding();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFaq());
    },
    about: () => _open(AboutScreen(links: _infoLinks)),
    howItWorks: () => _open(HowItWorksScreen(links: _infoLinks)),
  );

  // `<a href="#faq">` with html { scroll-behavior: smooth }
  void _scrollToFaq() {
    final ctx = _faqKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.ease,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);
    final isLoading = _starting || auth.loading;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: KoiColors.background,
      body: Stack(
        children: [
          SingleChildScrollView(
            key: const Key('landing-scroll'),
            controller: _scroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(
                  context,
                  topInset,
                  isLoading,
                  auth.error != null && auth.user == null,
                ),
                _features(),
                KeyedSubtree(key: _faqKey, child: _faq()),
                _howItWorksCta(),
                _readyCta(isLoading),
                _footer(),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _Nav(
              scrolled: _scrolled,
              topInset: topInset,
              isLoading: isLoading,
              onStart: _start,
            ),
          ),
        ],
      ),
    );
  }

  // ── HERO ───────────────────────────────────────────────────────────────
  Widget _hero(
    BuildContext context,
    double topInset,
    bool isLoading,
    bool showError,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    final hero = KoiText.hero(width);

    KoiFadeUp stagger(double delaySeconds, Widget child) => KoiFadeUp(
      // .hero-stagger-N: fadeUp 0.6s ease <delay> both
      spec: KoiAnimationSpec(
        duration: const Duration(milliseconds: 600),
        delay: Duration(milliseconds: (delaySeconds * 1000).round()),
      ),
      child: child,
    );

    return Padding(
      // pt-24 pb-16 px-6 (+ status bar, which the web viewport excludes)
      padding: EdgeInsets.fromLTRB(24, 96 + topInset, 24, 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              stagger(0, const _NeoTag()),
              const SizedBox(height: 24), // gap-6
              stagger(
                0.1,
                Text.rich(
                  key: const Key('hero-title'),
                  TextSpan(
                    style: hero,
                    children: [
                      const TextSpan(text: 'Your '),
                      const TextSpan(
                        text: 'mind',
                        style: TextStyle(color: Color(0xFF2D63EB)),
                      ),
                      const TextSpan(text: '\ndeserves a '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: _StrokedText(
                          'friend.',
                          style: hero.copyWith(color: const Color(0xFFFFD100)),
                          strokeWidth: 2, // WebkitTextStroke: '2px #000'
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              stagger(
                0.2,
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 448), // max-w-md
                  child: Text(
                    // JSX line break collapses to a space.
                    'KOI is a thoughtful AI companion that listens without '
                    'judgment, remembers the details that matter, and grows '
                    'with you — every single day.',
                    style: bodyText(
                      18,
                      weight: FontWeight.w500,
                      color: _gray600,
                      height: 1.625,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              stagger(0.35, const _SocialProof()),
              const SizedBox(height: 24),
              stagger(
                0.5,
                showError
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // role="alert" (app/page.tsx:203)
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              LandingScreen.errorTextFor(
                                ref.read(authServiceProvider).error,
                              ),
                              style: bodyText(
                                14,
                                weight: FontWeight.w600,
                                color: const Color(0xFFEF4444),
                                height: 20 / 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12), // gap-3
                          NeoButton(
                            key: const Key('landing-start'),
                            onPressed: isLoading ? null : _start,
                            child: Text(
                              isLoading
                                  ? LandingScreen.retryingLabel
                                  : LandingScreen.retryLabel,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        // flex-col items-start gap-4
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NeoButton(
                            key: const Key('landing-start'),
                            onPressed: isLoading ? null : _start,
                            child: isLoading
                                ? const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      NeoSpinner(color: KoiColors.neoWhite),
                                      SizedBox(width: 8),
                                      Text(LandingScreen.startingLabel),
                                    ],
                                  )
                                : const Text(LandingScreen.startLabel),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Anonymous sign-in · Local history',
                            style: bodyText(
                              14,
                              weight: FontWeight.w500,
                              color: _gray400,
                              height: 20 / 14,
                            ),
                          ),
                          // MOB-1 / AUTH-ENTRY (mobile-only): registered
                          // accounts. "Start Talking" above stays the
                          // no-account path, unchanged.
                          const SizedBox(height: 24),
                          AccountChoiceButtons(
                            keyPrefix: 'landing',
                            enabled: !isLoading,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            ref.watch(careStringsProvider).t(CareText.auWhy),
                            key: const Key('landing-account-why'),
                            style: bodyText(
                              14,
                              weight: FontWeight.w500,
                              color: _gray600,
                              height: 20 / 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const PsychologistLink(),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 48), // gap-12
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 384), // max-w-sm
              child: const ColorGrid(),
            ),
          ),
        ],
      ),
    );
  }

  // ── FEATURES ───────────────────────────────────────────────────────────
  Widget _features() {
    return Container(
      color: KoiColors.neoBlack,
      padding: const EdgeInsets.symmetric(
        vertical: 64,
        horizontal: 24,
      ), // py-16 px-6
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Eyebrow('Why KOI', color: const Color(0x66FFFFFF)), // white/40
          const SizedBox(height: 16),
          _SectionTitle(
            lead: 'Built for real ',
            accent: 'humans.',
            color: KoiColors.neoWhite,
            accentColor: const Color(0xFFFFD100),
            size: 36,
            lineHeight: 1.25,
          ),
          const SizedBox(height: 56), // mb-14
          for (var i = 0; i < LandingScreen.features.length; i++) ...[
            if (i > 0) const SizedBox(height: 20), // gap-5
            Reveal(
              delay: Duration(milliseconds: i * 100), // transitionDelay i*0.1s
              child: _FeatureCard(LandingScreen.features[i]),
            ),
          ],
        ],
      ),
    );
  }

  // ── FAQ ────────────────────────────────────────────────────────────────
  Widget _faq() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Reveal(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Eyebrow(
              'Got Questions',
              color: const Color(0x66000000),
            ), // black/40
            const SizedBox(height: 16),
            _SectionTitle(
              lead: 'Everything you ',
              accent: 'need to know.',
              color: KoiColors.neoBlack,
              accentColor: const Color(0xFF2D63EB),
              size: 36,
              lineHeight: 1.25,
            ),
            const SizedBox(height: 48), // mb-12
            const FaqAccordion(items: LandingScreen.faqs),
          ],
        ),
      ),
    );
  }

  // ── HOW IT WORKS CTA ───────────────────────────────────────────────────
  Widget _howItWorksCta() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 64), // py-8 pb-16 px-6
      child: Reveal(
        child: _CtaCard(
          background: const Color(0xFF0A0A0A),
          shadowColor: const Color(0xFF2D63EB),
          blobs: const [
            // w-96 h-96 #FFD100 opacity-10, translate(30%,-30%), blur(60px)
            _Blob(
              size: 384,
              color: Color(0xFFFFD100),
              opacity: 0.1,
              top: true,
              right: true,
              blur: 60,
            ),
          ],
          children: [
            _Eyebrow(
              'Under the hood',
              color: const Color(0x66FFFFFF),
              bottom: 12,
            ),
            _SectionTitle(
              lead: 'Curious how KOI ',
              accent: 'actually works?',
              color: KoiColors.neoWhite,
              accentColor: const Color(0xFFFFD100),
              size: 30,
              lineHeight: 1.25,
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Text(
                'From emotion detection to on-device encryption — explore the philosophy and technology behind your AI companion.',
                style: bodyText(
                  16,
                  color: const Color(0x99FFFFFF),
                  height: 1.625,
                ), // white/60
              ),
            ),
            const SizedBox(height: 32), // gap-8
            NeoButton(
              key: const Key('landing-how-it-works'),
              variant: NeoButtonVariant.secondary,
              customFontSize: 16,
              customPadding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 32,
              ),
              onPressed: () => _infoLinks.howItWorks(),
              child: const Text('How We Do It →'),
            ),
          ],
        ),
      ),
    );
  }

  // ── READY CTA ──────────────────────────────────────────────────────────
  Widget _readyCta(bool isLoading) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 64),
      child: Reveal(
        child: _CtaCard(
          background: const Color(0xFF2D63EB),
          shadowColor: KoiColors.neoBlack,
          blobs: const [
            // w-64 h-64 #FFD100 opacity-20, translate(30%,-30%)
            _Blob(
              size: 256,
              color: Color(0xFFFFD100),
              opacity: 0.2,
              top: true,
              right: true,
            ),
            // w-48 h-48 #fff opacity-10, translate(-30%,30%)
            _Blob(
              size: 192,
              color: Color(0xFFFFFFFF),
              opacity: 0.1,
              top: false,
              right: false,
            ),
          ],
          children: [
            _Eyebrow(
              'Start today',
              color: const Color(0x99FFFFFF),
              bottom: 12,
            ), // white/60
            _SectionTitle(
              lead: 'Ready to feel ',
              accent: 'heard?',
              color: KoiColors.neoWhite,
              accentColor: const Color(0xFFFFD100),
              size: 30,
              lineHeight: 1.25,
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Text(
                'Start with anonymous sign-in, choose a companion, and open a text conversation.',
                style: bodyText(
                  16,
                  color: const Color(0xB3FFFFFF),
                  height: 1.625,
                ), // white/70
              ),
            ),
            const SizedBox(height: 32),
            _TalkButton(isLoading: isLoading, onTap: _start),
            const SizedBox(height: 16), // gap-4
            Text(
              'Text chat · Encrypted local history',
              style: bodyText(
                12,
                weight: FontWeight.w600,
                color: const Color(0x80FFFFFF),
                height: 16 / 12,
              ), // white/50
            ),
          ],
        ),
      ),
    );
  }

  // ── FOOTER ─────────────────────────────────────────────────────────────
  Widget _footer() => KoiFooter(
    links: [
      ('About', _infoLinks.about),
      ('How It Works', _infoLinks.howItWorks),
      ('FAQ', _scrollToFaq),
    ],
  );
}

/// The fixed top nav. Unscrolled: 64px, white/75; scrolled (>20px): 52px,
/// white/97 + `0 4px 0 0 #000` shadow; `transition-all duration-300`;
/// `backdrop-blur-md` (12px); `border-b-2 border-black`.
class _Nav extends StatelessWidget {
  const _Nav({
    required this.scrolled,
    required this.topInset,
    required this.isLoading,
    required this.onStart,
  });

  final bool scrolled;
  final double topInset;
  final bool isLoading;
  final VoidCallback onStart;

  static const Duration transition = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          key: const Key('landing-nav'),
          duration: transition,
          curve: Curves.ease,
          height: (scrolled ? 52 : 64) + topInset,
          padding: EdgeInsets.only(top: topInset, left: 24, right: 24), // px-6
          decoration: BoxDecoration(
            color: scrolled ? const Color(0xF7FFFFFF) : const Color(0xBFFFFFFF),
            border: const Border(bottom: BorderSide(width: 2)),
            boxShadow: scrolled
                ? const [BoxShadow(offset: Offset(0, 4))]
                : const [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // w-9 h-9 rounded-xl text-lg font-black text-white
                  // border-2 border-black, #2D63EB, 2px 2px 0 #000
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D63EB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(width: 2),
                      boxShadow: const [BoxShadow(offset: Offset(2, 2))],
                    ),
                    child: Text(
                      'K',
                      style: bodyText(
                        18,
                        weight: FontWeight.w700,
                        color: KoiColors.neoWhite,
                        height: 28 / 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10), // gap-2.5
                  Text(
                    'KOI',
                    style: bodyText(
                      18,
                      weight: FontWeight.w700,
                      letterSpacing: -0.025 * 18,
                      height: 28 / 18,
                    ),
                  ),
                ],
              ),
              NeoButton(
                key: const Key('landing-nav-start'),
                customFontSize: 14, // fontSize 0.875rem
                customPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 20,
                ),
                onPressed: isLoading ? null : onStart,
                child: isLoading
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NeoSpinner(color: KoiColors.neoWhite, dimension: 14),
                          SizedBox(width: 8),
                          Text('Starting…'),
                        ],
                      )
                    : const Text('Get Started →'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// globals.css `.neo-tag` with the pulsing mint dot.
class _NeoTag extends StatelessWidget {
  const _NeoTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 4.8, horizontal: 14),
    decoration: BoxDecoration(
      color: KoiColors.neoGray,
      border: Border.all(color: const Color(0xFFE5E5E5), width: 1.5),
      borderRadius: BorderRadius.circular(9999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KoiPulseDot(
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF2DD36F),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 6), // gap .375rem
        Text(
          'AI Companion · Text conversation',
          style: bodyText(
            12.8,
            weight: FontWeight.w600,
            color: const Color(0xFF333333),
          ),
        ),
      ],
    ),
  );
}

/// The overlapping A/S/M/L circles + "Text & avatars for your conversations".
class _SocialProof extends StatelessWidget {
  const _SocialProof();

  static const List<(Color, String)> circles = [
    (Color(0xFFFFD100), 'A'),
    (Color(0xFF2D63EB), 'S'),
    (Color(0xFFFF6B6B), 'M'),
    (Color(0xFF2DD36F), 'L'),
  ];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      // flex -space-x-2: each circle overlaps the previous one by 8px
      SizedBox(
        width: 32 + 3 * 24,
        height: 32,
        child: Stack(
          children: [
            for (var i = 0; i < circles.length; i++)
              Positioned(
                left: i * 24.0,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: circles[i].$1,
                    shape: BoxShape.circle,
                    border: Border.all(color: KoiColors.neoWhite, width: 2),
                  ),
                  child: Text(
                    circles[i].$2,
                    style: bodyText(
                      12,
                      weight: FontWeight.w700,
                      color: KoiColors.neoWhite,
                      height: 16 / 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 12), // gap-3
      Flexible(
        child: Text.rich(
          TextSpan(
            style: bodyText(
              14,
              weight: FontWeight.w500,
              color: _gray500,
              height: 20 / 14,
            ),
            children: const [
              TextSpan(
                text: 'Text & avatars',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: KoiColors.neoBlack,
                ),
              ),
              TextSpan(text: ' for your conversations'),
            ],
          ),
        ),
      ),
    ],
  );
}

/// `-webkit-text-stroke`: the stroke is drawn over the fill.
class _StrokedText extends StatelessWidget {
  const _StrokedText(
    this.text, {
    required this.style,
    required this.strokeWidth,
  });
  final String text;
  final TextStyle style;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Text(text, style: style),
      Text(
        text,
        style: style.copyWith(
          color: null,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..color = KoiColors.neoBlack,
        ),
      ),
    ],
  );
}

/// `text-xs font-black tracking-widest uppercase` eyebrow line.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text, {required this.color, this.bottom = 0});
  final String text;
  final Color color;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottom),
    child: Text(
      text.toUpperCase(),
      style: bodyText(
        12,
        weight: FontWeight.w700,
        color: color,
        letterSpacing: 0.1 * 12,
        height: 16 / 12,
      ),
    ),
  );
}

/// Section h2: `font-black leading-tight` with letterSpacing -0.03em and an
/// accent-coloured second part.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.lead,
    required this.accent,
    required this.color,
    required this.accentColor,
    required this.size,
    required this.lineHeight,
  });

  final String lead;
  final String accent;
  final Color color;
  final Color accentColor;
  final double size;
  final double lineHeight;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: bodyText(
        size,
        weight: FontWeight.w700,
        color: color,
        letterSpacing: -0.03 * size,
        height: lineHeight,
      ),
      children: [
        TextSpan(text: lead),
        TextSpan(
          text: accent,
          style: TextStyle(color: accentColor),
        ),
      ],
    ),
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard(this.feature);
  final (String, String, String) feature;

  @override
  Widget build(BuildContext context) {
    final (icon, title, desc) = feature;
    // flex-col gap-3 p-6 rounded-2xl border-2 border-white/10 bg-white/5
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 30, height: 36 / 30),
          ), // text-3xl
          const SizedBox(height: 12),
          Text(
            title,
            style: bodyText(
              18,
              weight: FontWeight.w700,
              color: KoiColors.neoWhite,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Text(desc, style: bodyText(14, color: _gray400, height: 1.625)),
        ],
      ),
    );
  }
}

/// A decorative circle in the CTA cards (`absolute rounded-full
/// pointer-events-none`), translated ±30% out of its corner.
class _Blob {
  const _Blob({
    required this.size,
    required this.color,
    required this.opacity,
    required this.top,
    required this.right,
    this.blur = 0,
  });
  final double size;
  final Color color;
  final double opacity;
  final bool top;
  final bool right;
  final double blur;
}

/// `relative overflow-hidden rounded-3xl p-8 border-2 border-black` with an
/// 8px 8px offset shadow; content `flex-col items-start`.
class _CtaCard extends StatelessWidget {
  const _CtaCard({
    required this.background,
    required this.shadowColor,
    required this.blobs,
    required this.children,
  });

  final Color background;
  final Color shadowColor;
  final List<_Blob> blobs;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(width: 2),
      boxShadow: [BoxShadow(color: shadowColor, offset: const Offset(8, 8))],
    ),
    child: Stack(
      children: [
        for (final b in blobs)
          Positioned(
            top: b.top ? 0 : null,
            bottom: b.top ? null : 0,
            right: b.right ? 0 : null,
            left: b.right ? null : 0,
            child: IgnorePointer(
              child: Transform.translate(
                offset: Offset(
                  (b.right ? 0.3 : -0.3) * b.size,
                  (b.top ? -0.3 : 0.3) * b.size,
                ),
                child: _blob(b),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(32), // p-8
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    ),
  );

  Widget _blob(_Blob b) {
    Widget circle = Opacity(
      opacity: b.opacity,
      child: Container(
        width: b.size,
        height: b.size,
        decoration: BoxDecoration(color: b.color, shape: BoxShape.circle),
      ),
    );
    if (b.blur > 0) {
      circle = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: b.blur, sigmaY: b.blur),
        child: circle,
      );
    }
    return circle;
  }
}

/// The inline-styled "Talk to KOI ✦" button: #FFD100, #000, weight 800
/// (DM Sans → 700), 1rem, radius 9999px, padding 1rem 2rem, border 2.5px,
/// shadow 4px 4px 0 #000, opacity 0.7 while loading; mousedown
/// translateY(2px) + 2px shadow (hover lift has no touch equivalent).
class _TalkButton extends StatefulWidget {
  const _TalkButton({required this.isLoading, required this.onTap});
  final bool isLoading;
  final VoidCallback onTap;

  @override
  State<_TalkButton> createState() => _TalkButtonState();
}

class _TalkButtonState extends State<_TalkButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.isLoading;
    final pressed = _pressed && enabled;
    return Opacity(
      opacity: widget.isLoading ? 0.7 : 1,
      child: GestureDetector(
        key: const Key('landing-talk'),
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          // transition: transform 0.12s ease, box-shadow 0.12s ease
          duration: const Duration(milliseconds: 120),
          curve: Curves.ease,
          transform: Matrix4.translationValues(0, pressed ? 2 : 0, 0),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD100),
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(width: 2.5),
            boxShadow: [
              BoxShadow(
                offset: pressed ? const Offset(2, 2) : const Offset(4, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading) ...[
                const NeoSpinner(color: KoiColors.neoBlack),
                const SizedBox(width: 8), // gap 0.5rem
              ],
              Text(
                widget.isLoading ? 'Getting ready…' : 'Talk to KOI ✦',
                softWrap: false,
                style: bodyText(16, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
