import 'dart:async';

import 'package:flutter/material.dart';

import '../chat/widgets/chat_widgets.dart' show StrokeIcon;
import '../shell/svg_path.dart';
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';
import 'widgets/settings_widgets.dart';

/// Mirrors src/app/(authenticated)/settings/export/page.tsx.
///
/// Web: a simulated progress bar (+2% every 50ms), then after 5.1s
/// html2pdf.js renders a report built from HARDCODED sample data (no real
/// user data, no encryption) and "Download PDF Now" saves it through a
/// browser Blob + `<a download>`. Decision 2026-10-13: mobile mirrors the
/// page, progress and "Report Ready!" state, but creates no file (no PDF /
/// file-sharing package approved); the download button shows a toast.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  /// Mobile-only toast text (there is no web equivalent; see report).
  static const String downloadUnavailable = 'PDF download coming soon!';

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _isExporting = false;
  double _progress = 0;
  bool _exportComplete = false;
  Timer? _progressTimer;
  Timer? _doneTimer;
  ToastMessage? _toast;
  int _toastSeq = 0;

  @override
  void dispose() {
    _progressTimer?.cancel();
    _doneTimer?.cancel();
    super.dispose();
  }

  void _generate() {
    setState(() {
      _isExporting = true;
      _progress = 0;
      _exportComplete = false;
    });
    // setInterval(+2, 50ms) until 100
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (_progress >= 100) {
        t.cancel();
        return;
      }
      setState(() => _progress += 2);
    });
    // setTimeout(..., 5100): web builds the PDF here.
    // TODO(product): build a real report once real data and a PDF/share
    // package are approved.
    _doneTimer = Timer(const Duration(milliseconds: 5100), () {
      setState(() {
        _isExporting = false;
        _exportComplete = true;
      });
    });
  }

  void _download() => setState(
    () => _toast = ToastMessage(
      ExportScreen.downloadUnavailable,
      ToastType.info,
      ++_toastSeq,
    ),
  );

  String get _stage {
    final p = _progress;
    if (p < 20) return '📊 Analyzing mood patterns...';
    if (p < 40) return '💭 Extracting conversation themes...';
    if (p < 60) return '💙 Calculating loneliness trends...';
    if (p < 80) return '🎯 Compiling activity data...';
    if (p < 95) return '✨ Designing your report...';
    return '🎉 Almost ready!';
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: KoiColors.background,
    child: Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            key: const Key('export-scroll'),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BackToSettingsButton(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Export Wellness Report',
                          style: settingsText(
                            32,
                            weight: FontWeight.w900,
                            letterSpacing: -0.03 * 32,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: Text(
                          'Download your complete wellness journey as a '
                          'beautifully formatted PDF',
                          style: settingsText(
                            15.2,
                            color: const Color(0xFF666666),
                          ),
                        ),
                      ),
                      _previewCard(),
                      const SizedBox(height: 32),
                      const _PrivacyInfo(),
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

  static const List<(String, String)> _includes = [
    ('Mood Trends', 'Visual charts & progression'),
    ('Loneliness Tracking', 'Connection scores over time'),
    ('Conversation Themes', 'What you talked about most'),
    ('Activity Progress', 'Check-ins, streaks, messages'),
    ('Crisis Support Log', 'Times KOI helped in crisis'),
    ('Key Insights', 'Personalized observations'),
  ];

  Widget _previewCard() => Container(
    padding: const EdgeInsets.all(32), // 2rem
    decoration: BoxDecoration(
      color: KoiColors.neoWhite,
      border: Border.all(width: 2.5),
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [BoxShadow(offset: Offset(6, 6))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: cssGradient135(const [
                  Color(0xFF2D63EB),
                  Color(0xFF06B6D4),
                ]),
                border: Border.all(width: 3),
                borderRadius: BorderRadius.circular(16),
                // 4px 4px 0 rgba(0,0,0,0.2); 0.2 * 255 = 51 = 0x33
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), offset: Offset(4, 4)),
                ],
              ),
              child: StrokeIcon(
                paths: reportIconPaths,
                size: 32,
                strokeWidth: 2,
                color: KoiColors.neoWhite,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Wellness Report',
                      style: settingsText(17.6, weight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    'Your complete mental health journey',
                    style: settingsText(13.6, color: const Color(0xFF666666)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9F9),
            border: Border.all(width: 2, color: const Color(0xFFE5E5E5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Report Includes',
                  style: settingsText(14.4, weight: FontWeight.w700),
                ),
              ),
              for (final (i, (label, desc)) in _includes.indexed) ...[
                if (i > 0) const SizedBox(height: 8), // gap 0.5rem
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '• $label',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: ' - $desc',
                        style: const TextStyle(color: Color(0xFF999999)),
                      ),
                    ],
                  ),
                  style: settingsText(13.6),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (!_isExporting && !_exportComplete)
          NeoButton(
            key: const Key('export-generate'),
            fullWidth: true,
            onPressed: _generate,
            child: const FitButtonLabel('Generate Wellness Report ✦'),
          ),
        if (_isExporting) _progressView(),
        if (_exportComplete) _completeView(),
      ],
    ),
  );

  Widget _progressView() => Column(
    key: const Key('export-progress'),
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _stage,
                      style: settingsText(13.6, weight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${_progress.round()}%',
                    style: settingsText(
                      20,
                      weight: FontWeight.w900,
                      color: const Color(0xFF2D63EB),
                    ),
                  ),
                ],
              ),
            ),
            _ProgressBar(progress: _progress),
          ],
        ),
      ),
      // 2.5rem fox, bounce 0.6s ease-in-out infinite (Koi companion icon;
      // Q7 only dropped the fox user avatar).
      const _Bounce(child: Text('🦊', style: TextStyle(fontSize: 40))),
    ],
  );

  Widget _completeView() => Column(
    key: const Key('export-complete'),
    children: [
      const _PopIn(
        child: Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text('✅', style: TextStyle(fontSize: 64, height: 1.5)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Report Ready!',
          style: settingsText(19.2, weight: FontWeight.w800),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Text(
          'Your wellness report is ready to download',
          textAlign: TextAlign.center,
          style: settingsText(14.4, color: const Color(0xFF666666)),
        ),
      ),
      _Heartbeat(
        child: NeoButton(
          key: const Key('export-download'),
          fullWidth: true,
          onPressed: _download,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StrokeIcon(
                paths: downloadIconPaths,
                size: 20,
                strokeWidth: 2,
                color: KoiColors.neoWhite, // currentColor
              ),
              const SizedBox(width: 8),
              const Text('Download PDF Now'),
            ],
          ),
        ),
      ),
    ],
  );
}

// Preview icon: rect x3 y3 18x18 rx2; lines (3,9)-(21,9) and (9,21)-(9,9).
final List<Path> reportIconPaths = [
  Path()..addRRect(RRect.fromLTRBR(3, 3, 21, 21, const Radius.circular(2))),
  parseSvgPath('M3 9L21 9'),
  parseSvgPath('M9 21L9 9'),
];

// Download icon: path + polyline "7 10 12 15 17 10" + line (12,15)-(12,3).
final List<Path> downloadIconPaths = [
  parseSvgPath('M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4'),
  parseSvgPolyline('7 10 12 15 17 10'),
  parseSvgPath('M12 15L12 3'),
];

/// Bar: height 12px, #F0F0F0, radius 6px, border 2px #000; fill
/// linear-gradient(90deg, #2D63EB, #06b6d4 50%, #FFD100) at width
/// progress%, with a shimmer (transparent → rgba(255,255,255,0.4) →
/// transparent) sweeping left -100% → 100% every 1s.
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.progress});
  final double progress;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 12,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFFF0F0F0),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(width: 2),
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: AnimatedFractionallySizedBox(
        duration: const Duration(milliseconds: 100), // width 0.1s ease
        curve: Curves.ease,
        widthFactor: (widget.progress / 100).clamp(0.0, 1.0),
        heightFactor: 1,
        child: ClipRect(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF2D63EB),
                  Color(0xFF06B6D4),
                  Color(0xFFFFD100),
                ],
                stops: [0, 0.5, 1],
              ),
            ),
            child: AnimatedBuilder(
              animation: _shimmer,
              builder: (context, _) => FractionalTranslation(
                // CSS ease (default timing) from left -100% to 100%
                translation: Offset(
                  -1 + 2 * Curves.ease.transform(_shimmer.value),
                  0,
                ),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0x66FFFFFF), // 0.4 * 255 = 102 = 0x66
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// bounce: 0%,100% translateY(0); 50% translateY(-10px); 0.6s ease-in-out
/// infinite.
class _Bounce extends StatefulWidget {
  const _Bounce({required this.child});
  final Widget child;

  @override
  State<_Bounce> createState() => _BounceState();
}

class _BounceState extends State<_Bounce> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat();

  static final Animatable<double> _dy = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: -10.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: -10.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 50,
    ),
  ]);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) =>
        Transform.translate(offset: Offset(0, _dy.evaluate(_c)), child: child),
    child: widget.child,
  );
}

/// popIn 0.5s cubic-bezier(0.34, 1.56, 0.64, 1): opacity 0 → 1,
/// scale 0.5 → 1.
class _PopIn extends StatefulWidget {
  const _PopIn({required this.child});
  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..forward();

  static const Curve _curve = Cubic(0.34, 1.56, 0.64, 1);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      final p = _curve.transform(_c.value);
      return Opacity(
        opacity: p.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.5 + 0.5 * p, child: child),
      );
    },
    child: widget.child,
  );
}

/// heartbeat 7s ease-in-out infinite: scale 1 → 1.08 → 1 → 1.08 → 1 over
/// 0–28%, then rest.
class _Heartbeat extends StatefulWidget {
  const _Heartbeat({required this.child});
  final Widget child;

  @override
  State<_Heartbeat> createState() => _HeartbeatState();
}

class _HeartbeatState extends State<_Heartbeat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  static TweenSequenceItem<double> _seg(double a, double b, double w) =>
      TweenSequenceItem(
        tween: Tween(
          begin: a,
          end: b,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: w,
      );

  static final Animatable<double> _scale = TweenSequence<double>([
    _seg(1, 1.08, 7),
    _seg(1.08, 1, 7),
    _seg(1, 1.08, 7),
    _seg(1.08, 1, 7),
    _seg(1, 1, 72),
  ]);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) =>
        Transform.scale(scale: _scale.evaluate(_c), child: child),
    child: widget.child,
  );
}

/// Info card: var(--neo-yellow), border 2.5px, radius 1.25rem, shadow 4px,
/// padding 1.25rem.
class _PrivacyInfo extends StatelessWidget {
  const _PrivacyInfo();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: KoiColors.neoYellow,
      border: Border.all(width: 2.5),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(offset: Offset(4, 4))],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('💡', style: TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Your Privacy Matters',
                  style: settingsText(14.4, weight: FontWeight.w700),
                ),
              ),
              SettingsPlainList(
                style: settingsText(
                  13.6,
                  color: const Color(0xFF333333),
                  height: 1.7,
                ),
                items: const [
                  'Report generated locally on your device',
                  'All data remains encrypted',
                  'No personal information shared',
                  'Download & keep forever',
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
