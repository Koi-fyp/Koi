import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_widgets.dart' show pushKoiPage;
import '../care/care_strings.dart';
import '../care/care_widgets.dart' show CareButtonLabel;
import '../onboarding/step_layout.dart';
import '../widgets/neo_button.dart';
import 'safety_plan_editor.dart';
import 'safety_plan_view.dart' show SafetyPlanFootnote;

/// Mobile-only onboarding sub-screen between Companion and AI Disclosure
/// (decision 2026-10-20, option B): not a counted step, so the progress
/// dots and the Web step numbers stay as they are.
///
/// Entirely optional. "Not now" goes on at once; "Create" opens the
/// editor, and leaving the editor in any way (saved, nothing written, or a
/// failed save) also goes on. Nothing here can block onboarding.
class SafetyPlanOnboardingStep extends ConsumerWidget {
  const SafetyPlanOnboardingStep({super.key, required this.onNext});

  final VoidCallback onNext;

  Future<void> _create(BuildContext context) async {
    var advanced = false;
    void next() {
      if (advanced) return;
      advanced = true;
      onNext();
    }

    await pushKoiPage<void>(
      context,
      Builder(
        builder: (editorContext) => SafetyPlanEditor(
          onDone: () {
            Navigator.of(editorContext).pop();
            next();
          },
        ),
      ),
    );
    // Also when the route went away some other way.
    next();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(careStringsProvider);
    return Directionality(
      textDirection: s.direction,
      child: StepLayout(
        buttonGap: 16,
        button: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            NeoButton(
              key: const Key('sp-onboarding-create'),
              fullWidth: true,
              onPressed: () => _create(context),
              child: CareButtonLabel(s.t(CareText.spCreate)),
            ),
            const SizedBox(height: 12),
            NeoButton(
              key: const Key('sp-onboarding-skip'),
              variant: NeoButtonVariant.ghost,
              fullWidth: true,
              onPressed: onNext,
              child: CareButtonLabel(s.t(CareText.spNotNow)),
            ),
          ],
        ),
        children: [
          StepTitle(s.t(CareText.spOnboardingTitle), bottom: 12),
          StepSubtitle(s.t(CareText.spOnboardingBody), bottom: 8),
          StepSubtitle(s.t(CareText.spPrivacy), bottom: 0),
          SafetyPlanFootnote(strings: s),
        ],
      ),
    );
  }
}
