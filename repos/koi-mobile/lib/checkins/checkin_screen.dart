import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../avatar/avatar_providers.dart';
import '../avatar/avatar_state.dart' show CompanionAvatar;
import '../onboarding/step_layout.dart' show bodyText, displayText;
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';
import 'checkin_models.dart';
import 'checkin_providers.dart';
import 'checkin_stats.dart';

/// Mobile-only texts (approved 2026-10-19, Prompt 28). Gentle wording only:
/// no "should / must / have to", no missed days or broken streaks.
abstract final class CheckInTexts {
  static const String sleep = 'How did you sleep?';
  static const String mood = "How's your mood?";
  static const String connection = 'How connected do you feel to others?';
  static const String energy = "How's your energy?";
  static const String emotion = 'Which feels closest right now?';
  static const String scale = '1 = low · 5 = great';
  static const String skip = 'Skip';
  static const String evening = 'What was one good moment or connection today?';
  static const String eveningHint = 'Optional · only you can read this';
  static const String save = 'Save';
  static const String close = 'Close';
  static const String celebrate = 'You checked in today 🎉';
  static const String thanks = 'Thank you for sharing 💛';
  static const String markDone = 'Mark done';
  static const String done = 'Done ✓';
  static const String saveFailed = "Couldn't save this check-in. Try again?";

  static String daysCount(int n) =>
      n == 1 ? "You've checked in on 1 day." : "You've checked in on $n days.";
}

/// Opens the morning check-in or the evening reflection over the app.
Future<void> openCheckIn(BuildContext context, CheckInKind kind) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'checkin'),
        builder: (_) => CheckInScreen(kind: kind),
      ),
    );

/// DCW-2 morning check-in (5 taps: sleep, mood, connection, energy, one
/// emotion; the 5th tap saves) or DCW-3 evening reflection. Skip leaves
/// without saving anything.
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key, required this.kind});

  final CheckInKind kind;

  static const List<String> questions = [
    CheckInTexts.sleep,
    CheckInTexts.mood,
    CheckInTexts.connection,
    CheckInTexts.energy,
  ];

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  final List<int> _ratings = [];
  final TextEditingController _text = TextEditingController();
  MorningCheckIn? _saved;
  bool _eveningSaved = false;
  bool _saving = false;
  bool _failed = false;

  String? get _uid => ref.read(authServiceProvider).user?.uid;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _back() {
    if (_ratings.isEmpty) return _close();
    setState(() => _ratings.removeLast());
  }

  void _rate(int value) => setState(() => _ratings.add(value));

  Future<void> _pickEmotion(CheckInEmotion e) async {
    final uid = _uid;
    if (uid == null || _saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      final m = await ref
          .read(checkInControllerProvider(uid))
          .saveMorning(
            now: ref.read(checkInClockProvider)(),
            sleep: _ratings[0],
            mood: _ratings[1],
            connection: _ratings[2],
            energy: _ratings[3],
            emotion: e,
          );
      if (mounted) setState(() => _saved = m);
    } catch (err) {
      debugPrint('KOI: check-in not saved: ${err.runtimeType}');
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveEvening() async {
    final uid = _uid;
    if (uid == null || _saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await ref
          .read(checkInControllerProvider(uid))
          .saveEvening(now: ref.read(checkInClockProvider)(), text: _text.text);
      if (mounted) setState(() => _eveningSaved = true);
    } catch (err) {
      debugPrint('KOI: reflection not saved: ${err.runtimeType}');
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final finished = _saved != null || _eveningSaved;
    return Scaffold(
      backgroundColor: KoiColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              onBack: finished ? _close : _back,
              onSkip: finished ? null : _close,
            ),
            const _CompanionHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: _body(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_saved case final m?) return CheckInResult(morning: m);
    if (_eveningSaved) return const CheckInResult();
    final error = _failed
        ? Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              CheckInTexts.saveFailed,
              key: const Key('checkin-error'),
              style: bodyText(14, color: const Color(0xFF4B5563)),
            ),
          )
        : const SizedBox.shrink();
    if (widget.kind == CheckInKind.evening) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(CheckInTexts.evening, style: displayText(22, height: 1.25)),
          const SizedBox(height: 16),
          TextField(
            key: const Key('reflection-input'),
            controller: _text,
            maxLength: EveningReflection.maxLength,
            maxLines: 4,
            minLines: 2,
            decoration: InputDecoration(
              hintText: CheckInTexts.eveningHint,
              filled: true,
              fillColor: KoiColors.neoWhite,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          NeoButton(
            key: const Key('reflection-save'),
            fullWidth: true,
            loading: _saving,
            onPressed: _saving ? null : _saveEvening,
            child: const Text(CheckInTexts.save),
          ),
          error,
        ],
      );
    }
    final step = _ratings.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Dots(step: step, total: 5),
        const SizedBox(height: 20),
        if (step < 4) ...[
          Text(
            CheckInScreen.questions[step],
            key: Key('question-$step'),
            style: displayText(22, height: 1.25),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var v = 1; v <= 5; v++) ...[
                if (v > 1) const SizedBox(width: 8),
                Expanded(
                  child: _Choice(
                    key: Key('rating-$v'),
                    label: '$v',
                    onTap: () => _rate(v),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            CheckInTexts.scale,
            textAlign: TextAlign.center,
            style: bodyText(13, color: const Color(0xFF4B5563)),
          ),
        ] else ...[
          Text(
            CheckInTexts.emotion,
            key: const Key('question-4'),
            style: displayText(22, height: 1.25),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final e in CheckInEmotion.values)
                _Choice(
                  key: Key('emotion-${e.id}'),
                  label: '${e.emoji} ${e.label}',
                  onTap: _saving ? null : () => _pickEmotion(e),
                ),
            ],
          ),
        ],
        error,
      ],
    );
  }
}

/// After saving: celebration only (DCW-7), and for a morning check-in its
/// 1–2 suggestions with "Mark done" (DCW-4/5/6). Also on the Progress card.
class CheckInResult extends ConsumerWidget {
  const CheckInResult({super.key, this.morning, this.showClose = true});

  /// null after an evening reflection.
  final MorningCheckIn? morning;
  final bool showClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
    final controller = uid == null
        ? null
        : ref.watch(checkInControllerProvider(uid));
    final m = morning == null
        ? null
        : controller?.history.morningOn(morning!.day) ?? morning;
    final days = controller?.history.daysCheckedIn ?? 0;
    return Column(
      key: const Key('checkin-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          m != null ? CheckInTexts.celebrate : CheckInTexts.thanks,
          key: const Key('checkin-celebrate'),
          style: displayText(20),
        ),
        if (days > 0) ...[
          const SizedBox(height: 6),
          Text(
            CheckInTexts.daysCount(days),
            key: const Key('checkin-days'),
            style: bodyText(14, color: const Color(0xFF4B5563)),
          ),
        ],
        if (m != null) ...[
          const SizedBox(height: 16),
          for (final a in m.suggestions) ...[
            _Suggestion(
              activity: a,
              done: m.activityDone == a,
              onDone: m.activityDone != null || controller == null
                  ? null
                  : () => controller.markDone(m, a),
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (showClose) ...[
          const SizedBox(height: 8),
          NeoButton(
            key: const Key('checkin-close'),
            fullWidth: true,
            variant: NeoButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(CheckInTexts.close),
          ),
        ],
      ],
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.activity,
    required this.done,
    required this.onDone,
  });

  final CheckInActivity activity;
  final bool done;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('activity-${activity.id}'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: KoiColors.neoWhite,
      border: Border.all(width: 2),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            activity.text,
            style: bodyText(14, weight: FontWeight.w500, height: 1.35),
          ),
        ),
        const SizedBox(width: 8),
        if (done)
          Text(
            CheckInTexts.done,
            key: Key('activity-done-${activity.id}'),
            style: displayText(13),
          )
        else if (onDone != null)
          Semantics(
            button: true,
            child: GestureDetector(
              key: Key('activity-mark-${activity.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onDone,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: KoiColors.neoYellow,
                  border: Border.all(width: 2),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(CheckInTexts.markDone, style: displayText(12)),
              ),
            ),
          ),
      ],
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onSkip});
  final VoidCallback onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
    child: Row(
      children: [
        IconButton(
          key: const Key('checkin-back'),
          tooltip: 'Back',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        const Spacer(),
        if (onSkip != null)
          TextButton(
            key: const Key('checkin-skip'),
            onPressed: onSkip,
            child: Text(CheckInTexts.skip, style: displayText(15)),
          ),
      ],
    ),
  );
}

/// The saved companion asks (still image, no WebView).
class _CompanionHeader extends ConsumerWidget {
  const _CompanionHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(selectedAvatarProvider).valueOrNull;
    final image = c?.model?.imageAsset;
    return Padding(
      key: const Key('checkin-companion'),
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: KoiColors.neoYellow,
              shape: BoxShape.circle,
              border: Border.all(width: 2.5),
            ),
            alignment: Alignment.center,
            child: image != null
                ? Image.asset(image, fit: BoxFit.cover, width: 56, height: 56)
                : Text(
                    c == CompanionAvatar.koi ? '🦊' : '💛',
                    style: const TextStyle(fontSize: 26),
                  ),
          ),
          const SizedBox(width: 12),
          Text(c?.name ?? 'KOI', style: displayText(18)),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < total; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: i <= step ? KoiColors.neoBlack : KoiColors.neoWhite,
            shape: BoxShape.circle,
            border: Border.all(width: 1.5),
          ),
        ),
      ],
    ],
  );
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52, minWidth: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: KoiColors.neoWhite,
          border: Border.all(width: 2.5),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(offset: Offset(3, 3))],
        ),
        child: Text(label, style: displayText(17)),
      ),
    ),
  );
}
