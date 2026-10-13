import 'package:flutter/material.dart';

import '../../theme/koi_colors.dart';
import '../step_layout.dart';

/// One entry of `companions` in CompanionSelectionStep.tsx.
@immutable
class KoiCompanion {
  const KoiCompanion(this.id, this.name, this.trait, this.color, this.icon);
  final String id;
  final String name;
  final String trait;
  final Color color;
  final String icon;
}

/// Mirrors src/components/onboarding/CompanionSelectionStep.tsx at phone
/// width (grid-cols-1 below the md breakpoint).
///
/// The 'koi' companion keeps the 🦊 icon like web (2026-10-13: Q7 drops only
/// the fox *avatar*).
///
/// Tailwind: 1 unit = 4px; v3.4.19 defaults text-3xl 1.875rem/2.25rem,
/// text-2xl 1.5rem/2rem, text-lg 1.125rem/1.75rem, text-6xl 3.75rem/1,
/// gray-600 #4b5563, gray-500 #6b7280. Text without a font class inherits
/// body DM Sans, whose heaviest loaded weight is 700 (font-black → 700).
class CompanionSelectionStep extends StatefulWidget {
  const CompanionSelectionStep({super.key, required this.onNext});
  final ValueChanged<String> onNext;

  static const List<KoiCompanion> companions = [
    KoiCompanion('aisha', 'Aisha', 'Warm & caring', Color(0xFFFF4A60), '👩'),
    KoiCompanion('raza', 'Raza', 'Calm & grounded', Color(0xFFFFC224), '👨'),
    KoiCompanion('koi', 'Koi', 'Playful & curious', Color(0xFF06B6D4), '🦊'),
  ];

  @override
  State<CompanionSelectionStep> createState() => _CompanionSelectionStepState();
}

class _CompanionSelectionStepState extends State<CompanionSelectionStep> {
  String _selected = 'koi'; // useState('koi')

  @override
  Widget build(BuildContext context) {
    final selected = CompanionSelectionStep.companions.firstWhere(
      (c) => c.id == _selected,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32), // p-8
      child: Column(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose Your Companion',
                style: bodyText(30, weight: FontWeight.w700, height: 36 / 30),
              ),
              const SizedBox(height: 8), // mb-2
              Text(
                'Pick the personality that resonates with you',
                style: bodyText(
                  16,
                  color: const Color(0xFF4B5563),
                  height: 24 / 16,
                ),
              ),
              const SizedBox(height: 32), // mb-8
              for (
                var i = 0;
                i < CompanionSelectionStep.companions.length;
                i++
              ) ...[
                if (i > 0) const SizedBox(height: 24), // gap-6
                _CompanionCard(
                  companion: CompanionSelectionStep.companions[i],
                  isSelected:
                      CompanionSelectionStep.companions[i].id == _selected,
                  onSelect: () => setState(
                    () => _selected = CompanionSelectionStep.companions[i].id,
                  ),
                ),
              ],
            ],
          ),
          // gap-8 between the blocks + the button's own mt-8
          const SizedBox(height: 64),
          _ContinueButton(
            color: selected.color,
            label: 'Continue with ${selected.name}',
            onTap: () => widget.onNext(_selected),
          ),
        ],
      ),
    );
  }
}

class _CompanionCard extends StatelessWidget {
  const _CompanionCard({
    required this.companion,
    required this.isSelected,
    required this.onSelect,
  });

  final KoiCompanion companion;
  final bool isSelected;
  final VoidCallback onSelect;

  static const Color cyan = Color(0xFF06B6D4);
  static const Color idleTop = Color(0xFFF0F0F0);

  @override
  Widget build(BuildContext context) {
    // Name: text-2xl font-black uppercase italic. DM Sans italic is loaded
    // only at 300–400 on web; Flutter slants the 700 face here.
    final nameStyle = bodyText(
      24,
      weight: FontWeight.w700,
      height: 32 / 24,
    ).copyWith(fontStyle: FontStyle.italic);

    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        key: Key('companion-${companion.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onSelect,
        child: AnimatedContainer(
          // transition-all duration-300; translateY(-2px) when selected
          duration: const Duration(milliseconds: 300),
          transform: Matrix4.translationValues(0, isSelected ? -2 : 0, 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: KoiColors.neoWhite,
            border: Border.all(width: 3),
            borderRadius: BorderRadius.circular(32), // rounded-[32px]
            boxShadow: [
              isSelected
                  ? const BoxShadow(color: cyan, offset: Offset(6, 6))
                  : const BoxShadow(offset: Offset(4, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(32), // p-8
                decoration: BoxDecoration(
                  color: isSelected ? cyan : idleTop,
                  border: const Border(bottom: BorderSide(width: 3)),
                ),
                alignment: Alignment.center,
                child: Text(
                  companion.icon,
                  style: const TextStyle(fontSize: 60, height: 1),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24), // p-6
                child: Column(
                  children: [
                    Text(
                      companion.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: nameStyle,
                    ),
                    const SizedBox(height: 8), // mt-2
                    Text(
                      companion.trait,
                      textAlign: TextAlign.center,
                      style: bodyText(
                        16,
                        weight: FontWeight.w500,
                        color: const Color(0xFF6B7280),
                        height: 24 / 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `px-8 py-3 border-[3px] border-black rounded-full font-bold text-lg
/// shadow-[5px_5px_0px_0px_rgba(0,0,0,1)]`, background = companion colour,
/// white text; whileTap x/y 5px with no shadow.
class _ContinueButton extends StatefulWidget {
  const _ContinueButton({
    required this.color,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('companion-continue'),
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Transform.translate(
        offset: _pressed ? const Offset(5, 5) : Offset.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          decoration: BoxDecoration(
            color: widget.color,
            border: Border.all(width: 3),
            borderRadius: BorderRadius.circular(9999),
            boxShadow: _pressed
                ? const []
                : const [BoxShadow(offset: Offset(5, 5))],
          ),
          child: Text(
            widget.label,
            style: bodyText(
              18,
              weight: FontWeight.w700,
              color: KoiColors.neoWhite,
              height: 28 / 18,
            ),
          ),
        ),
      ),
    );
  }
}
