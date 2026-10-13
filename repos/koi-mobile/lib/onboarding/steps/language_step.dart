import 'package:flutter/material.dart';

import '../../theme/koi_colors.dart';
import '../../widgets/neo_button.dart';
import '../step_layout.dart';

@immutable
class LanguageOption {
  const LanguageOption(this.id, this.label, this.native, this.flag);
  final String id;
  final String label;
  final String native;
  final String flag;
}

/// Mirrors src/components/onboarding/LanguageStep.tsx.
class LanguageStep extends StatefulWidget {
  const LanguageStep({super.key, required this.onNext});
  final ValueChanged<String> onNext;

  static const List<LanguageOption> languages = [
    LanguageOption('en', 'English', 'English', '🇬🇧'),
    LanguageOption('ur', 'Urdu', 'اردو', '🇵🇰'),
  ];

  @override
  State<LanguageStep> createState() => _LanguageStepState();
}

class _LanguageStepState extends State<LanguageStep> {
  String _selected = 'en'; // useState<Language>('en')

  @override
  Widget build(BuildContext context) {
    return StepLayout(
      buttonGap: 24,
      button: NeoButton(
        key: const Key('language-next'),
        fullWidth: true,
        onPressed: () => widget.onNext(_selected),
        child: const Text('Continue →'),
      ),
      children: [
        const StepTitle('Select Language', bottom: 6),
        const StepSubtitle('Choose your preferred language.', bottom: 28),
        for (var i = 0; i < LanguageStep.languages.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _tile(LanguageStep.languages[i]),
        ],
      ],
    );
  }

  Widget _tile(LanguageOption lang) {
    final isSelected = _selected == lang.id;
    return OptionTile(
      key: Key('language-${lang.id}'),
      selected: isSelected,
      selectedColor: KoiColors.neoBlue,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      onTap: () => setState(() => _selected = lang.id),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(lang.flag, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 14), // gap 0.875rem
              Text(
                lang.label,
                style: displayText(
                  16,
                  color: isSelected ? KoiColors.neoWhite : KoiColors.neoBlack,
                ),
              ),
            ],
          ),
          Text(
            lang.native,
            style: bodyText(
              17.6,
              color: isSelected
                  ? const Color(0xBFFFFFFF) // rgba(255,255,255,0.75)
                  : const Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}
