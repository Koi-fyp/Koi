import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../landing/koi_footer.dart';
import '../landing/reveal.dart';
import '../onboarding/step_layout.dart' show bodyText;
import '../settings/widgets/settings_widgets.dart' show FitButtonLabel;
import '../theme/koi_colors.dart';
import '../theme/koi_text.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_spinner.dart';
import 'info_widgets.dart';

/// One entry of `PILLARS` in how-it-works/page.tsx.
@immutable
class Pillar {
  const Pillar(
    this.number,
    this.title,
    this.subtitle,
    this.color,
    this.textColor,
    this.desc,
    this.points,
  );
  final String number;
  final String title;
  final String subtitle;
  final Color color;
  final Color textColor;
  final String desc;
  final List<String> points;

  bool get light => textColor == KoiColors.neoWhite; // textColor === '#fff'
}

/// Mirrors src/app/how-it-works/page.tsx at phone width (see
/// info_widgets.dart for the shared conventions).
class HowItWorksScreen extends ConsumerStatefulWidget {
  const HowItWorksScreen({super.key, required this.links});

  final InfoLinks links;

  static const String startLabel = 'Start Talking ✦';
  static const String startingLabel = 'Getting ready…';

  static const List<Pillar> pillars = [
    Pillar(
      '01',
      'Your Companion',
      'What KOI is',
      Color(0xFFFFD100),
      KoiColors.neoBlack,
      'KOI is an AI companion — not a therapist, not a chatbot, not a search engine. It is a presence. Designed to listen deeply, remember what matters to you, and respond with warmth and without judgment. Think of KOI as an AI interface for reflection when the service is available.',
      [
        'Remembers context across your conversation',
        'Displays companion expressions supplied by the service',
        'English and Urdu preference; translation is not guaranteed',
        'Designed specifically for Pakistani users',
      ],
    ),
    Pillar(
      '02',
      'The AI Behind It',
      'How it thinks',
      Color(0xFF2D63EB),
      KoiColors.neoWhite,
      'KOI uses a language-model service for text responses. Responses can be incomplete or incorrect. The service also supplies companion expression metadata; these animations do not measure your mental-health condition.',
      [
        'Companion expressions: neutral, joy, angry, sorrow, fun',
        'Context window of recent messages for continuity',
        'Safety information when supplied by the service',
        'Saved history and visible connection errors',
      ],
    ),
    Pillar(
      '03',
      'Your Privacy',
      'How we protect you',
      Color(0xFF0A0A0A),
      KoiColors.neoWhite,
      'Conversation content is encrypted using AES-256-GCM before storage and sync attempts. Inference receives readable prompts and recent context. This is CSE at rest, not end-to-end encryption. Anonymous sign-in requires no email.',
      [
        'AES-256-GCM encryption, on-device key storage',
        'Firebase anonymous identity; email is optional',
        // how-it-works/page.tsx:46 says "stored in local IndexedDB"; mobile
        // stores them in Hive, so this line is reworded (decision
        // 2026-10-14). See WEB_BUGS_FOUND_DURING_MOBILE.md.
        'Offline-first: conversations stored in local encrypted storage on your device',
        'Encrypted sync may be pending or unavailable',
      ],
    ),
    Pillar(
      '04',
      'The Experience',
      'What it feels like',
      Color(0xFF2DD36F),
      KoiColors.neoBlack,
      'We obsessed over every detail of the KOI experience — the soft bounce of the avatar, the companion expressions supplied by the service, the gentle typing indicator. Every visual and interaction choice was made to create a sense of calm presence. KOI should feel less like an app and more like opening a door to a quiet room where you can think out loud.',
      [
        'Emotion-driven avatar with breathing + blinking animations',
        'Consistent colors; service-supplied expressions',
        // how-it-works/page.tsx:60-61 say "no automatic message resend" and
        // "reduced-motion support". Mobile still queues offline messages (G18
        // open) and does not honour reduce-motion, so these two lines keep
        // the old copy (decision 2026-10-18).
        'Offline-aware UI with queued message delivery',
        'Smooth animations designed to reduce anxiety, not add to it',
      ],
    ),
  ];

  @override
  ConsumerState<HowItWorksScreen> createState() => _HowItWorksScreenState();
}

class _HowItWorksScreenState extends ConsumerState<HowItWorksScreen> {
  final ScrollController _scroll = ScrollController();
  bool _scrolled = false; // window.scrollY > 20
  bool _loading = false; // StartButton useState(false)

  static const double _threshold = 0.1; // IntersectionObserver threshold

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

  /// StartButton.handle: signInAnonymously(), then router.replace(
  /// '/onboarding'). Decision 2026-10-14: instead of always forcing
  /// onboarding, close this page and let the root router decide like the
  /// landing page does (new users → onboarding, onboarded users → chat).
  Future<void> _start() async {
    setState(() => _loading = true);
    try {
      final auth = ref.read(authServiceProvider);
      await auth.signInAnonymously();
      if (!mounted) return;
      if (auth.user == null) {
        // Sign-in failed (the error shows on the landing page's own CTA).
        setState(() => _loading = false);
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: KoiColors.background,
      body: Stack(
        children: [
          SingleChildScrollView(
            key: const Key('how-scroll'),
            controller: _scroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(context, topInset),
                _pillars(),
                _closingCta(),
                KoiFooter(
                  links: [
                    ('Home', widget.links.home),
                    ('About', widget.links.about),
                    ('FAQ', widget.links.faq),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: InfoNav(
              scrolled: _scrolled,
              topInset: topInset,
              onHome: widget.links.home,
            ),
          ),
        ],
      ),
    );
  }

  // HERO: pt-32 pb-16 px-6 (+ status bar, which the web viewport excludes)
  Widget _hero(BuildContext context, double topInset) {
    final hero = KoiText.hero(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 128 + topInset, 24, 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InfoNeoTag('Under the Hood'),
          const SizedBox(height: 24 + 16), // tag mb-6 + h1 mt-4
          Text.rich(
            key: const Key('how-hero-title'),
            TextSpan(
              style: hero,
              children: const [
                TextSpan(text: 'How KOI\n'),
                TextSpan(
                  text: 'actually',
                  style: TextStyle(color: Color(0xFF2D63EB)),
                ),
                TextSpan(text: '\nworks.'),
              ],
            ),
          ),
          const SizedBox(height: 24), // mb-6
          Text(
            // JSX line break collapses to a space.
            'No magic. No mystery. Here is exactly what KOI is, how it '
            'thinks, how it protects you, and what we obsessed over to make '
            'it feel the way it does.',
            // text-xl leading-relaxed, #4B5563, 500
            style: bodyText(
              20,
              weight: FontWeight.w500,
              color: const Color(0xFF4B5563),
              height: 1.625,
            ),
          ),
        ],
      ),
    );
  }

  // PILLARS: pb-16 px-6, flex-col gap-8
  Widget _pillars() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 64),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, p) in HowItWorksScreen.pillars.indexed) ...[
          if (i > 0) const SizedBox(height: 32),
          Reveal(
            threshold: _threshold,
            delay: Duration(milliseconds: 100 * i), // transitionDelay i*0.1s
            child: _PillarCard(key: Key('pillar-${p.number}'), pillar: p),
          ),
        ],
      ],
    ),
  );

  // CLOSING CTA: py-8 pb-16 px-6; neo-card p-8 text-center
  Widget _closingCta() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 64),
    child: Reveal(
      threshold: _threshold,
      child: Container(
        key: const Key('how-cta'),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: KoiColors.neoWhite,
          border: Border.all(width: 2.5),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(offset: Offset(6, 6))],
        ),
        child: Column(
          children: [
            const InfoEyebrow('Ready?', color: Color(0x66000000)), // black/40
            Padding(
              padding: const EdgeInsets.only(bottom: 24), // mb-6
              child: Text.rich(
                TextSpan(
                  style: infoHeading(30),
                  children: const [
                    TextSpan(text: 'Now you know how it works.\n'),
                    TextSpan(
                      text: 'Come say hello.',
                      style: TextStyle(color: Color(0xFF2D63EB)),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 32), // mb-8
              child: Text(
                'Start with Firebase anonymous sign-in and choose your companion.',
                textAlign: TextAlign.center,
                style: bodyText(
                  16,
                  color: const Color(0x80000000), // black/50
                  height: 1.5,
                ),
              ),
            ),
            _startButton(),
          ],
        ),
      ),
    ),
  );

  /// StartButton: neo-btn-primary, fontSize 1rem, padding 1rem 2.5rem. At
  /// 360dp that is 279dp wide in a 243dp card, so mobile uses the standard
  /// .neo-btn 1.75rem sides and lets the label shrink slightly to fit
  /// (decision 2026-10-14).
  Widget _startButton() => NeoButton(
    key: const Key('how-start'),
    customFontSize: 16,
    customPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
    onPressed: _loading ? null : _start,
    child: _loading
        ? const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // w-4 h-4 border-2 border-white spinner
              NeoSpinner(color: KoiColors.neoWhite, dimension: 16),
              SizedBox(width: 8),
              Text(HowItWorksScreen.startingLabel),
            ],
          )
        : const FitButtonLabel(HowItWorksScreen.startLabel),
  );
}

/// One pillar card: rounded-3xl border-2 p-8, background = pillar colour,
/// shadow 6px 6px 0 #000, overflow hidden; big number watermark.
class _PillarCard extends StatelessWidget {
  const _PillarCard({super.key, required this.pillar});
  final Pillar pillar;

  @override
  Widget build(BuildContext context) {
    final p = pillar;
    final width = MediaQuery.sizeOf(context).width;
    // clamp(5rem, 15vw, 12rem)
    final watermark = (0.15 * width).clamp(80.0, 192.0);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.color,
        border: Border.all(width: 2),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(offset: Offset(6, 6))],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 16,
            right: 32,
            child: Text(
              p.number,
              style: KoiText.display(
                fontSize: watermark,
                fontWeight: FontWeight.w900, // font-black → 800 (bundled max)
                height: 1,
                letterSpacing: 0,
                color: p.light
                    ? const Color(0x12FFFFFF) // rgba(255,255,255,0.07)
                    : const Color(0x0F000000), // rgba(0,0,0,0.06)
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoEyebrow(
                  p.subtitle,
                  bottom: 12, // mb-3
                  color: p.light
                      ? const Color(0x80FFFFFF) // 0.5
                      : const Color(0x66000000), // 0.4
                ),
                Text(p.title, style: infoHeading(30, color: p.textColor)),
                const SizedBox(height: 40), // gap-10
                Text(
                  p.desc,
                  style: bodyText(
                    16,
                    weight: FontWeight.w500,
                    height: 1.625,
                    color: p.light
                        ? const Color(0xB3FFFFFF) // 0.7
                        : const Color(0xA6000000), // 0.65
                  ),
                ),
                const SizedBox(height: 24), // gap-6
                for (final (j, point) in p.points.indexed) ...[
                  if (j > 0) const SizedBox(height: 10), // gap-2.5
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.only(top: 2), // mt-0.5
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            width: 2,
                            color: p.light
                                ? const Color(0x66FFFFFF) // 0.4
                                : const Color(0x4D000000), // 0.3
                          ),
                        ),
                        child: Text(
                          '✓',
                          style: bodyText(
                            12,
                            weight: FontWeight.w900,
                            color: p.textColor,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12), // gap-3
                      Expanded(
                        child: Text(
                          point,
                          style: bodyText(
                            14,
                            weight: FontWeight.w600,
                            color: p.textColor,
                            height: 20 / 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
