import 'package:flutter/material.dart';

import '../theme/koi_colors.dart';

/// Mirrors src/components/onboarding/ProgressIndicator.tsx: a white bar with
/// a 2px black bottom border, padding 10px 20px, segments 6px apart. Each
/// segment is 4px tall, radius 2px, 1px black border; the active one has
/// flex 2, the others flex 1; done/active segments are neo-blue (done at
/// opacity 0.55), the rest #E5E5E5; `transition: flex 0.3s ease,
/// background 0.3s ease`.
class OnboardingProgressIndicator extends StatelessWidget {
  const OnboardingProgressIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  static const double gap = 6;
  static const Color idle = Color(0xFFE5E5E5);
  static const Duration transition = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KoiColors.neoWhite,
        border: Border(bottom: BorderSide(width: 2)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth - gap * (totalSteps - 1);
          // Exactly one segment is active (flex 2), so total flex is
          // totalSteps + 1 whenever currentStep is in range.
          final flexSum = List.generate(
            totalSteps,
            (i) => i == currentStep ? 2 : 1,
          ).fold<int>(0, (a, b) => a + b);
          return Row(
            children: [
              for (var i = 0; i < totalSteps; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Opacity(
                  opacity: i < currentStep ? 0.55 : 1,
                  child: AnimatedContainer(
                    key: Key('progress-segment-$i'),
                    duration: transition,
                    curve: Curves.ease,
                    width: available * (i == currentStep ? 2 : 1) / flexSum,
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= currentStep ? KoiColors.neoBlue : idle,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(width: 1),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
