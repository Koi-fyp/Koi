import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account/account_widgets.dart'
    show KoiBackButton, koiMinTouch, pushKoiPage;
import '../care/care_strings.dart';
import '../care/care_widgets.dart' show CareButtonLabel;
import '../checkins/local_breathing.dart';
import '../onboarding/steps/ai_disclosure_step.dart' show UrlOpener;
import '../safety/breathing_screen.dart';
import '../safety/crisis_screen.dart';
import '../safety/safety_contract.dart' show Helpline;
import '../theme/koi_text.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_button.dart';
import 'safety_plan_editor.dart';
import 'safety_plan_models.dart';
import 'safety_plan_providers.dart';
import 'text_direction.dart';

Future<void> _launch(Uri uri) async {
  // As in crisis_screen.dart: launchUrl directly, no canLaunchUrl.
  await launchUrl(uri);
}

/// The section heading and helper line in the table.
// NEEDS CLINICIAN REVIEW (the texts live in care_strings.dart).
CareText sectionTitle(SafetyPlanSection s) => switch (s) {
  SafetyPlanSection.warningSigns => CareText.spWarningSigns,
  SafetyPlanSection.copingAlone => CareText.spCopingAlone,
  SafetyPlanSection.distractions => CareText.spDistractions,
  SafetyPlanSection.peopleToAsk => CareText.spPeopleToAsk,
  SafetyPlanSection.professionals => CareText.spProfessionals,
  SafetyPlanSection.saferSurroundings => CareText.spSaferSurroundings,
  SafetyPlanSection.reasons => CareText.spReasons,
};

CareText sectionHelp(SafetyPlanSection s) => switch (s) {
  SafetyPlanSection.warningSigns => CareText.spWarningSignsHelp,
  SafetyPlanSection.copingAlone => CareText.spCopingAloneHelp,
  SafetyPlanSection.distractions => CareText.spDistractionsHelp,
  SafetyPlanSection.peopleToAsk => CareText.spPeopleToAskHelp,
  SafetyPlanSection.professionals => CareText.spProfessionalsHelp,
  SafetyPlanSection.saferSurroundings => CareText.spSaferSurroundingsHelp,
  SafetyPlanSection.reasons => CareText.spReasonsHelp,
};

/// The calm colours of the plan: the crisis dialog's warm white and text,
/// the breathing screen's teal-grey (CompanionScene.module.css literals).
abstract final class SafetyPlanColors {
  static const Color background = CrisisScreen.dialogBg;
  static const Color text = CrisisScreen.textColor;
  static const Color muted = CrisisScreen.sourceColor;
  static const Color accent = BreathingScreen.progressFill;
  static const Color card = BreathingScreen.progressTrack;
}

/// The plan's text styles: large, calm, Urdu with the taller line.
TextStyle planText(
  CareStrings s, {
  double size = 18,
  FontWeight weight = FontWeight.w400,
  Color color = SafetyPlanColors.text,
}) => KoiText.body(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: s.lineHeight,
  letterSpacing: 0,
);

TextStyle planHeading(CareStrings s, [double size = 20]) => KoiText.display(
  fontSize: size,
  fontWeight: FontWeight.w700,
  color: SafetyPlanColors.text,
  height: s.isUrdu ? 1.7 : 1.3,
  letterSpacing: 0,
);

/// Small print under every plan screen.
class SafetyPlanFootnote extends StatelessWidget {
  const SafetyPlanFootnote({super.key, required this.strings});
  final CareStrings strings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Text(
      strings.t(CareText.spFootnote),
      key: const Key('sp-footnote'),
      style: planText(strings, size: 13, color: SafetyPlanColors.muted),
    ),
  );
}

/// The read view: calm, large text; every phone number can be tapped to
/// call. 1166 is always the first helpline and cannot be removed.
///
/// [fromCrisis]: opened over the crisis screen. Read only (no Edit), and no
/// breathing link (breathing never runs while the crisis flow is open).
/// Nothing here touches the crisis state: Back simply returns to it.
class SafetyPlanView extends ConsumerWidget {
  const SafetyPlanView({
    super.key,
    this.fromCrisis = false,
    this.openUrl = _launch,
  });

  final bool fromCrisis;

  /// Opens `tel:` links. Injectable for tests.
  final UrlOpener openUrl;

  static const Helpline helpline = Helpline.defaultHelpline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(careStringsProvider);
    final uid = ref.watch(safetyPlanUidProvider);
    final c = uid == null ? null : ref.watch(safetyPlanControllerProvider(uid));
    final plan = c?.plan;
    return Directionality(
      textDirection: s.direction,
      child: Scaffold(
        backgroundColor: SafetyPlanColors.background,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: KoiBackButton(label: s.t(CareText.back)),
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(s.t(CareText.spTitle), style: planHeading(s, 28)),
                ),
                const SizedBox(height: 8),
                Text(
                  s.t(CareText.spPrivacy),
                  style: planText(s, size: 14, color: SafetyPlanColors.muted),
                ),
                const SizedBox(height: 16),
                if (c == null || c.loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: KoiLoader(label: s.t(CareText.spLoading)),
                  )
                else ...[
                  if (c.unreadable)
                    Text(
                      s.t(CareText.spLoadError),
                      key: const Key('sp-view-unavailable'),
                      style: planText(s),
                    ),
                  for (final section in SafetyPlanSection.values)
                    if (section == SafetyPlanSection.professionals ||
                        (plan?[section].isNotEmpty ?? false))
                      _section(context, ref, s, section, plan),
                  if (!fromCrisis) ...[
                    const SizedBox(height: 8),
                    Text(s.t(CareText.spAddMore), style: planText(s, size: 15)),
                    const SizedBox(height: 12),
                    NeoButton(
                      key: const Key('sp-edit'),
                      variant: NeoButtonVariant.secondary,
                      fullWidth: true,
                      onPressed: () =>
                          pushKoiPage<void>(context, const SafetyPlanEditor()),
                      child: CareButtonLabel(s.t(CareText.spEditPlan)),
                    ),
                  ],
                ],
                SafetyPlanFootnote(strings: s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    WidgetRef ref,
    CareStrings s,
    SafetyPlanSection section,
    SafetyPlan? plan,
  ) {
    final items = plan?[section] ?? const <SafetyPlanItem>[];
    return Padding(
      key: Key('sp-view-${section.id}'),
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SafetyPlanColors.card,
          borderRadius: BorderRadius.circular(14),
          border: const BorderDirectional(
            start: BorderSide(color: SafetyPlanColors.accent, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(s.t(sectionTitle(section)), style: planHeading(s)),
              ),
              const SizedBox(height: 8),
              if (section == SafetyPlanSection.professionals)
                _callRow(
                  s,
                  key: const Key('sp-helpline'),
                  text: helpline.name,
                  phone: helpline.number,
                ),
              for (final item in items)
                item.phone == null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          item.text,
                          key: Key('sp-item-${item.id}'),
                          textDirection: userTextDirection(item.text),
                          style: planText(s),
                        ),
                      )
                    : _callRow(
                        s,
                        key: Key('sp-item-${item.id}'),
                        text: item.text,
                        phone: item.phone!,
                      ),
              if (section == SafetyPlanSection.copingAlone && !fromCrisis)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: NeoButton(
                    key: const Key('sp-breathing'),
                    variant: NeoButtonVariant.ghost,
                    fullWidth: true,
                    onPressed: () => openLocalBreathing(context, ref),
                    child: CareButtonLabel(s.t(CareText.spBreathing)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _callRow(
    CareStrings s, {
    required Key key,
    required String text,
    required String phone,
  }) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Semantics(
      button: true,
      label: '${s.t(CareText.spCallLabel)} $text, $phone',
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          onTap: () => openUrl(CrisisScreen.telUri(phone)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: koiMinTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.call,
                    color: SafetyPlanColors.accent,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text,
                          textDirection: userTextDirection(text),
                          style: planText(s),
                        ),
                        Text(
                          phone,
                          textDirection: TextDirection.ltr,
                          style: planText(s, size: 16, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Settings → "My safety plan": the read view when a plan is stored, the
/// editor when there is none yet. Decided once, after the first load, so
/// writing the first line does not swap the editor away.
class SafetyPlanEntry extends ConsumerStatefulWidget {
  const SafetyPlanEntry({super.key});

  @override
  ConsumerState<SafetyPlanEntry> createState() => _SafetyPlanEntryState();
}

class _SafetyPlanEntryState extends ConsumerState<SafetyPlanEntry> {
  bool? _view;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(safetyPlanUidProvider);
    final c = uid == null ? null : ref.watch(safetyPlanControllerProvider(uid));
    if (_view == null && c != null && !c.loading) {
      _view = c.hasPlan || c.unreadable;
    }
    return switch (_view) {
      true => const SafetyPlanView(),
      false => const SafetyPlanEditor(),
      null => Scaffold(
        backgroundColor: SafetyPlanColors.background,
        body: Center(
          child: KoiLoader(
            label: ref.watch(careStringsProvider).t(CareText.spLoading),
          ),
        ),
      ),
    };
  }
}
