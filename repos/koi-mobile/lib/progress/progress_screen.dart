import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../chat/widgets/chat_widgets.dart' show StrokeIcon;
import '../settings/widgets/settings_widgets.dart'
    show
        SettingsToastLayer,
        ToastMessage,
        ToastType,
        cssGradient135,
        settingsText;
import '../theme/koi_colors.dart';
import '../theme/koi_motion.dart';
import 'progress_icons.dart';
import 'progress_stats.dart';

/// One mood bar (web `moodData` entry).
@immutable
class MoodPoint {
  const MoodPoint(this.day, this.mood, this.color);
  final String day;
  final double mood;
  final Color color;
}

/// Mirrors src/app/(authenticated)/progress/page.tsx with real local data
/// (decisions 2026-10-14):
/// - Days streak, Total Sessions, days active and the heatmap come from the
///   user's own messages in the local chat history ([ProgressStats]).
/// - Jigsaw pieces, Avg Mood and the mood chart have no data source on web
///   or mobile yet, so they show 0 / empty states. Web's numbers are all
///   hard-coded (see WEB_BUGS_FOUND_DURING_MOBILE.md).
/// - No third-party images (web loads api.dicebear.com into unlocked
///   jigsaw pieces); unlocked pieces are plain colour.
///
/// Text uses var(--font-body) (DM Sans) everywhere on this page; fontWeight
/// 800 renders as 700 (DM Sans is loaded 300–700). Hover-only effects are
/// not mirrored.
class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key, this.now = DateTime.now});

  /// Injectable clock for tests.
  final DateTime Function() now;

  /// Mobile-only toast texts (decision 2026-10-14: "coming soon" like the
  /// Export page's PDF button).
  static const String downloadSoon = 'Download coming soon!';
  static const String shareSoon = 'Share coming soon!';

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  ProgressStats _stats = ProgressStats.empty;
  bool _jigsawExpanded = false;
  int? _selectedMilestone;
  int? _selectedMoodDay;
  ToastMessage? _toast;
  int _toastSeq = 0;

  // TODO(product): no code on web or mobile writes jigsaw progress or mood
  // entries yet (web db.ts jigsawProgress / moodEntries are never written).
  // When they exist, read them here; mood entries must be CSE-encrypted.
  static const int _totalPieces = 0;
  static const List<MoodPoint> _moodData = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = ref.read(authServiceProvider).user?.uid;
    if (uid == null) return;
    try {
      // Q5: conversationId = uid.
      final rows = await ref.read(messageStoreProvider).byConversation(uid);
      if (mounted) {
        setState(() => _stats = ProgressStats.from(rows, widget.now()));
      }
    } catch (e) {
      debugPrint('KOI: progress load failed: $e');
    }
  }

  void _soon(String message) => setState(
    () => _toast = ToastMessage(message, ToastType.info, ++_toastSeq),
  );

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: KoiColors.background,
    child: Stack(
      fit: StackFit.expand, // fill the tab even under loose constraints
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            key: const Key('progress-scroll'),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  // padding 1.5rem 1.5rem 0; paddingBottom 2rem
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(),
                      const SizedBox(height: 24),
                      _JigsawCard(
                        expanded: _jigsawExpanded,
                        totalPieces: _totalPieces,
                        onToggle: (v) => setState(() => _jigsawExpanded = v),
                      ),
                      const SizedBox(height: 20),
                      _statsGrid(),
                      const SizedBox(height: 20),
                      _moodCard(),
                      const SizedBox(height: 20),
                      _milestones(),
                      const SizedBox(height: 24),
                      _HeatmapCard(heatmap: _stats.heatmap),
                      const SizedBox(height: 24),
                      const _EmotionalGrowthCard(),
                      const SizedBox(height: 24),
                      _shareCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SettingsToastLayer(
          toast: _toast,
          onClose: () => setState(() => _toast = null),
        ),
      ],
    ),
  );

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // h1 800 2rem, -0.03em, inline-block; sparkles absolute top -8px,
      // right -32px, floatY 2s ease-in-out infinite.
      Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 32),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Text(
              'Your Progress',
              style: settingsText(
                32,
                weight: FontWeight.w800,
                letterSpacing: -0.03 * 32,
              ),
            ),
            Positioned(
              top: -8,
              right: -32,
              child: KoiFloatY(
                spec: const KoiAnimationSpec(
                  duration: Duration(seconds: 2),
                  repeat: true,
                ),
                child: StrokeIcon(
                  paths: ProgressIcons.sparkles,
                  size: 20,
                  strokeWidth: 2,
                  color: KoiColors.neoYellow,
                ),
              ),
            ),
          ],
        ),
      ),
      Text(
        'Every step matters. Keep growing.',
        style: settingsText(
          14,
          weight: FontWeight.w500,
          color: const Color(0xFF666666),
        ),
      ),
    ],
  );

  // STATS (page.tsx:4-8) with real values.
  Widget _statsGrid() {
    final tiles = [
      _StatTile(
        key: const Key('stat-streak'),
        label: 'Days Streak',
        value: '${_stats.currentStreak}',
        unit: 'days',
        color: KoiColors.neoYellow,
        icon: ProgressIcons.flame,
      ),
      _StatTile(
        key: const Key('stat-sessions'),
        label: 'Total Sessions',
        value: '${_stats.sessions}',
        unit: 'sessions',
        color: const Color(0xFF2DD36F),
        icon: ProgressIcons.chat,
      ),
      _StatTile(
        key: const Key('stat-mood'),
        label: 'Avg Mood',
        value: '–', // approved empty state (no mood data yet)
        unit: '/ 10',
        color: KoiColors.neoBlue,
        icon: ProgressIcons.smile,
      ),
    ];
    // grid repeat(3, 1fr), gap 10px; rows stretch to the tallest tile.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }

  /// Last 7 days ending today, as web's 'Mon'…'Sun' labels.
  List<String> get _last7Days {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = widget.now();
    return [
      for (var i = 6; i >= 0; i--)
        names[DateTime(today.year, today.month, today.day - i).weekday - 1],
    ];
  }

  Widget _moodCard() {
    final hasData = _moodData.isNotEmpty;
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            title: 'Mood Trends',
            icon: ProgressIcons.trendingUp,
            iconColor: const Color(0xFF2DD36F),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 8), // gap 0.5rem
                  Expanded(
                    child: _MoodColumn(
                      label: hasData ? _moodData[i].day : _last7Days[i],
                      point: hasData ? _moodData[i] : null,
                      selected: _selectedMoodDay == i,
                      onTap: () => setState(
                        () =>
                            _selectedMoodDay = _selectedMoodDay == i ? null : i,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasData
                ? 'Your emotional journey over the past week shows growth '
                      'and resilience'
                : 'No mood check-ins yet', // approved empty state
            key: const Key('mood-caption'),
            textAlign: TextAlign.center,
            style: settingsText(12, color: const Color(0xFF666666)),
          ),
        ],
      ),
    );
  }

  // MILESTONES (page.tsx:10-15). Done state from real data where possible
  // (decision 2026-10-14); '50 Pieces' / 'Deep Diver' have no source.
  List<_Milestone> get _milestoneList => [
    _Milestone(
      1,
      'First Conversation',
      'You opened up for the first time.',
      _stats.messagesSent > 0,
      const Color(0xFF2DD36F),
      '+5 pieces',
    ),
    _Milestone(
      2,
      '7-Day Streak',
      'A week of showing up for yourself.',
      _stats.longestStreak >= 7,
      const Color(0xFF2D63EB),
      '+10 pieces',
    ),
    const _Milestone(
      3,
      '50 Pieces',
      'Halfway to your first milestone.',
      _totalPieces >= 50,
      Color(0xFFFFD100),
      '+15 pieces',
    ),
    const _Milestone(
      4,
      'Deep Diver',
      'Explored something truly personal.',
      false,
      Color(0xFF845EC2),
      '+20 pieces',
    ),
  ];

  Widget _milestones() {
    final list = _milestoneList;
    final done = list.where((m) => m.done).length;
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Milestones',
                  style: settingsText(
                    17.6,
                    weight: FontWeight.w800,
                    letterSpacing: -0.02 * 17.6,
                  ),
                ),
              ),
              Container(
                key: const Key('milestones-badge'),
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: KoiColors.neoYellow,
                  border: Border.all(width: 2),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(offset: Offset(2, 2))],
                ),
                child: Text(
                  '$done/${list.length} Complete',
                  style: settingsText(11.2, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17.6), // 1.1rem
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const SizedBox(height: 14), // gap 0.875rem
            _MilestoneRow(
              milestone: list[i],
              last: i == list.length - 1,
              selected: _selectedMilestone == list[i].id,
              onTap: () => setState(
                () => _selectedMilestone = _selectedMilestone == list[i].id
                    ? null
                    : list[i].id,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shareCard() => Container(
    key: const Key('share-card'),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: KoiColors.neoBlack,
      border: Border.all(width: 2.5),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(color: KoiColors.neoYellow, offset: Offset(6, 6)),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          top: -60,
          right: -60,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x1AFFD100), // rgba(255,209,0,0.1)
              border: Border.all(
                width: 2,
                color: const Color(0x33FFD100), // rgba(255,209,0,0.2)
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  StrokeIcon(
                    paths: ProgressIcons.sparkles,
                    size: 24,
                    strokeWidth: 2,
                    color: KoiColors.neoYellow,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Share Your Progress',
                    style: settingsText(
                      17.6,
                      weight: FontWeight.w800,
                      color: KoiColors.neoWhite,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF), // rgba(255,255,255,0.08)
                  border: Border.all(
                    width: 2,
                    color: const Color(0x26FFFFFF), // 0.15
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ShareStat(
                          key: const Key('share-pieces'),
                          value: '$_totalPieces',
                          label: 'pieces collected',
                          color: KoiColors.neoYellow,
                        ),
                        _ShareStat(
                          key: const Key('share-days'),
                          value: '${_stats.daysActive}',
                          label: 'days active',
                          color: const Color(0xFF2DD36F),
                        ),
                        _ShareStat(
                          key: const Key('share-streak'),
                          value: '${_stats.currentStreak}',
                          label: 'day streak',
                          color: KoiColors.neoBlue,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '"Every conversation is a step toward understanding '
                      'myself better"',
                      textAlign: TextAlign.center,
                      style: settingsText(
                        12,
                        color: const Color(0xB3FFFFFF), // 0.7
                      ).copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ShareButton(
                      key: const Key('share-download'),
                      label: 'Download',
                      icon: ProgressIcons.download,
                      filled: true,
                      onTap: () => _soon(ProgressScreen.downloadSoon),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ShareButton(
                      key: const Key('share-share'),
                      label: 'Share',
                      icon: ProgressIcons.share,
                      filled: false,
                      onTap: () => _soon(ProgressScreen.shareSoon),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Privacy-first · No personal details shared',
                textAlign: TextAlign.center,
                style: settingsText(
                  10.4,
                  color: const Color(0x80FFFFFF), // 0.5
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// White section card: border 2.5px, radius 1.25rem, shadow 6px, padding
/// 1.25rem.
class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});
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

/// h3 800 1.1rem, -0.02em, + a 20px icon on the right.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.title,
    required this.icon,
    required this.iconColor,
  });
  final String title;
  final List<Path> icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: settingsText(
            17.6,
            weight: FontWeight.w800,
            letterSpacing: -0.02 * 17.6,
          ),
        ),
      ),
      StrokeIcon(paths: icon, size: 20, strokeWidth: 2, color: iconColor),
    ],
  );
}

/// Jigsaw hero card (page.tsx:246-634).
class _JigsawCard extends StatelessWidget {
  const _JigsawCard({
    required this.expanded,
    required this.totalPieces,
    required this.onToggle,
  });

  final bool expanded;
  final int totalPieces;
  final ValueChanged<bool> onToggle;

  static const Duration _transition = Duration(milliseconds: 400);
  static const Curve _spring = Cubic(0.34, 1.56, 0.64, 1);

  /// 25 pieces; none unlocked until a jigsaw data source exists.
  static const int pieceCount = 25;
  static const int filledCount = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const Key('jigsaw-card'),
    behavior: HitTestBehavior.opaque,
    onTap: expanded ? null : () => onToggle(true),
    child: AnimatedScale(
      scale: expanded ? 1.02 : 1,
      duration: _transition,
      curve: _spring,
      // min-height: auto ↔ 480px cannot transition in CSS, so it switches
      // instantly (animating it with the spring curve would overshoot < 0).
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: expanded ? 480 : 0),
        child: AnimatedContainer(
          duration: _transition,
          curve: _spring,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: expanded ? const Color(0xFF1A54B8) : KoiColors.neoBlue,
            border: Border.all(width: 2.5),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                offset: expanded ? const Offset(10, 10) : const Offset(6, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decoration: right/top -1.5rem, 8rem circle; expanded
              // scale(1.5) translate(-20%, 20%).
              Positioned(
                right: -24,
                top: -24,
                child: AnimatedContainer(
                  duration: _transition,
                  curve: Curves.ease,
                  transformAlignment: Alignment.center,
                  transform: expanded
                      ? (Matrix4.identity()
                          ..scaleByDouble(1.5, 1.5, 1, 1)
                          ..translateByDouble(-0.2 * 128, 0.2 * 128, 0, 1))
                      : Matrix4.identity(),
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0x12FFFFFF), // rgba(255,255,255,0.07)
                    border: Border.all(
                      width: 2,
                      color: const Color(0x1AFFFFFF), // 0.1
                    ),
                  ),
                ),
              ),
              AnimatedPadding(
                duration: _transition,
                curve: _spring,
                padding: EdgeInsets.all(expanded ? 32 : 24),
                child: expanded ? _expanded() : _collapsed(),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  static TextStyle get _eyebrow => settingsText(
    12,
    weight: FontWeight.w500,
    color: const Color(0xA6FFFFFF), // rgba(255,255,255,0.65)
    letterSpacing: 0.08 * 12,
  );

  Widget _collapsed() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('Total Pieces Collected'.toUpperCase(), style: _eyebrow),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            StrokeIcon(
              paths: ProgressIcons.puzzle,
              size: 48,
              strokeWidth: 2,
              color: KoiColors.neoWhite,
            ),
            const SizedBox(width: 8),
            Text(
              '$totalPieces',
              key: const Key('jigsaw-total'),
              style: settingsText(
                56,
                weight: FontWeight.w800,
                color: KoiColors.neoWhite,
                height: 1,
                letterSpacing: -0.03 * 56,
              ),
            ),
            const SizedBox(width: 16),
            const _RoundArrow(size: 36, iconSize: 20),
          ],
        ),
      ),
      Text(
        'pieces of your story, preserved',
        style: settingsText(14, color: const Color(0x99FFFFFF)), // 0.6
      ),
    ],
  );

  Widget _expanded() {
    final pct = filledCount / pieceCount * 100;
    return KoiFadeUp(
      spec: const KoiAnimationSpec(duration: Duration(milliseconds: 500)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        "How Far You've Come".toUpperCase(),
                        style: _eyebrow,
                      ),
                    ),
                    Text(
                      'Your Wellness Journey',
                      style: settingsText(
                        24,
                        weight: FontWeight.w700,
                        color: KoiColors.neoWhite,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                key: const Key('jigsaw-collapse'),
                onTap: () => onToggle(false),
                child: const RotatedBox(
                  quarterTurns: 2, // rotate(180deg)
                  child: _RoundArrow(size: 32, iconSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 5x5 grid: gap 6px, bg rgba(0,0,0,0.15), padding 1rem, radius 12,
          // border 2px rgba(255,255,255,0.1); margin-bottom 1rem.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x26000000),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(width: 2, color: const Color(0x1AFFFFFF)),
            ),
            child: Column(
              children: [
                for (var r = 0; r < 5; r++) ...[
                  if (r > 0) const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var c = 0; c < 5; c++) ...[
                        if (c > 0) const SizedBox(width: 6),
                        Expanded(
                          child: KoiFadeUp(
                            // fadeUp 0.4s ease ${i * 0.02}s both
                            spec: KoiAnimationSpec(
                              duration: const Duration(milliseconds: 400),
                              delay: Duration(milliseconds: 20 * (r * 5 + c)),
                            ),
                            child: const _LockedPiece(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0x26FFFFFF), // 0.15
              borderRadius: BorderRadius.circular(8),
              border: Border.all(width: 2, color: const Color(0x33FFFFFF)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Completion Progress',
                        style: settingsText(
                          12,
                          weight: FontWeight.w600,
                          color: const Color(0xCCFFFFFF), // 0.8
                        ),
                      ),
                    ),
                    Text(
                      '${pct.round()}%',
                      style: settingsText(
                        12,
                        weight: FontWeight.w700,
                        color: KoiColors.neoWhite,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 8,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0x33000000),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      width: 1,
                      color: const Color(0x26FFFFFF),
                    ),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: pct / 100,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD100), Color(0xFF2DD36F)],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$filledCount of $pieceCount pieces unlocked · Keep growing '
                  'to reveal more',
                  textAlign: TextAlign.center,
                  style: settingsText(
                    11.2,
                    color: const Color(0x99FFFFFF), // 0.6
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White-translucent circle with the down arrow (rgba(255,255,255,0.2),
/// border 2px rgba(255,255,255,0.3)).
class _RoundArrow extends StatelessWidget {
  const _RoundArrow({required this.size, required this.iconSize});
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0x33FFFFFF),
      border: Border.all(width: 2, color: const Color(0x4DFFFFFF)),
    ),
    child: StrokeIcon(
      paths: ProgressIcons.arrow,
      size: iconSize,
      strokeWidth: 2,
      color: KoiColors.neoWhite,
    ),
  );
}

/// A locked piece: aspect 1, #f0f0f0, border 2px rgba(0,0,0,0.08), radius
/// 6px, lock icon 18px #ccc.
///
/// Unlocked pieces (gradient of the piece colour + a 15% white overlay; web
/// also draws a dicebear image, skipped on mobile) and their hover tooltip
/// are not built: nothing can unlock a piece yet (no jigsaw data source).
class _LockedPiece extends StatelessWidget {
  const _LockedPiece();

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        border: Border.all(width: 2, color: const Color(0x14000000)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: LayoutBuilder(
        // Lock is 18px; scale down if a piece is smaller than that.
        builder: (context, c) => StrokeIcon(
          paths: ProgressIcons.lock,
          size: c.maxWidth < 18 ? c.maxWidth : 18,
          strokeWidth: 2,
          color: const Color(0xFFCCCCCC),
        ),
      ),
    ),
  );
}

/// One stat tile (page.tsx:638-700): white, border 2.5px, radius 1rem,
/// shadow 4px, padding 0.875rem 0.75rem, centred.
class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final List<Path> icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    decoration: BoxDecoration(
      color: KoiColors.neoWhite,
      border: Border.all(width: 2.5),
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [BoxShadow(offset: Offset(4, 4))],
    ),
    child: Column(
      children: [
        StrokeIcon(paths: icon, size: 24, strokeWidth: 2, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          textAlign: TextAlign.center,
          style: settingsText(20.8, weight: FontWeight.w800, height: 1),
        ),
        const SizedBox(height: 2),
        Text(
          unit.toUpperCase(),
          textAlign: TextAlign.center,
          style: settingsText(
            9.92,
            weight: FontWeight.w500,
            color: const Color(0xFFAAAAAA),
            letterSpacing: 0.06 * 9.92,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: settingsText(
            10.88,
            weight: FontWeight.w500,
            color: const Color(0xFF666666),
          ),
        ),
      ],
    ),
  );
}

/// One mood column: bar + day label, gap 0.375rem. Bar height is
/// value/10 of the space above the label (web intends `height: N%`, which
/// browsers resolve to 0 here; see WEB_BUGS). Tap shows the value (web:
/// hover).
class _MoodColumn extends StatelessWidget {
  const _MoodColumn({
    required this.label,
    required this.point,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final MoodPoint? point;
  final bool selected;
  final VoidCallback onTap;

  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final labelStyle = settingsText(
      11.2,
      weight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected ? KoiColors.neoBlack : const Color(0xFF999999),
    );
    final p = point;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: p == null ? null : onTap,
      child: LayoutBuilder(
        builder: (context, c) {
          final labelH =
              (labelStyle.fontSize! * labelStyle.height!) *
              MediaQuery.textScalerOf(context).scale(1);
          final room = (c.maxHeight - labelH - _gap).clamp(0.0, 120.0);
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (p != null) ...[
                if (selected)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: KoiColors.neoBlack,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      p.mood.toStringAsFixed(1),
                      style: settingsText(
                        11.2,
                        weight: FontWeight.w600,
                        color: KoiColors.neoWhite,
                      ),
                    ),
                  ),
                Container(
                  height: (p.mood / 10).clamp(0.0, 1.0) * room,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [p.color, p.color.withAlpha(0xAA)],
                    ),
                    border: Border.all(width: 2),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: _gap),
              Text(label, maxLines: 1, style: labelStyle),
            ],
          );
        },
      ),
    );
  }
}

@immutable
class _Milestone {
  const _Milestone(
    this.id,
    this.title,
    this.desc,
    this.done,
    this.color,
    this.reward,
  );
  final int id;
  final String title;
  final String desc;
  final bool done;
  final Color color;
  final String reward;
}

/// One milestone row (page.tsx:828-916).
class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.milestone,
    required this.last,
    required this.selected,
    required this.onTap,
  });

  final _Milestone milestone;
  final bool last;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = milestone;
    return GestureDetector(
      key: Key('milestone-${m.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: m.done ? 1 : 0.6,
        // padding 0.625rem + margin -0.625rem: the highlight box reaches
        // 10px past the content; its 2px border insets the content by 2px.
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -10,
              top: -10,
              right: -10,
              bottom: -10,
              child: AnimatedContainer(
                key: Key('milestone-${m.id}-highlight'),
                duration: const Duration(milliseconds: 200),
                curve: Curves.ease,
                decoration: BoxDecoration(
                  color: selected ? const Color(0x0A000000) : null, // 0.04
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    width: 2,
                    color: selected
                        ? const Color(0x0F000000) // 0.06
                        : const Color(0x00000000),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      children: [
                        AnimatedScale(
                          scale: selected ? 1.15 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            key: Key('milestone-${m.id}-box'),
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: m.done ? m.color : const Color(0xFFEEEEEE),
                              border: Border.all(width: 2),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: m.done
                                  ? const [BoxShadow(offset: Offset(2, 2))]
                                  : null,
                            ),
                            child: m.done
                                ? StrokeIcon(
                                    paths: ProgressIcons.check,
                                    size: 14,
                                    strokeWidth: 2,
                                    color: KoiColors.neoBlack,
                                  )
                                : Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFFBBBBBB),
                                    ),
                                  ),
                          ),
                        ),
                        // flex 1 0 20px in an unstretched column → 20px.
                        if (!last)
                          Container(
                            width: 2,
                            height: 20,
                            margin: const EdgeInsets.only(top: 4),
                            color: m.done
                                ? const Color(0x26000000) // 0.15
                                : const Color(0xFFEEEEEE),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                m.title,
                                style: settingsText(
                                  14,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              if (m.done)
                                Container(
                                  key: Key('milestone-${m.id}-reward'),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                    horizontal: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: m.color,
                                    border: Border.all(width: 1.5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    m.reward,
                                    style: settingsText(
                                      10,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          m.desc,
                          style: settingsText(
                            12.48,
                            color: const Color(0xFF777777),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Activity heatmap (page.tsx:921-996): 7 rows × 8 columns, gap 3px, square
/// cells, colours by intensity 0–4; legend Less ■■■■■ More. Long-press
/// shows web's `title` ("{n} activities").
class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.heatmap});
  final List<List<int>> heatmap;

  static const List<Color> colors = [
    Color(0xFFF0F0F0),
    Color(0xFFC8E6C9),
    Color(0xFF81C784),
    Color(0xFF4CAF50),
    Color(0xFF2E7D32),
  ];

  Widget _cell(int intensity, {Key? key, double radius = 3}) => Container(
    key: key,
    decoration: BoxDecoration(
      color: colors[intensity],
      border: Border.all(width: 1, color: const Color(0x1A000000)),
      borderRadius: BorderRadius.circular(radius),
    ),
  );

  @override
  Widget build(BuildContext context) => _WhiteCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardHeader(
          title: 'Activity Heatmap',
          icon: ProgressIcons.calendar,
          iconColor: KoiColors.neoBlue,
        ),
        const SizedBox(height: 16),
        for (var row = 0; row < 7; row++) ...[
          if (row > 0) const SizedBox(height: 3),
          Row(
            children: [
              for (var col = 0; col < ProgressStats.weeks; col++) ...[
                if (col > 0) const SizedBox(width: 3),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Builder(
                      builder: (context) {
                        final n = heatmap.isEmpty ? 0 : heatmap[row][col];
                        return Tooltip(
                          message: '$n activities',
                          child: _cell(n, key: Key('heat-$row-$col')),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Less',
              style: settingsText(11.2, color: const Color(0xFF999999)),
            ),
            const Spacer(),
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              SizedBox(width: 12, height: 12, child: _cell(i, radius: 2)),
            ],
            const Spacer(),
            Text(
              'More',
              style: settingsText(11.2, color: const Color(0xFF999999)),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Emotional Growth card (page.tsx:999-1059). Static on web and mobile.
class _EmotionalGrowthCard extends StatelessWidget {
  const _EmotionalGrowthCard();

  // EMOTION_COLORS (page.tsx:17-23)
  static const List<(String, Color)> emotions = [
    ('calm', Color(0xFFA5D6A7)),
    ('happy', Color(0xFFFFD100)),
    ('anxious', Color(0xFFFF8A65)),
    ('sad', Color(0xFF90CAF9)),
    ('growth', Color(0xFF845EC2)),
  ];

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: cssGradient135(const [Color(0xFFA5D6A7), Color(0xFF81C784)]),
      border: Border.all(width: 2.5),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(offset: Offset(6, 6))],
    ),
    child: Stack(
      children: [
        Positioned(
          top: -40,
          right: -40,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x26FFFFFF), // 0.15
              border: Border.all(width: 2, color: const Color(0x33FFFFFF)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  StrokeIcon(
                    paths: ProgressIcons.brain,
                    size: 24,
                    strokeWidth: 2,
                    color: const Color(0xFF1B5E20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Emotional Growth',
                    style: settingsText(
                      16,
                      weight: FontWeight.w800,
                      color: const Color(0xFF1B5E20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (name, color) in emotions)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        border: Border.all(
                          width: 2,
                          color: const Color(0x26000000), // 0.15
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        // text-transform: capitalize
                        name[0].toUpperCase() + name.substring(1),
                        style: settingsText(11.2, weight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Your puzzle reflects your emotional journey — each color '
                "represents a different feeling you've explored.",
                style: settingsText(12, color: const Color(0xFF2E7D32)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Share card number + label: 800 2rem lh 1; 0.7rem rgba(255,255,255,0.6).
class _ShareStat extends StatelessWidget {
  const _ShareStat({
    super.key,
    required this.value,
    required this.label,
    required this.color,
  });
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: settingsText(
          32,
          weight: FontWeight.w800,
          color: color,
          height: 1,
        ),
      ),
      Text(label, style: settingsText(11.2, color: const Color(0x99FFFFFF))),
    ],
  );
}

/// Download (yellow, black border, 3px shadow) / Share (transparent, white
/// border): flex 1, radius 12, padding 0.75rem, 700 0.875rem, gap 0.5rem,
/// icon 18px. Web has no click handlers; mobile shows a "coming soon" toast.
class _ShareButton extends StatelessWidget {
  const _ShareButton({
    super.key,
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final List<Path> icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? KoiColors.neoBlack : KoiColors.neoWhite;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: filled ? KoiColors.neoYellow : null,
            border: Border.all(
              width: 2,
              color: filled ? KoiColors.neoBlack : KoiColors.neoWhite,
            ),
            borderRadius: BorderRadius.circular(12),
            // The yellow button is opaque, so a normal shadow is correct.
            boxShadow: filled ? const [BoxShadow(offset: Offset(3, 3))] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StrokeIcon(paths: icon, size: 18, strokeWidth: 2, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: settingsText(14, weight: FontWeight.w700, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
