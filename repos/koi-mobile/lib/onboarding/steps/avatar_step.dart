import 'package:flutter/material.dart';

import '../../theme/koi_colors.dart';
import '../../widgets/neo_button.dart';
import '../onboarding_service.dart';
import '../step_layout.dart';

@immutable
class AvatarOption {
  const AvatarOption(
    this.id,
    this.label,
    this.emoji,
    this.description,
    this.color,
  );
  final String id;
  final String label;
  final String emoji;
  final String description;
  final Color color;
}

/// Mirrors src/components/onboarding/AvatarStep.tsx.
///
/// Q7 (2026-10-13): the 'fox' option (Koi 🦊, neo-orange) is dropped on
/// mobile. NOTE: the web still shows it and should be updated.
/// The 3-column grid is kept as on web, so the two remaining tiles keep the
/// web tile size.
///
/// Q8: this step is currently unreachable, because AIDisclosureStep jumps
/// straight to Language exactly like the web (see onboarding_screen.dart).
class AvatarStep extends StatefulWidget {
  const AvatarStep({super.key, required this.onNext});
  final ValueChanged<String> onNext;

  static const List<AvatarOption> avatars = [
    AvatarOption(
      KoiAvatarId.femaleHuman,
      'Aisha',
      '👩',
      'Warm & caring',
      KoiColors.neoCoral,
    ),
    AvatarOption(
      KoiAvatarId.maleHuman,
      'Raza',
      '👨',
      'Calm & grounded',
      KoiColors.neoBlue,
    ),
  ];

  @override
  State<AvatarStep> createState() => _AvatarStepState();
}

class _AvatarStepState extends State<AvatarStep> {
  String? _selected; // useState<AvatarId | null>(null)

  @override
  Widget build(BuildContext context) {
    return StepLayout(
      buttonGap: 24, // marginTop: 1.5rem
      button: NeoButton(
        key: const Key('avatar-next'),
        fullWidth: true,
        onPressed: _selected == null ? null : () => widget.onNext(_selected!),
        child: const Text('Continue →'),
      ),
      children: [
        const StepTitle('Choose Your Avatar', bottom: 6),
        const StepSubtitle(
          'Pick the look that feels most like you',
          bottom: 28,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // gridTemplateColumns: repeat(3, 1fr); gap: 12px
            final cell = (constraints.maxWidth - 2 * 12) / 3;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < AvatarStep.avatars.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  SizedBox(width: cell, child: _tile(AvatarStep.avatars[i])),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _tile(AvatarOption a) {
    final isSelected = _selected == a.id;
    return OptionTile(
      key: Key('avatar-${a.id}'), // data-testid
      selected: isSelected,
      selectedColor: a.color,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      onTap: () => setState(() => _selected = a.id),
      child: Column(
        children: [
          Text(a.emoji, style: const TextStyle(fontSize: 40, height: 1)),
          const SizedBox(height: 8),
          Text(
            a.label,
            style: displayText(
              14,
              color: isSelected ? KoiColors.neoWhite : KoiColors.neoBlack,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            a.description,
            textAlign: TextAlign.center,
            style: bodyText(
              11.52,
              color: isSelected
                  ? const Color(0xCCFFFFFF) // rgba(255,255,255,0.8)
                  : const Color(0xFF888888),
            ),
          ),
        ],
      ),
    );
  }
}
