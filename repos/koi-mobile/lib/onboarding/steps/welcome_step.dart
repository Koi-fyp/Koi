import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/koi_colors.dart';
import '../../theme/koi_motion.dart';
import '../../theme/koi_shadows.dart';
import '../step_layout.dart';

/// Mirrors src/components/onboarding/WelcomeStep.tsx: auto-advances after
/// 2200ms, or on tap anywhere.
class WelcomeStep extends StatefulWidget {
  const WelcomeStep({super.key, required this.onNext});
  final VoidCallback onNext;

  static const Duration autoAdvance = Duration(milliseconds: 2200);
  static const String tagline = 'Your companion in moments of loneliness';
  static const String tapToContinue = 'Tap to continue';

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(WelcomeStep.autoAdvance, widget.onNext); // setTimeout
  }

  @override
  void dispose() {
    _timer.cancel(); // clearTimeout on unmount
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Continue', // aria-label="Continue"
      child: GestureDetector(
        key: const Key('welcome-step'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onNext,
        child: Container(
          color: KoiColors.background, // background: #ffe5d9
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
          alignment: Alignment.center,
          // animation: fadeUp 0.5s ease both
          child: KoiFadeUp(
            spec: const KoiAnimationSpec(duration: Duration(milliseconds: 500)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: KoiColors.neoBlue,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(width: 3),
                    boxShadow: KoiShadows.hard(6),
                  ),
                  child: Text(
                    'K',
                    style: displayText(
                      40,
                      weight: FontWeight.w800,
                      color: KoiColors.neoWhite,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 32), // marginBottom: 2rem
                Text(
                  'KOI',
                  style: displayText(
                    48,
                    weight: FontWeight.w800,
                    letterSpacing: -0.04 * 48,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 16), // marginBottom: 1rem
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    WelcomeStep.tagline,
                    textAlign: TextAlign.center,
                    style: bodyText(
                      17.6, // 1.1rem
                      color: const Color(0xFF666666),
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 48), // marginBottom: 3rem
                Text(
                  WelcomeStep.tapToContinue.toUpperCase(), // textTransform
                  style: bodyText(
                    12.48, // 0.78rem
                    weight: FontWeight.w500,
                    color: const Color(0xFFCCCCCC),
                    letterSpacing: 0.1 * 12.48,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
