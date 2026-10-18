import 'package:flutter/material.dart';

import '../../theme/koi_colors.dart';
import '../step_layout.dart';

/// One entry of `companions` in CompanionSelectionStep.tsx (or the Settings
/// AvatarPicker.tsx). Onboarding cards show [image] (null for Koi: "Fox
/// preview unavailable"); the Settings picker shows [icon].
@immutable
class KoiCompanion {
  const KoiCompanion(
    this.id,
    this.name,
    this.trait,
    this.color, {
    this.icon,
    this.image,
  });
  final String id;
  final String name;
  final String trait;
  final Color color;
  final String? icon;
  final String? image;
}

/// Mirrors src/components/onboarding/CompanionSelectionStep.tsx
/// (feat/avatar-webview-host 223e97c) at phone width (grid-cols-1 below the
/// md breakpoint).
///
/// Tailwind: 1 unit = 4px; v3.4.19 defaults text-3xl 1.875rem/2.25rem,
/// text-2xl 1.5rem/2rem, text-lg 1.125rem/1.75rem, text-6xl 3.75rem/1,
/// text-5xl 3rem/1, text-sm 0.875rem/1.25rem, gray-600 #4b5563,
/// gray-500 #6b7280. Text without a font class inherits body DM Sans, whose
/// heaviest loaded weight is 700 (font-black → 700).
class CompanionSelectionStep extends StatefulWidget {
  const CompanionSelectionStep({
    super.key,
    required this.onNext,
    this.initialSelection = 'raza', // initialSelection = 'raza' (:59)
  });
  final ValueChanged<String> onNext;
  final String initialSelection;

  /// CompanionSelectionStep.tsx:7-11.
  static const List<KoiCompanion> companions = [
    KoiCompanion(
      'aisha',
      'Aisha',
      'Warm & caring · Female avatar',
      Color(0xFFFF4A60),
      image: 'assets/images/Female.png',
    ),
    KoiCompanion(
      'raza',
      'Raza',
      'Calm & grounded · Male avatar',
      Color(0xFFFFC224),
      image: 'assets/images/Male.png',
    ),
    KoiCompanion(
      'koi',
      'Koi',
      'Playful & curious · Fox choice',
      Color(0xFF06B6D4),
    ),
  ];

  @override
  State<CompanionSelectionStep> createState() => _CompanionSelectionStepState();
}

class _CompanionSelectionStepState extends State<CompanionSelectionStep> {
  late String _selected = widget.initialSelection;

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
                // CompanionSelectionStep.tsx:69
                'Choose your companion and matching avatar. Aisha uses the '
                'female model, Raza the male model, and Koi keeps the fox '
                'choice.',
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
                CompanionCard(
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

/// CompanionCard from CompanionSelectionStep.tsx:24-57. The Settings
/// AvatarPicker (settings/components/AvatarPicker.tsx:26-70) has its own
/// copy with the same classes and styles but an emoji instead of the
/// preview, so both screens use this widget ([KoiCompanion.icon]).
class CompanionCard extends StatelessWidget {
  const CompanionCard({
    super.key,
    required this.companion,
    required this.isSelected,
    required this.onSelect,
    this.keyPrefix = 'companion',
  });

  final KoiCompanion companion;
  final bool isSelected;
  final VoidCallback onSelect;

  /// Tap target key is '$keyPrefix-' + the companion id.
  final String keyPrefix;

  static const Color cyan = Color(0xFF06B6D4);
  static const Color idleTop = Color(0xFFF0F0F0);

  /// h-[118px] (CompanionSelectionStep.tsx:45-46).
  static const double previewHeight = 118;

  /// CompanionSelectionStep.tsx:45-48: the avatar image, a status line if
  /// it fails to load, or the fox placeholder for Koi. The Settings picker
  /// shows its emoji (AvatarPicker.tsx:55-57, text-6xl).
  Widget _preview() {
    final icon = companion.icon;
    if (icon != null) {
      return Text(icon, style: const TextStyle(fontSize: 60, height: 1));
    }
    final image = companion.image;
    if (image != null) {
      return SizedBox(
        height: previewHeight,
        child: Image.asset(
          image,
          key: Key('companion-preview-${companion.id}'),
          semanticLabel: '${companion.name} avatar preview',
          fit: BoxFit.contain,
          errorBuilder: (context, _, _) => Center(
            child: Semantics(
              liveRegion: true, // role="status"
              child: Text(
                '${companion.name} preview unavailable. You can still '
                'select this companion.',
                textAlign: TextAlign.center,
                style: bodyText(16, height: 24 / 16),
              ),
            ),
          ),
        ),
      );
    }
    // flex h-[118px] flex-col items-center justify-center gap-2 text-5xl,
    // aria-label "Fox avatar preview unavailable"; the label is text-sm
    // font-semibold.
    return Semantics(
      key: const Key('companion-preview-fox'),
      label: 'Fox avatar preview unavailable',
      excludeSemantics: true,
      child: SizedBox(
        height: previewHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🦊', style: TextStyle(fontSize: 48, height: 1)),
            const SizedBox(height: 8),
            Text(
              'Fox preview unavailable',
              style: bodyText(14, weight: FontWeight.w600, height: 20 / 14),
            ),
          ],
        ),
      ),
    );
  }

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
        key: Key('$keyPrefix-${companion.id}'),
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
                child: _preview(),
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
