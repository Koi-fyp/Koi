import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_widgets.dart';
import '../account/capability_gate.dart';
import '../account/destinations.dart';
import '../app/providers.dart';
import '../care/care_api_support.dart' show careFailureText;
import '../care/care_strings.dart';
import '../care/care_widgets.dart' show CareButtonLabel, showReauthSheet;
import '../platform/demo_badge.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_motion.dart';
import '../theme/koi_radii.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';
import 'asset_manifest.dart';
import 'attempt_controller.dart';
import 'question_view.dart';
import 'questionnaire_models.dart';
import 'questionnaire_providers.dart';

String assignmentStateLabel(CareStrings s, AssignmentState state) =>
    s.t(switch (state) {
      AssignmentState.assigned => CareText.qStateAssigned,
      AssignmentState.inProgress => CareText.qStateInProgress,
      AssignmentState.submitted => CareText.qStateSubmitted,
    });

/// The patient's assigned questionnaires.
class QuestionnaireListScreen extends StatelessWidget {
  const QuestionnaireListScreen({super.key});

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.questionnaires,
    builder: (_) => const _QuestionnaireList(),
  );
}

class _QuestionnaireList extends ConsumerWidget {
  const _QuestionnaireList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(careStringsProvider);
    final list = ref.watch(assignmentsProvider);
    final demo = ref.watch(questionnaireApiProvider).isMock;
    final lang = s.isUrdu ? 'ur' : 'en';
    return Directionality(
      textDirection: s.direction,
      child: KoiPage(
        back: true,
        demo: demo,
        title: s.t(CareText.questionnaires),
        children: list.when(
          loading: () => [NeoSkeletonList(label: s.t(CareText.qLoadingList))],
          error: (e, _) => [
            KoiNoticeCard(
              message: careFailureText(s, e),
              action: () => ref.invalidate(assignmentsProvider),
              actionLabel: s.t(CareText.retry),
            ),
          ],
          data: (items) => items.isEmpty
              ? [KoiNoticeCard(message: s.t(CareText.qNothing))]
              : [
                  for (final a in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                        button: true,
                        label:
                            '${a.titleFor(lang)}. '
                            '${assignmentStateLabel(s, a.state)}',
                        excludeSemantics: true,
                        child: GestureDetector(
                          key: Key('assignment-${a.assignmentId}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            await pushKoiPage<void>(
                              context,
                              QuestionnaireRunnerScreen(assignment: a),
                            );
                            ref.invalidate(assignmentsProvider);
                          },
                          child: NeoCard(
                            padding: const EdgeInsets.all(16),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: koiMinTouch,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.titleFor(lang),
                                    style: koiBodyStyle(
                                      size: 17,
                                      weight: FontWeight.w700,
                                    ).copyWith(height: s.lineHeight),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    assignmentStateLabel(s, a.state),
                                    style: koiMutedStyle().copyWith(
                                      height: s.lineHeight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
        ),
      ),
    );
  }
}

/// Load → answer → check answers → submit → "Response submitted".
class QuestionnaireRunnerScreen extends ConsumerWidget {
  const QuestionnaireRunnerScreen({super.key, required this.assignment});

  final Assignment assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CapabilityGate(
    destination: KoiDestination.questionnaire,
    builder: (_) {
      final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
      if (uid == null) return const SizedBox.shrink();
      return _Runner(attemptRef: AttemptRef(uid, assignment));
    },
  );
}

class _Runner extends ConsumerStatefulWidget {
  const _Runner({required this.attemptRef});
  final AttemptRef attemptRef;

  @override
  ConsumerState<_Runner> createState() => _RunnerState();
}

class _RunnerState extends ConsumerState<_Runner> {
  bool _summary = false;

  /// The language the patient picked with the chips (null = the default:
  /// app language, else English, else the first published locale).
  QuestionnaireLanguage? _picked;

  QuestionnaireLanguage _language(PublishedQuestionnaire v, CareStrings s) {
    final picked = _picked;
    if (picked != null && v.locales.contains(picked)) return picked;
    return v.defaultLanguage(s.isUrdu ? 'ur' : 'en');
  }

  AttemptController get _c =>
      ref.read(attemptControllerProvider(widget.attemptRef));

  CareStrings get _s => ref.read(careStringsProvider);

  Future<void> _confirmRestart() async {
    final s = _s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: s.direction,
        child: _ConfirmDialog(
          title: s.t(CareText.qRestartTitle),
          message: s.t(CareText.qRestartBody),
          confirm: s.t(CareText.qStartAgain),
          cancel: s.t(CareText.qCancel),
          strings: s,
        ),
      ),
    );
    if (ok != true || !mounted) return;
    // Refused (submitted elsewhere / conflict) shows as the controller's
    // locked or conflict state.
    await _c.restart();
    if (mounted) setState(() => _summary = false);
  }

  Future<void> _submit() async {
    var ok = await _c.submit();
    if (!ok && mounted && _c.submitProblem == SubmitProblem.reauth) {
      // Recent sign-in needed: ask for the password, then submit again
      // with the SAME idempotency key (kept by the controller).
      if (await showReauthSheet(context, ref)) ok = await _c.submit();
    }
    if (!ok && mounted && _c.submitProblem == SubmitProblem.incomplete) {
      setState(() => _summary = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(attemptControllerProvider(widget.attemptRef));
    final s = ref.watch(careStringsProvider);
    final demo = ref.watch(questionnaireApiProvider).isMock;
    final manifest =
        ref.watch(questionnaireAssetManifestProvider).valueOrNull ??
        QuestionnaireAssetManifest.empty;
    final reduce = koiReduceMotion(context);
    final Widget page = switch (c.phase) {
      AttemptPhase.loading => Scaffold(
        key: const ValueKey('loading'),
        body: KoiLoadingPage(label: s.t(CareText.qLoading)),
      ),
      AttemptPhase.submitting => Scaffold(
        key: const ValueKey('submitting'),
        body: KoiLoadingPage(label: s.t(CareText.qSubmitting)),
      ),
      AttemptPhase.unavailable => Directionality(
        key: const ValueKey('unavailable'),
        textDirection: s.direction,
        child: KoiPage(
          back: true,
          demo: demo,
          children: [
            KoiNoticeCard(
              message: _loadErrorText(s, c.loadError),
              action: c.load,
              actionLabel: s.t(CareText.retry),
            ),
          ],
        ),
      ),
      AttemptPhase.submitted => AcknowledgementView(
        key: const ValueKey('submitted'),
        submittedAt: c.submittedAt,
        demo: demo,
        strings: s,
      ),
      AttemptPhase.answering => Directionality(
        key: ValueKey(_summary ? 'summary' : 'question'),
        textDirection: _language(c.questionnaire!, s).direction,
        child: _summary
            ? _summaryPage(c, s, demo, manifest)
            : _questionPage(c, s, demo, manifest),
      ),
    };
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : KoiMotion.fadeUp.duration,
      switchInCurve: Curves.ease,
      child: page,
    );
  }

  static String _loadErrorText(CareStrings s, AttemptLoadError? e) =>
      switch (e) {
        AttemptLoadError.offline => s.t(CareText.qOfflineOpen),
        AttemptLoadError.notFound => s.t(CareText.qGone),
        AttemptLoadError.forbidden => CapabilityGate.deniedText,
        AttemptLoadError.unsupported => s.t(CareText.qUnsupported),
        _ => s.t(CareText.genericError),
      };

  Widget _header(AttemptController c, CareStrings s, bool demo) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        const KoiBackButton(),
        const SizedBox(width: 8),
        // Flexible: the Urdu status + Demo badge fit at 320 dp (MOB-6).
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SaveIndicator(status: c.saveStatus, strings: s),
          ),
        ),
        if (demo) ...[const SizedBox(width: 8), const DemoDataBadge()],
      ],
    ),
  );

  Widget _scaffold(List<Widget> children) => Scaffold(
    backgroundColor: KoiColors.background,
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );

  Widget _label(String text, CareStrings s) => CareButtonLabel(text);

  Widget _conflictBanner(AttemptController c, CareStrings s) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: NeoCard(
      key: const Key('conflict-banner'),
      variant: NeoCardVariant.yellow,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.t(CareText.qConflictTitle),
            style: koiBodyStyle(weight: FontWeight.w700)
                .copyWith(height: s.lineHeight),
          ),
          const SizedBox(height: 6),
          Text(
            s.t(CareText.qConflictBody),
            style: koiBodyStyle(size: 14).copyWith(height: s.lineHeight),
          ),
          const SizedBox(height: 12),
          NeoButton(
            key: const Key('conflict-use-server'),
            variant: NeoButtonVariant.ghost,
            onPressed: c.resolveUseServer,
            child: _label(s.t(CareText.qUseServer), s),
          ),
          const SizedBox(height: 10),
          NeoButton(
            key: const Key('conflict-keep-mine'),
            variant: NeoButtonVariant.ghost,
            onPressed: c.resolveKeepMine,
            child: _label(s.t(CareText.qKeepMine), s),
          ),
        ],
      ),
    ),
  );

  Widget _questionPage(
    AttemptController c,
    CareStrings s,
    bool demo,
    QuestionnaireAssetManifest manifest,
  ) {
    final v = c.questionnaire!;
    final lang = _language(v, s);
    final q = v.questions[c.index];
    final last = c.index == v.questions.length - 1;
    final showMissing =
        c.submitProblem == SubmitProblem.incomplete && c.missing.contains(q.id);
    return _scaffold([
      _header(c, s, demo),
      Text(
        v.title.resolve(lang),
        key: const Key('questionnaire-title'),
        style: questionnaireTextStyle(lang, size: 22, weight: FontWeight.w700),
      ),
      if (v.locales.length > 1) ...[
        const SizedBox(height: 12),
        QuestionnaireLanguageChips(
          locales: v.locales,
          selected: lang,
          strings: s,
          onSelected: (l) => setState(() => _picked = l),
        ),
      ],
      const SizedBox(height: 16),
      QuestionnaireProgress(
        index: c.index,
        total: v.questions.length,
        strings: s,
      ),
      const SizedBox(height: 20),
      if (c.saveStatus == SaveStatus.conflict) _conflictBanner(c, s),
      QuestionView(
        key: ValueKey('qv-${q.id}'),
        question: q,
        language: lang,
        answer: c.answers[q.id],
        enabled: c.saveStatus != SaveStatus.conflict,
        manifest: manifest,
        strings: s,
        onChanged: (a) => c.setAnswer(q.id, a),
      ),
      if (showMissing) ...[
        const SizedBox(height: 8),
        KoiErrorText(s.t(CareText.qPleaseAnswer)),
      ],
      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(
            child: NeoButton(
              key: const Key('q-previous'),
              variant: NeoButtonVariant.ghost,
              fullWidth: true,
              customPadding: const EdgeInsets.symmetric(vertical: 14),
              onPressed: c.index == 0 ? null : () => c.goTo(c.index - 1),
              child: _label(s.t(CareText.qPrevious), s),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: NeoButton(
              key: const Key('q-next'),
              fullWidth: true,
              customPadding: const EdgeInsets.symmetric(vertical: 14),
              onPressed: () {
                if (!questionComplete(q, c.answers[q.id])) {
                  c.markUnanswered(q.id);
                  return;
                }
                if (last) {
                  setState(() => _summary = true);
                } else {
                  c.goTo(c.index + 1);
                }
              },
              child: _label(
                s.t(last ? CareText.qCheckAnswers : CareText.qNext),
                s,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Center(
        child: NeoButton(
          key: const Key('q-restart'),
          variant: NeoButtonVariant.ghost,
          onPressed: _confirmRestart,
          child: _label(s.t(CareText.qStartAgain), s),
        ),
      ),
    ]);
  }

  String _answerText(
    Question q,
    Answer? a,
    CareStrings s,
    QuestionnaireLanguage lang,
  ) {
    if (a == null || a.isEmpty) return s.t(CareText.qNoAnswer);
    if (a.yes case final yes?) return yes ? lang.yes : lang.no;
    if (a.text case final text?) return text;
    return [
      for (final id in a.optionIds)
        if (q.option(id) case final o?) o.label.resolve(lang),
    ].join(', ');
  }

  Widget _summaryPage(
    AttemptController c,
    CareStrings s,
    bool demo,
    QuestionnaireAssetManifest manifest,
  ) {
    final v = c.questionnaire!;
    final lang = _language(v, s);
    return _scaffold([
      _header(c, s, demo),
      Semantics(
        header: true,
        child: Text(
          s.t(CareText.qCheckYourAnswers),
          style: koiTitleStyle(24).copyWith(height: s.isUrdu ? 1.6 : null),
        ),
      ),
      const SizedBox(height: 16),
      if (c.saveStatus == SaveStatus.conflict) _conflictBanner(c, s),
      for (var i = 0; i < v.questions.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: NeoCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.questions[i].prompt.resolve(lang),
                        style: questionnaireTextStyle(
                          lang,
                          size: 14.5,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _answerText(
                          v.questions[i],
                          c.answers[v.questions[i].id],
                          s,
                          lang,
                        ),
                        key: Key('summary-${v.questions[i].id}'),
                        style: questionnaireTextStyle(lang, size: 14.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                NeoButton(
                  key: Key('edit-${v.questions[i].id}'),
                  variant: NeoButtonVariant.ghost,
                  customPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 14,
                  ),
                  onPressed: () {
                    c.goTo(i);
                    setState(() => _summary = false);
                  },
                  child: Text(s.t(CareText.qEdit)),
                ),
              ],
            ),
          ),
        ),
      if (c.submitProblem != null) ...[
        const SizedBox(height: 4),
        KoiErrorText(_submitProblemText(s, c.submitProblem!)),
      ],
      const SizedBox(height: 20),
      NeoButton(
        key: const Key('q-submit'),
        fullWidth: true,
        onPressed: c.saveStatus == SaveStatus.conflict ? null : _submit,
        child: _label(s.t(CareText.qSubmit), s),
      ),
      const SizedBox(height: 12),
      NeoButton(
        key: const Key('q-back-to-questions'),
        variant: NeoButtonVariant.ghost,
        fullWidth: true,
        onPressed: () => setState(() => _summary = false),
        child: _label(s.t(CareText.qBackToQuestions), s),
      ),
    ]);
  }

  static String _submitProblemText(CareStrings s, SubmitProblem p) =>
      s.t(switch (p) {
        SubmitProblem.incomplete => CareText.qProblemIncomplete,
        SubmitProblem.offline => CareText.qProblemOffline,
        SubmitProblem.unconfirmed => CareText.qProblemUnconfirmed,
        SubmitProblem.conflict => CareText.qProblemConflict,
        SubmitProblem.reauth => CareText.qProblemReauth,
        SubmitProblem.other => CareText.genericError,
      });
}

/// The questionnaire's published languages (shown only when there is more
/// than one), like the web runner's Language selector. Each chip is a
/// 48 dp radio target named in its own language.
class QuestionnaireLanguageChips extends StatelessWidget {
  const QuestionnaireLanguageChips({
    super.key,
    required this.locales,
    required this.selected,
    required this.strings,
    required this.onSelected,
  });

  final List<QuestionnaireLanguage> locales;
  final QuestionnaireLanguage selected;
  final CareStrings strings;
  final ValueChanged<QuestionnaireLanguage> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('q-languages'),
    label: strings.t(CareText.qLanguage),
    container: true,
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final l in locales)
          Semantics(
            key: Key('q-lang-${l.wire}'),
            inMutuallyExclusiveGroup: true,
            checked: l == selected,
            button: true,
            label: l.nativeName,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(l),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: koiMinTouch,
                  minWidth: koiMinTouch,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: l == selected
                      ? KoiColors.neoYellow
                      : KoiColors.neoWhite,
                  border: Border.all(width: 2),
                  borderRadius: KoiRadii.pillAll,
                ),
                child: Text(
                  l.nativeName,
                  textDirection: l.direction,
                  style: questionnaireTextStyle(
                    l,
                    size: 14,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// "Question 3 of 7" with a Neo progress bar.
class QuestionnaireProgress extends StatelessWidget {
  const QuestionnaireProgress({
    super.key,
    required this.index,
    required this.total,
    required this.strings,
  });

  final int index;
  final int total;
  final CareStrings strings;

  @override
  Widget build(BuildContext context) {
    final label = strings.questionOf(index + 1, total);
    return Semantics(
      key: const Key('q-progress'),
      label: label,
      value: '${((index + 1) / total * 100).round()}%',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: koiBodyStyle(
              size: 13.5,
              weight: FontWeight.w700,
            ).copyWith(height: strings.lineHeight),
          ),
          const SizedBox(height: 6),
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: KoiColors.neoWhite,
              border: Border.all(width: 2),
              borderRadius: KoiRadii.pillAll,
            ),
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: (index + 1) / total,
              child: Container(
                decoration: const BoxDecoration(
                  color: KoiColors.neoBlue,
                  borderRadius: KoiRadii.pillAll,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Saving… / Saved / Offline – not synced / Not saved / Conflict.
class SaveIndicator extends StatelessWidget {
  const SaveIndicator({
    super.key,
    required this.status,
    this.strings = CareStrings.en,
  });
  final SaveStatus status;
  final CareStrings strings;

  static CareText? textFor(SaveStatus s) => switch (s) {
    SaveStatus.idle => null,
    SaveStatus.saving => CareText.qSaving,
    SaveStatus.saved => CareText.qSaved,
    SaveStatus.offline => CareText.qOfflineNotSynced,
    SaveStatus.notSaved => CareText.qNotSaved,
    SaveStatus.conflict => CareText.qConflict,
  };

  @override
  Widget build(BuildContext context) {
    final key = textFor(status);
    if (key == null) return const SizedBox.shrink();
    final text = strings.t(key);
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        key: const Key('save-indicator'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: status == SaveStatus.conflict || status == SaveStatus.notSaved
              ? KoiColors.neoYellow
              : KoiColors.neoWhite,
          border: Border.all(width: 2),
          borderRadius: KoiRadii.pillAll,
        ),
        child: status == SaveStatus.saving
            ? KoiLoader(compact: true, label: text)
            : Text(
                text,
                style: koiBodyStyle(
                  size: 12.5,
                  weight: FontWeight.w700,
                ).copyWith(height: strings.isUrdu ? 1.6 : null),
              ),
      ),
    );
  }
}

/// The ONLY thing a patient sees after submitting: "Response submitted"
/// and the time, from the Web's write confirmation. Nothing about what
/// happens to the answers afterwards is fetched or shown.
class AcknowledgementView extends StatelessWidget {
  const AcknowledgementView({
    super.key,
    this.submittedAt,
    this.demo = false,
    this.strings = CareStrings.en,
  });

  final DateTime? submittedAt;
  final bool demo;
  final CareStrings strings;

  static const String title = 'Response submitted';

  @override
  Widget build(BuildContext context) {
    final at = submittedAt;
    final s = strings;
    return Directionality(
      textDirection: s.direction,
      child: KoiPage(
        demo: demo,
        children: [
          const SizedBox(height: 24),
          NeoCard(
            variant: NeoCardVariant.yellow,
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    s.t(CareText.qAckTitle),
                    key: const Key('ack-title'),
                    textAlign: TextAlign.center,
                    style: koiTitleStyle(26)
                        .copyWith(height: s.isUrdu ? 1.6 : null),
                  ),
                ),
                if (at != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    s.submittedAt(
                      MaterialLocalizations.of(
                        context,
                      ).formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal())),
                    ),
                    key: const Key('ack-time'),
                    style: koiBodyStyle(size: 14.5)
                        .copyWith(height: s.lineHeight),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          NeoButton(
            key: const Key('ack-done'),
            fullWidth: true,
            onPressed: () => Navigator.of(context).maybePop(),
            child: CareButtonLabel(s.t(CareText.qBackToList)),
          ),
        ],
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirm,
    required this.cancel,
    required this.strings,
  });

  final String title;
  final String message;
  final String confirm;
  final String cancel;
  final CareStrings strings;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(20),
    shape: const RoundedRectangleBorder(),
    elevation: 0,
    child: NeoCard(
      variant: NeoCardVariant.elevated,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: koiTitleStyle(22)
                .copyWith(height: strings.isUrdu ? 1.6 : null),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: koiBodyStyle().copyWith(height: strings.lineHeight),
          ),
          const SizedBox(height: 20),
          NeoButton(
            key: const Key('confirm-yes'),
            variant: NeoButtonVariant.danger,
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: CareButtonLabel(confirm),
          ),
          const SizedBox(height: 10),
          NeoButton(
            key: const Key('confirm-no'),
            variant: NeoButtonVariant.ghost,
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: CareButtonLabel(cancel),
          ),
        ],
      ),
    ),
  );
}
