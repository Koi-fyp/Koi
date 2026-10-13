import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chat/widgets/chat_widgets.dart' show StrokeIcon;
import '../landing/koi_footer.dart';
import '../landing/reveal.dart';
import '../onboarding/step_layout.dart' show bodyText;
import '../settings/widgets/settings_widgets.dart'
    show SettingsToastLayer, ToastMessage, ToastType;
import '../shell/svg_path.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_text.dart';
import 'info_widgets.dart';

/// Mirrors src/app/about/page.tsx at phone width (see info_widgets.dart for
/// the shared conventions). Every CDN image (`.page-bg`, the timeline's
/// pattern.webp, the vecteezy team-card images) is left out; their colour
/// and gradient layers are kept (decision 2026-10-14).
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, required this.links});

  final InfoLinks links;

  /// Mobile-only toast for the team cards' "Learn more →" (no handler on
  /// web; decision 2026-10-14).
  static const String learnMoreSoon = 'Profiles coming soon!';

  // VALUES (about/page.tsx:5-10)
  static const List<(String, String, String)> values = [
    (
      '🤝',
      'Radical Empathy',
      'We build every feature by asking: would this make someone feel more heard or less? Empathy is not a feature — it is the foundation.',
    ),
    (
      '🔒',
      'Privacy First',
      'Your thoughts are yours. We designed KOI from day one to work without accounts, without data harvesting, without compromise.',
    ),
    (
      '🌍',
      'Built for Pakistan',
      'Mental health support in Pakistan is scarce and stigmatised. KOI speaks Urdu, understands local context, and is free — always.',
    ),
    (
      '🧪',
      'Honest Technology',
      'KOI is transparent about being an AI. We will never pretend otherwise. Trust is built through honesty, not illusion.',
    ),
  ];

  // TIMELINE (about/page.tsx:12-17)
  static const List<(String, String, String)> timeline = [
    (
      '2024',
      'The Idea',
      'Born from a personal experience of loneliness — the realisation that sometimes you just need something to listen, at 2am, without judgment.',
    ),
    (
      'Early 2025',
      'First Build',
      'A small team of two. The first working prototype with emotion detection and on-device encryption. Tested quietly with 50 users in Lahore.',
    ),
    (
      'Mid 2025',
      'Urdu Support',
      "KOI learns to speak Urdu. The first AI companion that can hold a meaningful conversation in Pakistan's native tongue.",
    ),
    (
      'Now',
      'Growing',
      'Thousands of conversations. Constant iteration. A deepening belief that accessible mental health support can change lives.',
    ),
  ];

  // Mission list (about/page.tsx:110-115)
  static const List<(String, String)> missionPoints = [
    ('🇵🇰', 'Made in Pakistan, for Pakistan'),
    ('💬', '50,000+ conversations and counting'),
    ('🔐', 'Zero data ever sold or shared'),
    ('🌙', 'Available at 2am when you need it most'),
  ];

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

const Color _blue = Color(0xFF2D63EB);

class _AboutScreenState extends State<AboutScreen> {
  final ScrollController _scroll = ScrollController();
  bool _scrolled = false; // window.scrollY > 20
  ToastMessage? _toast;
  int _toastSeq = 0;

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

  void _learnMore() => setState(
    () => _toast = ToastMessage(
      AboutScreen.learnMoreSoon,
      ToastType.info,
      ++_toastSeq,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: KoiColors.background,
      body: Stack(
        children: [
          SingleChildScrollView(
            key: const Key('about-scroll'),
            controller: _scroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(context, topInset),
                _mission(),
                _values(),
                _TeamSection(onLearnMore: _learnMore),
                _timeline(),
                KoiFooter(
                  links: [
                    ('Home', widget.links.home),
                    ('How It Works', widget.links.howItWorks),
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
          SettingsToastLayer(
            toast: _toast,
            onClose: () => setState(() => _toast = null),
          ),
        ],
      ),
    );
  }

  // HERO: pt-32 pb-16 px-6 (+ status bar)
  Widget _hero(BuildContext context, double topInset) {
    final hero = KoiText.hero(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 128 + topInset, 24, 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InfoNeoTag('Our Story'),
          const SizedBox(height: 24 + 16), // tag mb-6 + h1 mt-4
          Text.rich(
            key: const Key('about-hero-title'),
            TextSpan(
              style: hero,
              children: const [
                // `we&nbsp;<span>needed</span>`: a no-break space.
                TextSpan(text: 'We built KOI\nbecause we '),
                TextSpan(
                  text: 'needed',
                  style: TextStyle(color: _blue),
                ),
                TextSpan(text: '\nit ourselves.'),
              ],
            ),
          ),
          const SizedBox(height: 24), // mb-6
          Text(
            'Loneliness is an epidemic. In Pakistan alone, millions navigate '
            'anxiety, grief, and disconnection with nowhere to turn. We '
            'decided to build something that could sit with you in those '
            'moments — quietly, privately, without judgment.',
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

  // MISSION: py-8 pb-16 px-6; neo-card p-8; flex-col gap-10
  Widget _mission() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 64),
    child: Reveal(
      child: Container(
        key: const Key('about-mission'),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: KoiColors.neoWhite,
          border: Border.all(width: 2.5),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(offset: Offset(6, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const InfoEyebrow('Our Mission', color: Color(0x66000000)),
            Padding(
              padding: const EdgeInsets.only(bottom: 24), // mb-6
              child: Text(
                'Mental health support should be as accessible as a text '
                'message.',
                style: infoHeading(30),
              ),
            ),
            Text(
              'We are not building a product. We are building infrastructure '
              'for emotional wellbeing — one conversation at a time. KOI '
              'exists to make that support available to anyone, anywhere, in '
              'any language, at any hour.',
              style: bodyText(
                16,
                color: const Color(0x99000000), // black/60
                height: 1.625,
              ),
            ),
            const SizedBox(height: 40), // gap-10
            for (final (i, (icon, text))
                in AboutScreen.missionPoints.indexed) ...[
              if (i > 0) const SizedBox(height: 16), // gap-4
              Container(
                padding: const EdgeInsets.all(16), // p-4
                decoration: BoxDecoration(
                  color: const Color(0x05000000), // bg-black/[0.02]
                  border: Border.all(
                    width: 2,
                    color: const Color(0x1A000000), // black/10
                  ),
                  borderRadius: BorderRadius.circular(12), // rounded-xl
                ),
                child: Row(
                  children: [
                    Text(
                      icon,
                      style: const TextStyle(fontSize: 24, height: 32 / 24),
                    ),
                    const SizedBox(width: 16), // gap-4
                    Expanded(
                      child: Text(
                        text,
                        style: bodyText(
                          14,
                          weight: FontWeight.w700,
                          height: 20 / 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  // VALUES: py-16 px-6 bg-black, full width
  Widget _values() => ColoredBox(
    key: const Key('about-values'),
    color: KoiColors.neoBlack,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InfoEyebrow('What We Stand For', color: Color(0x66FFFFFF)),
          Padding(
            padding: const EdgeInsets.only(bottom: 56), // mb-14
            child: Text.rich(
              TextSpan(
                style: infoHeading(36, color: KoiColors.neoWhite),
                children: const [
                  TextSpan(text: "Our values aren't a poster.\n"),
                  TextSpan(
                    text: "They're the code.",
                    style: TextStyle(color: Color(0xFFFFD100)),
                  ),
                ],
              ),
            ),
          ),
          for (final (i, (icon, title, desc))
              in AboutScreen.values.indexed) ...[
            if (i > 0) const SizedBox(height: 20), // gap-5
            Reveal(
              delay: Duration(milliseconds: 100 * i),
              child: Container(
                padding: const EdgeInsets.all(32), // p-8
                decoration: BoxDecoration(
                  color: const Color(0x0DFFFFFF), // bg-white/5
                  border: Border.all(
                    width: 2,
                    color: const Color(0x1AFFFFFF), // white/10
                  ),
                  borderRadius: BorderRadius.circular(16), // rounded-2xl
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      icon,
                      style: const TextStyle(fontSize: 36, height: 40 / 36),
                    ),
                    const SizedBox(height: 16), // gap-4
                    Text(
                      title,
                      style: bodyText(
                        20,
                        weight: FontWeight.w900,
                        color: KoiColors.neoWhite,
                        height: 28 / 20,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      desc,
                      style: bodyText(
                        14,
                        color: const Color(0xFF9CA3AF),
                        height: 1.625,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  // TIMELINE: py-16 px-6
  Widget _timeline() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const InfoEyebrow('The Journey', color: Color(0x66000000)),
              Padding(
                padding: const EdgeInsets.only(bottom: 56), // mb-14
                child: Text.rich(
                  TextSpan(
                    style: infoHeading(36),
                    children: const [
                      TextSpan(text: 'How we got '),
                      TextSpan(
                        text: 'here.',
                        style: TextStyle(color: _blue),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Stack(
          children: [
            // Vertical line: left 22px, 6px wide, pill, border 1.5px #000.
            // Web layers a CDN pattern.webp over #FF6B6B; mobile shows the
            // solid coral only (decision 2026-10-14).
            Positioned(
              key: const Key('timeline-line'),
              top: 0,
              bottom: 0,
              left: 22,
              width: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(width: 1.5),
                ),
              ),
            ),
            Column(
              children: [
                for (final (i, (year, label, desc))
                    in AboutScreen.timeline.indexed)
                  Reveal(
                    delay: Duration(milliseconds: 150 * i),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 48), // pb-12
                      child: _TimelineItem(
                        index: i,
                        last: i == AboutScreen.timeline.length - 1,
                        year: year,
                        label: label,
                        desc: desc,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.index,
    required this.last,
    required this.year,
    required this.label,
    required this.desc,
  });

  final int index;
  final bool last;
  final String year;
  final String label;
  final String desc;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // w-11 h-11 rounded-full border-2 font-black text-xs; last blue/white
      // else yellow/black; 3px 3px 0 #000
      Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: last ? _blue : const Color(0xFFFFD100),
          border: Border.all(width: 2),
          boxShadow: const [BoxShadow(offset: Offset(3, 3))],
        ),
        child: Text(
          '${index + 1}',
          style: bodyText(
            12,
            weight: FontWeight.w900,
            color: last ? KoiColors.neoWhite : KoiColors.neoBlack,
            height: 16 / 12,
          ),
        ),
      ),
      const SizedBox(width: 32), // gap-8
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 6), // pt-1.5
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8), // mb-2
                child: Wrap(
                  spacing: 12, // gap-3
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      year.toUpperCase(),
                      style: bodyText(
                        12,
                        weight: FontWeight.w900,
                        color: const Color(0x66000000),
                        letterSpacing: 0.1 * 12,
                        height: 16 / 12,
                      ),
                    ),
                    InfoNeoTag(
                      label,
                      fontSize: 11.52, // 0.72rem
                      padding: const EdgeInsets.symmetric(
                        vertical: 2.4, // 0.15rem
                        horizontal: 9.6, // 0.6rem
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                desc,
                style: bodyText(
                  16,
                  weight: FontWeight.w500,
                  color: const Color(0xB3000000), // black/70
                  height: 1.625,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// TeamCards (about/page.tsx:227-452) at ≤480px: `.team-grid` is one
/// column (gap 1.25rem); `.team-card-h` stacks image over text; the
/// vertical card's rows are 240px / auto. Cards fade up 28px over 0.5s
/// (transform cubic-bezier(0.34,1.2,0.64,1)), staggered 0.12s, when 15%
/// visible. Hover lift is not mirrored.
class _TeamSection extends StatelessWidget {
  const _TeamSection({required this.onLearnMore});
  final VoidCallback onLearnMore;

  static Reveal _reveal(int i, Widget child) => Reveal(
    threshold: 0.15,
    duration: const Duration(milliseconds: 500),
    curve: const Cubic(0.34, 1.2, 0.64, 1),
    delay: Duration(milliseconds: 120 * i),
    child: child,
  );

  @override
  Widget build(BuildContext context) => Padding(
    // .team-section: padding 4rem 1.5rem
    padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoEyebrow('The People', color: Color(0x66000000)),
        Padding(
          padding: const EdgeInsets.only(bottom: 48), // mb-12
          child: Text.rich(
            TextSpan(
              style: infoHeading(36),
              children: const [
                TextSpan(text: 'Meet the '),
                TextSpan(
                  text: 'team.',
                  style: TextStyle(color: _blue),
                ),
              ],
            ),
          ),
        ),
        _reveal(
          0,
          _TeamCard(
            key: const Key('team-fatima'),
            background: const CssRadialBackground(Color(0xFFF3E8FF), [
              // .team-card-img default layers (vecteezy image left out)
              CssRadial(0.3, 0.5, Color(0x55C084FC), 0.6),
              CssRadial(0.8, 0.2, Color(0x44FB923C), 0.55),
              CssRadial(0.6, 0.8, Color(0x222D63EB), 0.5),
            ]),
            image: const _PhonePair(
              leftAngle: -6,
              leftBottom: 10,
              arrowBottom: 18,
              rightAngle: 4,
              left: [
                _Line.accent(),
                _Line(),
                _Line(width: 0.8),
                _Line(width: 0.5),
              ],
              right: [
                _Line(color: Color(0xFFFFD100), width: 0.7),
                _Line.accent(),
                _Line(width: 0.9),
                _Line(width: 0.4),
              ],
            ),
            avatar: const _Avatar('FH', Color(0xFFFFD100)),
            name: 'Fatima Hasan Gilani',
            id: 'SP23-BSE-047',
            role: 'AI Engineer & Research',
            desc: 'Leads model fine-tuning, emotion classification, and all things research.',
            onLearnMore: onLearnMore,
          ),
        ),
        const SizedBox(height: 20), // gap 1.25rem
        _reveal(
          1,
          _TeamCard(
            key: const Key('team-irsa'),
            background: const CssRadialBackground(Color(0xFFFEF9EE), [
              CssRadial(0.7, 0.3, Color(0x55FB923C), 0.55),
              CssRadial(0.2, 0.7, Color(0x332DD36F), 0.5),
              CssRadial(0.5, 0.5, Color(0x33FFD100), 0.6),
            ]),
            image: const _PhonePair(
              leftAngle: -4,
              leftBottom: 8,
              arrowBottom: 16,
              rightAngle: 3,
              left: [
                _Line(color: Color(0xFF2DD36F), width: 0.65),
                _Line(),
                _Line(width: 0.85),
                _Line(width: 0.45),
              ],
              right: [
                _Line(color: Color(0xFFFF9F43), width: 0.75),
                _Line(color: Color(0xFF2DD36F), width: 0.55),
                _Line(),
                _Line(width: 0.6),
              ],
            ),
            avatar: const _Avatar('IN', Color(0xFF2DD36F)),
            name: 'Irsa Noor',
            id: 'SP23-BSE-063',
            role: 'Architecture & Solutions',
            desc: 'Owns system design, data architecture, and solution scalability.',
            onLearnMore: onLearnMore,
          ),
        ),
        const SizedBox(height: 20),
        _reveal(
          2,
          _AhmadCard(key: const Key('team-ahmad'), onLearnMore: onLearnMore),
        ),
      ],
    ),
  );
}

/// `.team-card-h` / `.team-card-v` frame: border 3px, radius 8px,
/// box-shadow 6px 6px #000000ba, overflow hidden.
BoxDecoration _cardFrame() => BoxDecoration(
  border: Border.all(width: 3),
  borderRadius: BorderRadius.circular(8),
  boxShadow: const [BoxShadow(color: Color(0xBA000000), offset: Offset(6, 6))],
);

/// Horizontal card at ≤480px: image area (min-height 180px, centred) over
/// the text area.
class _TeamCard extends StatelessWidget {
  const _TeamCard({
    super.key,
    required this.background,
    required this.image,
    required this.avatar,
    required this.name,
    required this.id,
    required this.role,
    required this.desc,
    required this.onLearnMore,
  });

  final CssRadialBackground background;
  final Widget image;
  final Widget avatar;
  final String name;
  final String id;
  final String role;
  final String desc;
  final VoidCallback onLearnMore;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: _cardFrame(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 180),
          child: CustomPaint(
            painter: background,
            child: Center(heightFactor: 1, child: image),
          ),
        ),
        _TextArea(
          children: [
            avatar,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: KoiText.display(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1D1D1D),
                    height: 1.5,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  id,
                  style: bodyText(
                    12,
                    weight: FontWeight.w600,
                    color: _blue,
                    height: 16 / 12,
                  ),
                ),
              ],
            ),
            Text(
              role,
              style: bodyText(
                14,
                weight: FontWeight.w600,
                color: const Color(0xFF626570),
                height: 1.5,
              ),
            ),
            Text(
              desc,
              style: bodyText(12, color: const Color(0xFF626570), height: 1.5),
            ),
            _LearnMore(onTap: onLearnMore),
          ],
        ),
      ],
    ),
  );
}

/// The vertical card (Ahmad): rows 240px / auto at ≤768px; the image
/// area also has min-height 220px.
class _AhmadCard extends StatelessWidget {
  const _AhmadCard({super.key, required this.onLearnMore});
  final VoidCallback onLearnMore;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: _cardFrame(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 240,
          child: CustomPaint(
            painter: const CssRadialBackground(Color(0xFFEEF2FF), [
              CssRadial(0.4, 0.4, Color(0x442D63EB), 0.55),
              CssRadial(0.8, 0.7, Color(0x44C084FC), 0.5),
              CssRadial(0.2, 0.8, Color(0x33FB923C), 0.45),
            ]),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Avatar(
                    'AS',
                    _blue,
                    color: KoiColors.neoWhite,
                    size: 88,
                    fontSize: 28.8, // 1.8rem
                  ),
                  const SizedBox(height: 12), // gap 12px
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Transform.rotate(
                        angle: -5 * math.pi / 180,
                        child: const _PhoneFrame(
                          width: 42,
                          height: 72,
                          lines: [_Line.accent(), _Line(), _Line(width: 0.7)],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: _CurvedArrow(size: 22),
                      ),
                      const SizedBox(width: 8),
                      Transform.rotate(
                        angle: 4 * math.pi / 180,
                        child: const _PhoneFrame(
                          width: 42,
                          height: 72,
                          lines: [
                            _Line(color: Color(0xFFFFD100), width: 0.8),
                            _Line.accent(),
                            _Line(width: 0.5),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        _TextArea(
          top: 32, // paddingTop 2rem; justifyContent flex-start
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ahmad Suleman',
                  style: KoiText.display(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1D1D1D),
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4), // mt-1
                Text(
                  'SP23-BSE-002',
                  style: bodyText(
                    12,
                    weight: FontWeight.w600,
                    color: _blue,
                    height: 16 / 12,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8), // mt-2
              child: Text(
                'Web Stack & Cloud',
                style: bodyText(
                  14,
                  weight: FontWeight.w600,
                  color: const Color(0xFF626570),
                  height: 1.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4), // mt-1
              child: Text(
                'Builds and maintains the full-stack infrastructure — from '
                'Next.js frontend to Firebase cloud functions. Owns '
                'deployment, CI/CD, and performance.',
                style: bodyText(
                  14,
                  color: const Color(0xFF626570),
                  height: 1.6,
                ),
              ),
            ),
            // inline marginTop 1rem replaces .team-btn's 0.5rem
            _LearnMore(onTap: onLearnMore, top: 16),
          ],
        ),
      ],
    ),
  );
}

/// `.team-card-text`: #fcfcfc, padding 1.5rem, flex-col, gap 0.5rem.
class _TextArea extends StatelessWidget {
  const _TextArea({required this.children, this.top = 24});
  final List<Widget> children;
  final double top;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFFCFCFC),
    child: Padding(
      padding: EdgeInsets.fromLTRB(24, top, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            children[i],
          ],
        ],
      ),
    ),
  );
}

/// `.team-avatar`: 72px circle, border 3px, display 800 1.5rem, shadow 4px.
class _Avatar extends StatelessWidget {
  const _Avatar(
    this.initials,
    this.background, {
    this.color = KoiColors.neoBlack,
    this.size = 72,
    this.fontSize = 24,
  });

  final String initials;
  final Color background;
  final Color color;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: background,
      border: Border.all(width: 3),
      boxShadow: const [BoxShadow(offset: Offset(4, 4))],
    ),
    child: Text(
      initials,
      style: KoiText.display(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        color: color,
        height: 1,
        letterSpacing: 0,
      ),
    ),
  );
}

/// `.team-btn` "Learn more →": #FFD100, 700 .8rem, border 2px, radius 6px,
/// padding .35rem .875rem, shadow 3px, margin-top .5rem. Web has no click
/// handler (hover only); mobile shows a "coming soon" toast (decision
/// 2026-10-14) and uses web's hover look (translate 3px, no shadow) as the
/// pressed state.
class _LearnMore extends StatefulWidget {
  const _LearnMore({required this.onTap, this.top = 8});
  final VoidCallback onTap;
  final double top;

  @override
  State<_LearnMore> createState() => _LearnMoreState();
}

class _LearnMoreState extends State<_LearnMore> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: widget.top),
    child: Semantics(
      button: true,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120), // 0.12s ease
          curve: Curves.ease,
          transform: Matrix4.translationValues(_down ? 3 : 0, _down ? 3 : 0, 0),
          padding: const EdgeInsets.symmetric(vertical: 5.6, horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD100),
            border: Border.all(width: 2),
            borderRadius: BorderRadius.circular(6),
            // hover: box-shadow 0 0 0 #000
            boxShadow: [
              BoxShadow(offset: Offset(_down ? 0 : 3, _down ? 0 : 3)),
            ],
          ),
          child: Text(
            'Learn more →',
            style: bodyText(12.8, weight: FontWeight.w700),
          ),
        ),
      ),
    ),
  );
}

/// One `.phone-line`: height 4px, pill, #e5e5e5 (accent: #2D63EB, 60%);
/// [width] is the inline percentage (default 100%).
class _Line {
  const _Line({this.color = const Color(0xFFE5E5E5), this.width = 1});
  const _Line.accent() : color = _blue, width = 0.6;
  final Color color;
  final double width;
}

/// `.phone-frame` (52x90, border 3px, radius 10px, white, shadow 3px) with
/// its ::before notch (top 6px, centred, 18x3 black pill) and
/// `.phone-inner` (margin-top 16px, padding 4px, gap 3px).
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.lines, this.width = 52, this.height = 90});

  final List<_Line> lines;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: KoiColors.neoWhite,
      border: Border.all(width: 3),
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [BoxShadow(offset: Offset(3, 3))],
    ),
    child: Stack(
      children: [
        Positioned(
          // top 6px from the padding box (inside the 3px border)
          top: 6,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 18,
              height: 3,
              decoration: BoxDecoration(
                color: KoiColors.neoBlack,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16 + 4, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const SizedBox(height: 3),
                FractionallySizedBox(
                  widthFactor: lines[i].width,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: lines[i].color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

// The 28x28 arrow: "M4 22 C4 10, 16 4, 24 8" and "M20 6 L24 8 L21 12",
// stroke #000 2.5, round caps/joins.
final List<Path> _arrowPaths = [
  parseSvgPath('M4 22 C4 10, 16 4, 24 8'),
  parseSvgPath('M20 6 L24 8 L21 12'),
];

class _CurvedArrow extends StatelessWidget {
  const _CurvedArrow({this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => StrokeIcon(
    paths: _arrowPaths,
    size: size,
    strokeWidth: 2.5,
    color: KoiColors.neoBlack,
    viewBox: 28,
  );
}

/// Two tilted phones with the arrow between them (`display: flex; gap:
/// 10px; align-items: flex-end`).
class _PhonePair extends StatelessWidget {
  const _PhonePair({
    required this.leftAngle,
    required this.leftBottom,
    required this.arrowBottom,
    required this.rightAngle,
    required this.left,
    required this.right,
  });

  final double leftAngle;
  final double leftBottom;
  final double arrowBottom;
  final double rightAngle;
  final List<_Line> left;
  final List<_Line> right;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Padding(
        padding: EdgeInsets.only(bottom: leftBottom),
        child: Transform.rotate(
          angle: leftAngle * math.pi / 180,
          child: _PhoneFrame(lines: left),
        ),
      ),
      const SizedBox(width: 10),
      Padding(
        padding: EdgeInsets.only(bottom: arrowBottom),
        child: const _CurvedArrow(),
      ),
      const SizedBox(width: 10),
      Transform.rotate(
        angle: rightAngle * math.pi / 180,
        child: _PhoneFrame(lines: right),
      ),
    ],
  );
}
