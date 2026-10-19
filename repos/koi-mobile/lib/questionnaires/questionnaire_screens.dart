import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_widgets.dart';
import '../account/capability_gate.dart';
import '../account/destinations.dart';
import '../app/providers.dart';
import '../experts/expert_screens.dart' show platformErrorText;
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

String attemptStatusLabel(AttemptStatus s) => switch (s) {
  AttemptStatus.notStarted => 'Not started',
  AttemptStatus.inProgress => 'In progress',
  AttemptStatus.submitted => 'Submitted',
};

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
    final list = ref.watch(assignmentsProvider);
    final demo = ref.watch(questionnaireApiProvider).isMock;
    return KoiPage(
      back: true,
      demo: demo,
      title: 'Questionnaires',
      children: list.when(
        loading: () => const [NeoSkeletonList(label: 'Loading questionnaires')],
        error: (e, _) => [
          KoiNoticeCard(
            message: platformErrorText(e),
            action: () => ref.invalidate(assignmentsProvider),
            actionLabel: 'Try again',
          ),
        ],
        data: (items) => items.isEmpty
            ? const [KoiNoticeCard(message: 'Nothing to fill in right now.')]
            : [
                for (final a in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Semantics(
                      button: true,
                      label: '${a.title}. ${attemptStatusLabel(a.status)}',
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
                                  a.title,
                                  style: koiBodyStyle(
                                    size: 17,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  attemptStatusLabel(a.status),
                                  style: koiMutedStyle(),
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

  AttemptController get _c =>
      ref.read(attemptControllerProvider(widget.attemptRef));

  Future<void> _confirmRestart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => const _ConfirmDialog(
        title: 'Start again?',
        message:
            'Your answers to this questionnaire will be cleared. This cannot '
            'be undone.',
        confirm: 'Start again',
      ),
    );
    if (ok != true || !mounted) return;
    // Refused (submitted elsewhere / conflict) shows as the controller's
    // locked or conflict state.
    await _c.restart();
    if (mounted) setState(() => _summary = false);
  }

  Future<void> _submit() async {
    final ok = await _c.submit();
    if (!ok && mounted && _c.submitProblem == SubmitProblem.incomplete) {
      setState(() => _summary = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(attemptControllerProvider(widget.attemptRef));
    final demo = ref.watch(questionnaireApiProvider).isMock;
    final manifest =
        ref.watch(questionnaireAssetManifestProvider).valueOrNull ??
        QuestionnaireAssetManifest.empty;
    final reduce = koiReduceMotion(context);
    final Widget page = switch (c.phase) {
      AttemptPhase.loading => const Scaffold(
        key: ValueKey('loading'),
        body: KoiLoadingPage(label: 'Loading questionnaire…'),
      ),
      AttemptPhase.submitting => const Scaffold(
        key: ValueKey('submitting'),
        body: KoiLoadingPage(label: 'Submitting…'),
      ),
      AttemptPhase.unavailable => KoiPage(
        key: const ValueKey('unavailable'),
        back: true,
        demo: demo,
        children: [
          KoiNoticeCard(
            message: _loadErrorText(c.loadError),
            action: c.load,
            actionLabel: 'Try again',
          ),
        ],
      ),
      AttemptPhase.submitted => AcknowledgementView(
        key: const ValueKey('submitted'),
        submittedAt: c.submittedAt,
        demo: demo,
      ),
      AttemptPhase.answering =>
        _summary
            ? _summaryPage(c, demo, manifest)
            : _questionPage(c, demo, manifest),
    };
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : KoiMotion.fadeUp.duration,
      switchInCurve: Curves.ease,
      child: page,
    );
  }

  static String _loadErrorText(AttemptLoadError? e) => switch (e) {
    AttemptLoadError.offline =>
      'You seem to be offline. This questionnaire needs a connection to '
          'open.',
    AttemptLoadError.notFound => 'This questionnaire is no longer available.',
    AttemptLoadError.forbidden => CapabilityGate.deniedText,
    AttemptLoadError.unsupported =>
      'This questionnaire cannot be shown in this version of the app. Please '
          'let your psychologist know.',
    _ => 'Something went wrong. Please try again.',
  };

  Widget _header(AttemptController c, bool demo) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        const KoiBackButton(),
        const Spacer(),
        SaveIndicator(status: c.saveStatus),
        if (demo) ...[const SizedBox(width: 8), const DemoDataBadge()],
      ],
    ),
  );

  Widget _scaffold(Key key, List<Widget> children) => Scaffold(
    key: key,
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

  Widget _conflictBanner(AttemptController c) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: NeoCard(
      key: const Key('conflict-banner'),
      variant: NeoCardVariant.yellow,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'These answers were changed somewhere else.',
            style: koiBodyStyle(weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose which answers to keep. Nothing is combined.',
            style: koiBodyStyle(size: 14),
          ),
          const SizedBox(height: 12),
          NeoButton(
            key: const Key('conflict-use-server'),
            variant: NeoButtonVariant.ghost,
            onPressed: c.resolveUseServer,
            child: const Text('Load the saved answers'),
          ),
          const SizedBox(height: 10),
          NeoButton(
            key: const Key('conflict-keep-mine'),
            variant: NeoButtonVariant.ghost,
            onPressed: c.resolveKeepMine,
            child: const Text('Keep this device\'s answers'),
          ),
        ],
      ),
    ),
  );

  Widget _questionPage(
    AttemptController c,
    bool demo,
    QuestionnaireAssetManifest manifest,
  ) {
    final v = c.version!;
    final q = v.questions[c.index];
    final last = c.index == v.questions.length - 1;
    final showMissing =
        c.submitProblem == SubmitProblem.incomplete && c.missing.contains(q.id);
    return _scaffold(const ValueKey('question'), [
      _header(c, demo),
      Directionality(
        textDirection: v.locale.direction,
        child: Text(
          v.title,
          style: questionnaireTextStyle(
            v.locale,
            size: 22,
            weight: FontWeight.w700,
          ),
        ),
      ),
      if (c.index == 0 && v.instructions != null) ...[
        const SizedBox(height: 8),
        Directionality(
          textDirection: v.locale.direction,
          child: Text(
            v.instructions!,
            style: questionnaireTextStyle(v.locale, size: 15),
          ),
        ),
      ],
      const SizedBox(height: 16),
      QuestionnaireProgress(index: c.index, total: v.questions.length),
      const SizedBox(height: 20),
      if (c.saveStatus == SaveStatus.conflict) _conflictBanner(c),
      QuestionView(
        key: ValueKey('qv-${q.id}'),
        question: q,
        locale: v.locale,
        answer: c.answers[q.id],
        enabled: c.saveStatus != SaveStatus.conflict,
        manifest: manifest,
        manifestVersion: v.assetManifestVersion,
        onChanged: (a) => c.setAnswer(q.id, a),
      ),
      if (showMissing) ...[
        const SizedBox(height: 8),
        const KoiErrorText('Please answer this question.'),
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
              child: const Text('Previous'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: NeoButton(
              key: const Key('q-next'),
              fullWidth: true,
              customPadding: const EdgeInsets.symmetric(vertical: 14),
              onPressed: () {
                if (q.required &&
                    q.hasWording &&
                    (c.answers[q.id]?.isEmpty ?? true)) {
                  c.markUnanswered(q.id);
                  return;
                }
                if (last) {
                  setState(() => _summary = true);
                } else {
                  c.goTo(c.index + 1);
                }
              },
              child: Text(last ? 'Check answers' : 'Next'),
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
          child: const Text('Start again'),
        ),
      ),
    ]);
  }

  String _answerText(
    Question q,
    Answer? a,
    QuestionnaireLocale locale,
    QuestionnaireAssetManifest manifest,
    String? manifestVersion,
  ) {
    if (a == null || a.isEmpty) return 'No answer';
    if (q.type.isText) return a.text!;
    return [
      for (final id in a.optionIds)
        for (final o in q.options.where((o) => o.id == id))
          o.label ??
              (o.assetId == null
                  ? null
                  : manifest
                        .resolve(
                          o.assetId!,
                          forManifestVersion: manifestVersion,
                        )
                        ?.altFor(locale)) ??
              'Picture',
    ].join(', ');
  }

  Widget _summaryPage(
    AttemptController c,
    bool demo,
    QuestionnaireAssetManifest manifest,
  ) {
    final v = c.version!;
    return _scaffold(const ValueKey('summary'), [
      _header(c, demo),
      Semantics(
        header: true,
        child: Text('Check your answers', style: koiTitleStyle(24)),
      ),
      const SizedBox(height: 16),
      if (c.saveStatus == SaveStatus.conflict) _conflictBanner(c),
      for (var i = 0; i < v.questions.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: NeoCard(
            padding: const EdgeInsets.all(14),
            child: Directionality(
              textDirection: v.locale.direction,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.questions[i].prompt ?? missingWordingText,
                          style: questionnaireTextStyle(
                            v.locale,
                            size: 14.5,
                            weight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _answerText(
                            v.questions[i],
                            c.answers[v.questions[i].id],
                            v.locale,
                            manifest,
                            v.assetManifestVersion,
                          ),
                          key: Key('summary-${v.questions[i].id}'),
                          style: questionnaireTextStyle(v.locale, size: 14.5),
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
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (c.submitProblem != null) ...[
        const SizedBox(height: 4),
        KoiErrorText(_submitProblemText(c.submitProblem!)),
      ],
      const SizedBox(height: 20),
      NeoButton(
        key: const Key('q-submit'),
        fullWidth: true,
        onPressed: c.saveStatus == SaveStatus.conflict ? null : _submit,
        child: const Text('Submit'),
      ),
      const SizedBox(height: 12),
      NeoButton(
        key: const Key('q-back-to-questions'),
        variant: NeoButtonVariant.ghost,
        fullWidth: true,
        onPressed: () => setState(() => _summary = false),
        child: const Text('Back to questions'),
      ),
    ]);
  }

  static String _submitProblemText(SubmitProblem p) => switch (p) {
    SubmitProblem.incomplete => 'Please answer the required questions.',
    SubmitProblem.offline =>
      'You seem to be offline. Your answers are saved on this device; '
          'connect to submit.',
    SubmitProblem.unconfirmed =>
      'We could not confirm your submission. Tap Submit again: it will not '
          'be sent twice.',
    SubmitProblem.conflict =>
      'These answers were changed somewhere else. Choose which to keep '
          'first.',
    SubmitProblem.other => 'Something went wrong. Please try again.',
  };
}

/// "Question 3 of 7" with a Neo progress bar.
class QuestionnaireProgress extends StatelessWidget {
  const QuestionnaireProgress({
    super.key,
    required this.index,
    required this.total,
  });

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final label = 'Question ${index + 1} of $total';
    return Semantics(
      key: const Key('q-progress'),
      label: label,
      value: '${((index + 1) / total * 100).round()}%',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: koiBodyStyle(size: 13.5, weight: FontWeight.w700)),
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

/// Saving… / Saved / Offline – not synced / Conflict.
class SaveIndicator extends StatelessWidget {
  const SaveIndicator({super.key, required this.status});
  final SaveStatus status;

  static String? textFor(SaveStatus s) => switch (s) {
    SaveStatus.idle => null,
    SaveStatus.saving => 'Saving…',
    SaveStatus.saved => 'Saved',
    SaveStatus.offline => 'Offline – not synced',
    SaveStatus.conflict => 'Conflict',
  };

  @override
  Widget build(BuildContext context) {
    final text = textFor(status);
    if (text == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        key: const Key('save-indicator'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: status == SaveStatus.conflict
              ? KoiColors.neoYellow
              : KoiColors.neoWhite,
          border: Border.all(width: 2),
          borderRadius: KoiRadii.pillAll,
        ),
        child: status == SaveStatus.saving
            ? const KoiLoader(compact: true, label: 'Saving…')
            : Text(
                text,
                style: koiBodyStyle(size: 12.5, weight: FontWeight.w700),
              ),
      ),
    );
  }
}

/// The ONLY thing a patient sees after submitting.
class AcknowledgementView extends StatelessWidget {
  const AcknowledgementView({super.key, this.submittedAt, this.demo = false});

  final DateTime? submittedAt;
  final bool demo;

  static const String title = 'Response submitted';

  @override
  Widget build(BuildContext context) {
    final at = submittedAt;
    return KoiPage(
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
                  title,
                  key: const Key('ack-title'),
                  textAlign: TextAlign.center,
                  style: koiTitleStyle(26),
                ),
              ),
              if (at != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Submitted at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()))}',
                  key: const Key('ack-time'),
                  style: koiBodyStyle(size: 14.5),
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
          child: const Text('Back to questionnaires'),
        ),
      ],
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirm,
  });

  final String title;
  final String message;
  final String confirm;

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
          Text(title, style: koiTitleStyle(22)),
          const SizedBox(height: 8),
          Text(message, style: koiBodyStyle()),
          const SizedBox(height: 20),
          NeoButton(
            key: const Key('confirm-yes'),
            variant: NeoButtonVariant.danger,
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirm),
          ),
          const SizedBox(height: 10),
          NeoButton(
            key: const Key('confirm-no'),
            variant: NeoButtonVariant.ghost,
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
