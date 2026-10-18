import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../onboarding/step_layout.dart' show bodyText, displayText;
import '../theme/koi_colors.dart';
import 'checkin_models.dart';
import 'checkin_providers.dart';
import 'checkin_screen.dart';
import 'checkin_stats.dart';
import 'local_breathing.dart';

/// Mobile-only texts (approved 2026-10-19, Prompt 28).
abstract final class MoodTexts {
  static const String title = 'Mood Trends';
  static const String empty = 'No mood check-ins yet';
  static const String emptyFiltered = 'No check-ins in this view yet';
  static const String emotions = 'Emotions';
  static const String all = 'All';
  static const String heavy =
      'Things seem heavy lately. Want to talk or try a breathing exercise?';
  static const String talk = 'Talk with KOI';
  static const String breathe = 'Breathing exercise';
  static const String addSamples = 'Add sample check-ins (debug)';
  static const String clear = 'Clear check-ins (debug)';
  static const String checkInTitle = 'Daily check-in';
  static const String morningPrompt = 'How are you this morning?';
  static const String startMorning = 'Start check-in';
  static const String eveningTitle = 'Evening reflection';
  static const String eveningPrompt = 'One good moment from today?';
  static const String startEvening = 'Add reflection';
  static const String calendar = 'Check-in Calendar';
}

/// Emotion colours (KOI tokens).
Color emotionColor(CheckInEmotion e) => switch (e) {
  CheckInEmotion.happy => KoiColors.neoYellow,
  CheckInEmotion.sad => KoiColors.neoBlue,
  CheckInEmotion.anxious => KoiColors.neoPurple,
  CheckInEmotion.calm => KoiColors.cyan,
  CheckInEmotion.neutral => const Color(0xFFD1D5DB),
};

/// The Progress page's white card look (border 2.5, radius 20, shadow 6).
class _Card extends StatelessWidget {
  const _Card({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: KoiColors.neoWhite,
      border: Border.all(width: 2.5),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(offset: Offset(6, 6))],
    ),
    child: child,
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? KoiColors.neoBlack : KoiColors.neoWhite,
          border: Border.all(width: 2),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          label,
          style: displayText(
            12,
            color: selected ? KoiColors.neoWhite : KoiColors.neoBlack,
          ),
        ),
      ),
    ),
  );
}

class _Button extends StatelessWidget {
  const _Button({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: KoiColors.neoYellow,
          border: Border.all(width: 2.5),
          borderRadius: BorderRadius.circular(9999),
          boxShadow: const [BoxShadow(offset: Offset(3, 3))],
        ),
        child: Text(label, style: displayText(14)),
      ),
    ),
  );
}

/// Entry card: the morning check-in before 15:00, the evening reflection
/// from 15:00; after a morning check-in, the celebration and suggestions.
class DailyCheckInCard extends ConsumerWidget {
  const DailyCheckInCard({super.key, required this.now});
  final DateTime Function() now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
    if (uid == null) return const SizedBox.shrink();
    final h = ref.watch(checkInControllerProvider(uid)).history;
    final t = now();
    final today = dayKey(t);
    final kind = CheckInKind.at(t);
    final morning = h.morningOn(today);
    final evening = h.eveningOn(today);
    final Widget body;
    if (kind == CheckInKind.evening && evening == null) {
      body = _prompt(
        context,
        MoodTexts.eveningTitle,
        MoodTexts.eveningPrompt,
        MoodTexts.startEvening,
        CheckInKind.evening,
      );
    } else if (morning != null) {
      body = CheckInResult(morning: morning, showClose: false);
    } else if (kind == CheckInKind.morning) {
      body = _prompt(
        context,
        MoodTexts.checkInTitle,
        MoodTexts.morningPrompt,
        MoodTexts.startMorning,
        CheckInKind.morning,
      );
    } else {
      body = const CheckInResult(showClose: false);
    }
    return _Card(key: const Key('daily-checkin-card'), child: body);
  }

  Widget _prompt(
    BuildContext context,
    String title,
    String prompt,
    String action,
    CheckInKind kind,
  ) => Column(
    key: Key('checkin-entry-${kind.id}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: displayText(18)),
      const SizedBox(height: 6),
      Text(prompt, style: bodyText(14, color: const Color(0xFF4B5563))),
      const SizedBox(height: 14),
      _Button(
        key: const Key('checkin-start'),
        label: action,
        onTap: () => openCheckIn(context, kind),
      ),
    ],
  );
}

/// SDS M11 on Progress (MLT-1/6/7/8/4): trend line with time filters, the
/// emotion pie, an emotion filter, the gentle "heavy" card and the empty
/// state. Only real check-ins; the sample data exists only behind the debug
/// button.
class MoodDashboard extends ConsumerStatefulWidget {
  const MoodDashboard({super.key, required this.now, this.onOpenChat});

  final DateTime Function() now;

  /// "Talk with KOI": the shell switches to the Chat tab.
  final VoidCallback? onOpenChat;

  @override
  ConsumerState<MoodDashboard> createState() => _MoodDashboardState();
}

class _MoodDashboardState extends ConsumerState<MoodDashboard> {
  MoodRange _range = MoodRange.days7;
  CheckInEmotion? _emotion;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
    if (uid == null) return const SizedBox.shrink();
    final controller = ref.watch(checkInControllerProvider(uid));
    final mornings = controller.history.mornings;
    final today = widget.now();
    final debug = ref.watch(checkInDebugToolsProvider);
    final inRange = moodPoints(mornings, range: _range, today: today);
    final points = moodPoints(
      mornings,
      range: _range,
      today: today,
      emotion: _emotion,
    );
    final shares = emotionShares(inRange);
    return _Card(
      key: const Key('mood-dashboard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(MoodTexts.title, style: displayText(18)),
          if (showsHeavyCard(mornings)) ...[
            const SizedBox(height: 14),
            _HeavyCard(onOpenChat: widget.onOpenChat),
          ],
          const SizedBox(height: 14),
          if (mornings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                MoodTexts.empty,
                key: const Key('mood-empty'),
                textAlign: TextAlign.center,
                style: bodyText(13, color: const Color(0xFF4B5563)),
              ),
            )
          else ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in MoodRange.values)
                  _Pill(
                    key: Key('range-${r.name}'),
                    label: r.label,
                    selected: r == _range,
                    onTap: () => setState(() => _range = r),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (points.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  MoodTexts.emptyFiltered,
                  key: const Key('mood-empty-filtered'),
                  textAlign: TextAlign.center,
                  style: bodyText(13, color: const Color(0xFF4B5563)),
                ),
              )
            else
              SizedBox(
                key: const Key('mood-trend'),
                height: 160,
                child: _TrendChart(points: points),
              ),
            const SizedBox(height: 18),
            Text(MoodTexts.emotions, style: displayText(15)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Pill(
                  key: const Key('emotion-filter-all'),
                  label: MoodTexts.all,
                  selected: _emotion == null,
                  onTap: () => setState(() => _emotion = null),
                ),
                for (final e in CheckInEmotion.values)
                  _Pill(
                    key: Key('emotion-filter-${e.id}'),
                    label: '${e.emoji} ${e.label}',
                    selected: _emotion == e,
                    onTap: () => setState(() => _emotion = e),
                  ),
              ],
            ),
            if (shares.isNotEmpty) ...[
              const SizedBox(height: 14),
              _EmotionPie(shares: shares),
            ],
          ],
          if (debug) ...[
            const SizedBox(height: 16),
            Wrap(
              key: const Key('checkin-debug'),
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const Key('checkin-debug-add'),
                  onPressed: () => controller.addSamples(today),
                  child: const Text(MoodTexts.addSamples),
                ),
                TextButton(
                  key: const Key('checkin-debug-clear'),
                  onPressed: controller.clear,
                  child: const Text(MoodTexts.clear),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// MLT-1: mood_rating (1–5) per check-in day; x = days since the first
/// point shown.
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});
  final List<MorningCheckIn> points;

  @override
  Widget build(BuildContext context) {
    final first = dayOf(points.first.day);
    final spots = [
      for (final p in points)
        FlSpot(
          dayOf(p.day).difference(first).inDays.toDouble(),
          p.mood.toDouble(),
        ),
    ];
    return LineChart(
      LineChartData(
        minY: 1,
        maxY: 5,
        minX: 0,
        maxX: spots.last.x < 1 ? 1 : spots.last.x,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 24,
              getTitlesWidget: (v, meta) =>
                  Text('${v.toInt()}', style: bodyText(11)),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: KoiColors.neoBlue,
            barWidth: 3,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

/// MLT-7: share of each emotion in the selected time range.
class _EmotionPie extends StatelessWidget {
  const _EmotionPie({required this.shares});
  final Map<CheckInEmotion, int> shares;

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('emotion-pie'),
    children: [
      SizedBox(
        width: 110,
        height: 110,
        child: PieChart(
          PieChartData(
            centerSpaceRadius: 22,
            sectionsSpace: 1,
            sections: [
              for (final MapEntry(key: e, value: pct) in shares.entries)
                PieChartSectionData(
                  value: pct.toDouble(),
                  color: emotionColor(e),
                  radius: 30,
                  showTitle: false,
                ),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final MapEntry(key: e, value: pct) in shares.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${e.emoji} ${e.label} · $pct%',
                  key: Key('pie-${e.id}'),
                  style: bodyText(13, weight: FontWeight.w500),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// MLT-4: a gentle note, not the crisis flow.
class _HeavyCard extends ConsumerWidget {
  const _HeavyCard({required this.onOpenChat});
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    key: const Key('mood-heavy'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E0),
      border: Border.all(width: 2),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(MoodTexts.heavy, style: bodyText(14, weight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onOpenChat != null)
              _Button(
                key: const Key('heavy-chat'),
                label: MoodTexts.talk,
                onTap: onOpenChat!,
              ),
            _Button(
              key: const Key('heavy-breathing'),
              label: MoodTexts.breathe,
              onTap: () => openLocalBreathing(context, ref),
            ),
          ],
        ),
      ],
    ),
  );
}

/// DCW-10: the month, an emotion icon on each morning check-in day, other
/// days plain. Today opens the check-in; a past check-in day shows its
/// answers.
class CheckInCalendar extends ConsumerStatefulWidget {
  const CheckInCalendar({super.key, required this.now});
  final DateTime Function() now;

  @override
  ConsumerState<CheckInCalendar> createState() => _CheckInCalendarState();
}

class _CheckInCalendarState extends ConsumerState<CheckInCalendar> {
  late DateTime _month = DateTime(widget.now().year, widget.now().month);

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', //
    'August', 'September', 'October', 'November', 'December',
  ];

  void _shift(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by));

  Future<void> _tapDay(String day, MorningCheckIn? m, CheckInHistory h) async {
    final now = widget.now();
    if (day == dayKey(now)) return openCheckIn(context, CheckInKind.at(now));
    final e = h.eveningOn(day);
    if (m == null && e == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('cal-day-details'),
        title: Text(day, style: displayText(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m != null) ...[
              Text('${m.emotion.emoji} ${m.emotion.label}'),
              Text('Mood ${m.mood}/5 · Sleep ${m.sleep}/5'),
              Text('Connection ${m.connection}/5 · Energy ${m.energy}/5'),
            ],
            if (e != null && e.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(e.text),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(CheckInTexts.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
    if (uid == null) return const SizedBox.shrink();
    final h = ref.watch(checkInControllerProvider(uid)).history;
    final first = _month;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    final cells = <Widget>[
      for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
        Center(child: Text(d, style: displayText(12))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++)
        _dayCell(DateTime(first.year, first.month, d), h),
    ];
    return _Card(
      key: const Key('checkin-calendar'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(MoodTexts.calendar, style: displayText(18))),
              IconButton(
                key: const Key('cal-prev'),
                tooltip: 'Previous month',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                key: const Key('cal-next'),
                tooltip: 'Next month',
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Text(
            '${_months[first.month - 1]} ${first.year}',
            key: const Key('cal-month'),
            style: bodyText(14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.8,
            children: cells,
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime date, CheckInHistory h) {
    final day = dayKey(date);
    final m = h.morningOn(day);
    final isToday = day == dayKey(widget.now());
    return Semantics(
      button: true,
      label: m == null ? day : '$day, ${m.emotion.label}',
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('cal-day-$day'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _tapDay(day, m, h),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: isToday ? Border.all(width: 2) : null,
          ),
          alignment: Alignment.center,
          // Number + emoji scale down rather than overflow on narrow phones.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${date.day}', style: bodyText(11)),
                if (m != null)
                  Text(
                    m.emotion.emoji,
                    key: Key('cal-icon-$day'),
                    style: const TextStyle(fontSize: 14),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
