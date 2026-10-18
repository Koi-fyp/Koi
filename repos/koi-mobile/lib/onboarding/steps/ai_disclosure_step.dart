import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shell/svg_path.dart';
import '../../theme/koi_colors.dart';
import '../../widgets/neo_button.dart';
import '../../widgets/neo_card.dart';
import '../step_layout.dart';

/// One crisis helpline row, from AIDisclosureStep.tsx.
@immutable
class Helpline {
  const Helpline(this.name, this.tel, this.href);
  final String name;
  final String tel;
  final String href;
}

/// Opens a `tel:` URL in the dialer. Injectable for tests.
typedef UrlOpener = Future<void> Function(Uri uri);

Future<void> _launch(Uri uri) async {
  // launchUrl directly (no canLaunchUrl), so no <queries> manifest entry is
  // needed (url_launcher 6.3.3 README, Android section).
  await launchUrl(uri);
}

/// Mirrors src/components/onboarding/AIDisclosureStep.tsx.
class AIDisclosureStep extends StatefulWidget {
  const AIDisclosureStep({
    super.key,
    required this.onNext,
    this.openUrl = _launch,
  });

  final VoidCallback onNext;
  final UrlOpener openUrl;

  static const List<Helpline> helplines = [
    Helpline('Umang (Mental Health)', '0311-7786264', 'tel:03117786264'),
    Helpline('Rozan Counselling', '0800-22444', 'tel:080022444'),
    Helpline('Emergency Services', '15 / 1122', 'tel:15'),
  ];

  /// Default [UrlOpener]: opens the dialer.
  static Future<void> defaultOpen(Uri uri) => _launch(uri);

  static const String aiCheck = 'I understand KOI is an AI, not a therapist';
  // AIDisclosureStep.tsx:30 (223e97c).
  static const String privacyCheck =
      'I understand saved history is encrypted, while inference receives '
      'readable text';

  @override
  State<AIDisclosureStep> createState() => _AIDisclosureStepState();
}

class _AIDisclosureStepState extends State<AIDisclosureStep> {
  bool _checkedAI = false;
  bool _checkedPrivacy = false;

  @override
  Widget build(BuildContext context) {
    return StepLayout(
      contentBottomPadding: 16,
      buttonGap: 16,
      button: NeoButton(
        key: const Key('disclosure-next'),
        fullWidth: true,
        onPressed: _checkedAI && _checkedPrivacy ? widget.onNext : null,
        child: const Text('I Agree →'),
      ),
      children: [
        const StepTitle('Important Notice', bottom: 20),
        // Warning card: NeoCard variant="yellow" className="p-4 mb-4"
        SizedBox(
          width: double.infinity,
          child: NeoCard(
            variant: NeoCardVariant.yellow,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KOI is an AI, not a therapist',
                        style: displayText(14.4),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        // JSX line break collapses to a space.
                        'KOI cannot diagnose mental health conditions and is '
                        'not a substitute for professional care. In an '
                        'emergency, contact emergency services immediately.',
                        style: bodyText(
                          13.6,
                          color: const Color(0xFF333333),
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Crisis helplines: NeoCard className="p-4 mb-5"
        SizedBox(
          width: double.infinity,
          child: NeoCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: KoiColors.neoCoral,
                        border: Border.all(width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '!',
                        style: displayText(
                          11.2,
                          weight: FontWeight.w800,
                          color: KoiColors.neoWhite,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Crisis Helplines (Pakistan)',
                      style: displayText(13.6),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < AIDisclosureStep.helplines.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _HelplineRow(
                    helpline: AIDisclosureStep.helplines[i],
                    onTap: () => widget.openUrl(
                      Uri.parse(AIDisclosureStep.helplines[i].href),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _CheckRow(
          key: const Key('check-ai'),
          label: AIDisclosureStep.aiCheck,
          checked: _checkedAI,
          onChanged: () => setState(() => _checkedAI = !_checkedAI),
        ),
        const SizedBox(height: 14), // gap 0.875rem
        _CheckRow(
          key: const Key('check-privacy'),
          label: AIDisclosureStep.privacyCheck,
          checked: _checkedPrivacy,
          onChanged: () => setState(() => _checkedPrivacy = !_checkedPrivacy),
        ),
      ],
    );
  }
}

class _HelplineRow extends StatelessWidget {
  const _HelplineRow({required this.helpline, required this.onTap});
  final Helpline helpline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Flexible(
        child: Text(
          helpline.name,
          style: bodyText(13.6, color: const Color(0xFF444444)),
        ),
      ),
      Semantics(
        link: true,
        child: GestureDetector(
          key: Key('tel-${helpline.href}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(
            helpline.tel,
            style: displayText(13.6, color: KoiColors.neoCoral),
          ),
        ),
      ),
    ],
  );
}

/// The `<label>` + role="checkbox" button. Tapping the label text toggles too
/// (a `<label>` forwards clicks to its button).
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    super.key,
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final bool checked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: checked,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            // transition: background 0.15s ease
            duration: const Duration(milliseconds: 150),
            curve: Curves.ease,
            margin: const EdgeInsets.only(top: 1),
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: checked ? KoiColors.neoBlue : KoiColors.neoWhite,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(width: 2.5),
              boxShadow: const [BoxShadow(offset: Offset(2, 2))],
            ),
            child: checked
                ? const SizedBox.square(
                    dimension: 13,
                    child: CustomPaint(painter: _CheckPainter()),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: bodyText(
                14.4,
                color: const Color(0xFF333333),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The checkmark: `<svg width="13" height="13" viewBox="0 0 12 12">` with
/// `<path d="M2 6l3 3 5-5">`, stroke white, strokeWidth 2, round caps/joins.
class _CheckPainter extends CustomPainter {
  const _CheckPainter();

  static final Path _path = parseSvgPath('M2 6l3 3 5-5');

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 12, size.height / 12);
    canvas.drawPath(
      _path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = KoiColors.neoWhite
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => false;
}
