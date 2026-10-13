import 'package:flutter/material.dart';

import '../onboarding/step_layout.dart';
import '../theme/koi_colors.dart';

/// One FAQ entry (page.tsx `FAQS`).
@immutable
class Faq {
  const Faq(this.q, this.a);
  final String q;
  final String a;
}

/// globals.css `.faq-accordion` / `.faq-item` / `.faq-question` /
/// `.faq-icon` / `.faq-answer`, with page.tsx's one-open-at-a-time state
/// (`openFaq`). `:hover` (#f5ca00) has no touch equivalent and is dropped.
class FaqAccordion extends StatefulWidget {
  const FaqAccordion({super.key, required this.items});
  final List<Faq> items;

  @override
  State<FaqAccordion> createState() => _FaqAccordionState();
}

class _FaqAccordionState extends State<FaqAccordion> {
  int? _open; // useState<number | null>(null)

  @override
  Widget build(BuildContext context) {
    return Container(
      // border 2px #000; background #FFD100; radius 6px; overflow hidden;
      // box-shadow 4px 4px rgba(0,0,0,0.86)
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: KoiColors.neoYellow,
        border: Border.all(width: 2),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Color(0xDB000000), offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.items.length; i++)
            Container(
              // .faq-item border-bottom 2px; none on :last-child
              decoration: i < widget.items.length - 1
                  ? const BoxDecoration(
                      border: Border(bottom: BorderSide(width: 2)),
                    )
                  : null,
              child: _FaqItem(
                index: i,
                faq: widget.items[i],
                open: _open == i,
                onTap: () => setState(() => _open = _open == i ? null : i),
              ),
            ),
        ],
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  const _FaqItem({
    required this.index,
    required this.faq,
    required this.open,
    required this.onTap,
  });

  final int index;
  final Faq faq;
  final bool open;
  final VoidCallback onTap;

  // .faq-answer transition: max-height 0.35s cubic-bezier(0.4, 0, 0.2, 1)
  static const Curve answerCurve = Cubic(0.4, 0, 0.2, 1);
  static const Duration answerDuration = Duration(milliseconds: 350);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          key: Key('faq-$index'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            // transition: background 0.2s ease; .open → #ffe833
            duration: const Duration(milliseconds: 200),
            curve: Curves.ease,
            color: open ? const Color(0xFFFFE833) : KoiColors.neoYellow,
            // padding 1.1rem 1.5rem
            padding: const EdgeInsets.symmetric(vertical: 17.6, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // display 700 0.95rem #000
                Flexible(child: Text(faq.q, style: displayText(15.2))),
                AnimatedRotation(
                  // .faq-icon.open rotate(45deg), transform 0.25s ease
                  turns: open ? 45 / 360 : 0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.ease,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: KoiColors.neoBlack,
                      shape: BoxShape.circle,
                      border: Border.all(width: 2),
                    ),
                    // font-size 1rem; weight 900 → Bricolage's heaviest
                    // loaded weight, 800; color #FFD100
                    child: Text(
                      '+',
                      style: displayText(
                        16,
                        weight: FontWeight.w800,
                        color: KoiColors.neoYellow,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            heightFactor: open ? 1 : 0,
            duration: answerDuration,
            curve: answerCurve,
            child: AnimatedContainer(
              // padding 0 1.5rem → 1rem 1.5rem 1.25rem (0.25s ease);
              // background #fffde7; .open adds border-top 2px #000
              duration: const Duration(milliseconds: 250),
              curve: Curves.ease,
              width: double.infinity,
              padding: open
                  ? const EdgeInsets.fromLTRB(24, 16, 24, 20)
                  : const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFDE7),
                border: open
                    ? const Border(top: BorderSide(width: 2))
                    : const Border(
                        top: BorderSide(width: 0, style: BorderStyle.none),
                      ),
              ),
              child: Text(
                faq.a,
                // 0.9rem, line-height 1.7, #111, weight 500, body font
                style: bodyText(
                  14.4,
                  weight: FontWeight.w500,
                  color: const Color(0xFF111111),
                  height: 1.7,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
