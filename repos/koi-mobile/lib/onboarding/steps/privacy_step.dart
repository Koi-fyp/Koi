import 'package:flutter/material.dart';

import '../../theme/koi_colors.dart';
import '../../widgets/neo_button.dart';
import '../../widgets/neo_card.dart';
import '../step_layout.dart';

/// Mirrors src/components/onboarding/PrivacyStep.tsx.
class PrivacyStep extends StatelessWidget {
  const PrivacyStep({super.key, required this.onNext});
  final VoidCallback onNext;

  static const List<String> stored = [
    'Anonymous session ID (no name required)',
    'Your conversations (encrypted, on your device)',
    'Check-in mood responses',
    'Your avatar and language preference',
  ];

  static const List<String> notStored = [
    'Your real name or contact details',
    'Location data',
    'Conversations shared with third parties',
    'Any data sold to advertisers',
  ];

  @override
  Widget build(BuildContext context) {
    return StepLayout(
      contentBottomPadding: 16,
      buttonGap: 16, // style={{ marginTop: '1rem' }}
      button: NeoButton(
        key: const Key('privacy-next'),
        fullWidth: true,
        onPressed: onNext,
        child: const Text('I Understand →'),
      ),
      children: [
        const StepTitle('Privacy Matters', bottom: 6),
        const StepSubtitle(
          "Here's what you should know about your data.",
          bottom: 24,
        ),
        const _ListCard(
          title: 'What we store',
          color: KoiColors.neoMint,
          mark: '✓',
          items: stored,
        ),
        const SizedBox(height: 16), // mb-4
        const _ListCard(
          title: 'What we never store',
          color: KoiColors.neoCoral,
          mark: '✗',
          items: notStored,
        ),
      ],
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.color,
    required this.mark,
    required this.items,
  });

  final String title;
  final Color color;
  final String mark;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: NeoCard(
        padding: const EdgeInsets.all(16), // p-4
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // h3: display 700 0.875rem, marginBottom 0.875rem, gap 0.5rem
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(title, style: displayText(14)),
              ],
            ),
            const SizedBox(height: 14),
            // ul: gap 0.5rem; li: body 0.875rem #444, gap 0.625rem
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1), // marginTop: 1px
                    child: Text(
                      mark,
                      style: bodyText(
                        14,
                        weight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      items[i],
                      style: bodyText(14, color: const Color(0xFF444444)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
