import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_widgets.dart';
import '../questionnaires/questionnaire_models.dart';
import '../questionnaires/questionnaire_providers.dart';
import '../questionnaires/questionnaire_screens.dart';
import '../shell/nav_icons.dart';
import '../theme/koi_colors.dart';
import '../widgets/neo_card.dart';
import 'care_strings.dart';
import 'care_widgets.dart';

// MOB-5 Care hub pieces (Care Home for General, My Care for Patient). The
// web's sidebar workspace (WorkspaceFrame.tsx, PatientWorkspace.tsx on
// origin/feat/koi2-ui-overhaul f9ed940) becomes one scrolling hub with
// pushed detail screens. Which hub shows is decided by the confirmed
// capabilities only (care_screen.dart); these widgets decide nothing.

/// "General User" / "Patient" under the hub title (the web's
/// "General User Dashboard" / "Patient Dashboard" workspace label).
class CareRoleChip extends StatelessWidget {
  const CareRoleChip({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: CareChip(key: const Key('care-role-chip'), label: label),
    ),
  );
}

/// The top card of a hub: "Start your care journey" / "Your care is
/// active", with its primary actions (full width, 48dp+, wrapping labels).
class CareHeroCard extends StatelessWidget {
  const CareHeroCard({
    super.key,
    required this.strings,
    required this.title,
    required this.body,
    required this.actions,
    this.eyebrow,
  });

  final CareStrings strings;
  final String title;
  final String? eyebrow;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: NeoCard(
        variant: NeoCardVariant.yellow,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: careBody(s, size: 18, weight: FontWeight.w700),
              ),
            ),
            if (eyebrow != null) ...[
              const SizedBox(height: 6),
              Text(eyebrow!, style: careMuted(s)),
            ],
            const SizedBox(height: 4),
            Text(body, style: careBody(s)),
            const SizedBox(height: 14),
            for (final (i, a) in actions.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              a,
            ],
          ],
        ),
      ),
    );
  }
}

/// My Care: the assigned questionnaires at a glance (PatientWorkspace.tsx
/// "Your questionnaires"): how many still need completing and the first
/// three titles. Titles and states only: never a score, evaluation, review
/// or job state. Opens the questionnaire list.
class MyCareQuestionnairesCard extends ConsumerWidget {
  const MyCareQuestionnairesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(careStringsProvider);
    final lang = s.isUrdu ? 'ur' : 'en';
    final list = ref.watch(assignmentsProvider);
    final items = list.valueOrNull;
    final line = list.isLoading && items == null
        ? s.t(CareText.qLoadingList)
        : items == null
        ? s.t(CareText.questionnairesSub)
        : items.isEmpty
        ? s.t(CareText.m5QEmpty)
        : s.awaitingCount(
            items.where((a) => a.state != AssignmentState.submitted).length,
          );
    final titles = [
      for (final a in (items ?? const []).take(3)) a.titleFor(lang),
    ];
    final title = s.t(CareText.questionnaires);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        button: true,
        label: [title, line, ...titles].join('. '),
        excludeSemantics: true,
        child: GestureDetector(
          key: const Key('care-questionnaires'),
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            await pushKoiPage<void>(context, const QuestionnaireListScreen());
            ref.invalidate(assignmentsProvider);
          },
          child: NeoCard(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: koiMinTouch),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: careBody(
                            s,
                            size: 16.5,
                            weight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          line,
                          key: const Key('care-questionnaires-line'),
                          style: careMuted(s),
                        ),
                        for (final t in titles)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '• $t',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: careBody(s, size: 14),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text('›', style: koiTitleStyle(24), semanticsLabel: ''),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// My Care: "Additional care options" (the web's collapsed sidebar
/// section): Find a Psychologist, My Applications, invitation, Become a
/// Psychologist. Collapsed by default.
class MoreCareOptions extends StatefulWidget {
  const MoreCareOptions({
    super.key,
    required this.strings,
    required this.children,
  });

  final CareStrings strings;
  final List<Widget> children;

  @override
  State<MoreCareOptions> createState() => _MoreCareOptionsState();
}

class _MoreCareOptionsState extends State<MoreCareOptions> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final title = s.t(CareText.m5MoreOptions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: title,
          excludeSemantics: true,
          child: GestureDetector(
            key: const Key('care-more-options'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: koiMinTouch),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: careBody(s, size: 15.5, weight: FontWeight.w700),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const KoiNavIcon(
                      KoiNavGlyph.chevronDown,
                      color: KoiColors.neoBlack,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_open) ...widget.children,
      ],
    );
  }
}
