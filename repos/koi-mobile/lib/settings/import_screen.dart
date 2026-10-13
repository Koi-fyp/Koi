import 'package:flutter/material.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_motion.dart';
import 'widgets/settings_widgets.dart';

/// Mirrors src/app/(authenticated)/settings/import/page.tsx, a static
/// "Coming Soon" page (no file handling on web either).
///
/// The feature cards set inline `opacity: 0.6`, but their `fadeUp ... both`
/// animation ends at `opacity: 1` and keeps it (CSS animations override
/// inline styles), so web shows them fully opaque. Mobile mirrors what web
/// renders (see WEB_BUGS_FOUND_DURING_MOBILE.md).
class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  static KoiAnimationSpec _fadeUp(int delayMs) => KoiAnimationSpec(
    duration: const Duration(milliseconds: 600), // fadeUp 0.6s ease both
    delay: Duration(milliseconds: delayMs),
  );

  static const List<(String, String, String, Color, int)> _features = [
    (
      '📄',
      'PDF Import',
      'Upload exported PDFs and extract your conversations',
      Color(0xFFE3F2FD),
      400,
    ),
    (
      '📊',
      'JSON Import',
      'Restore complete conversation data from JSON backups',
      Color(0xFFF3E5F5),
      500,
    ),
    (
      '🎯',
      'Smart Conflict Resolution',
      'Intelligently merge imported data with existing conversations',
      Color(0xFFFFF9C4),
      600,
    ),
    (
      '✓',
      'Preview Before Import',
      'Review and validate data before adding to your library',
      Color(0xFFE8F5E9),
      700,
    ),
  ];

  @override
  Widget build(BuildContext context) => DecoratedBox(
    // linear-gradient(135deg, #F9F9F9 0%, #FAFAFA 100%), minHeight 100vh
    decoration: BoxDecoration(
      gradient: cssGradient135(const [Color(0xFFF9F9F9), Color(0xFFFAFAFA)]),
    ),
    child: SingleChildScrollView(
      key: const Key('import-scroll'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BackToSettingsButton(),
                KoiFadeUp(spec: _fadeUp(0), child: _hero()),
                for (final (i, f) in _features.indexed) ...[
                  if (i > 0) const SizedBox(height: 16), // gap 1rem
                  KoiFadeUp(spec: _fadeUp(f.$5), child: _featureCard(f)),
                ],
                const SizedBox(height: 32), // marginBottom 2rem
                KoiFadeUp(spec: _fadeUp(800), child: _notifyCard()),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _hero() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
    child: Column(
      children: [
        // 5rem, floatY 3s ease-in-out infinite, grayscale(0.3), mb 1.5rem
        const KoiFloatY(
          spec: KoiAnimationSpec(duration: Duration(seconds: 3), repeat: true),
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(_grayscale03),
            child: Text('📥', style: TextStyle(fontSize: 80, height: 1.5)),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Import Data',
            textAlign: TextAlign.center,
            // 900, 2.5rem, letter-spacing -0.03em, line-height 1.1
            style: settingsText(
              40,
              weight: FontWeight.w900,
              letterSpacing: -0.03 * 40,
              height: 1.1,
            ),
          ),
        ),
        KoiFadeUp(
          spec: _fadeUp(200),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
            decoration: BoxDecoration(
              color: KoiColors.neoYellow,
              border: Border.all(width: 2.5),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(offset: Offset(3, 3))],
            ),
            child: Text(
              '✨ Coming Soon',
              style: settingsText(14.4, weight: FontWeight.w800),
            ),
          ),
        ),
        KoiFadeUp(
          spec: _fadeUp(300),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              "We're building a beautiful way to restore your conversations "
              'from PDF and JSON backups.',
              textAlign: TextAlign.center,
              style: settingsText(
                16,
                color: const Color(0xFF666666),
                height: 1.7,
              ),
            ),
          ),
        ),
        // the paragraph's margin-bottom 2rem
        const SizedBox(height: 32),
      ],
    ),
  );

  Widget _featureCard((String, String, String, Color, int) f) {
    final (icon, title, desc, color, _) = f;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KoiColors.neoWhite,
        border: Border.all(width: 2.5),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(offset: Offset(4, 4))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(icon, style: const TextStyle(fontSize: 28, height: 1)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    title,
                    style: settingsText(
                      16,
                      weight: FontWeight.w800,
                      color: const Color(0xFF333333),
                    ),
                  ),
                ),
                Text(
                  desc,
                  style: settingsText(13.6, color: const Color(0xFF999999)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notifyCard() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: cssGradient135(const [Color(0xFF2D63EB), Color(0xFF06B6D4)]),
      border: Border.all(width: 2.5),
      borderRadius: BorderRadius.circular(24),
      // 6px 6px 0 rgba(0,0,0,0.3); 0.3 * 255 ≈ 77 = 0x4D
      boxShadow: const [
        BoxShadow(color: Color(0x4D000000), offset: Offset(6, 6)),
      ],
    ),
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('🔔', style: TextStyle(fontSize: 32)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Get Notified',
            style: settingsText(
              17.6,
              weight: FontWeight.w800,
              color: KoiColors.neoWhite,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Opacity(
            opacity: 0.9,
            child: Text(
              "We'll let you know as soon as import functionality is ready. "
              'Stay tuned!',
              textAlign: TextAlign.center,
              style: settingsText(13.6, color: KoiColors.neoWhite, height: 1.6),
            ),
          ),
        ),
        // <button disabled>
        Semantics(
          button: true,
          enabled: false,
          child: Container(
            key: const Key('import-notify'),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF), // rgba(255,255,255,0.2)
              border: Border.all(
                width: 2,
                color: const Color(0x66FFFFFF), // rgba(255,255,255,0.4)
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Notify Me (Coming Soon)',
              textAlign: TextAlign.center,
              style: settingsText(
                14.4,
                weight: FontWeight.w700,
                color: const Color(0x99FFFFFF), // rgba(255,255,255,0.6)
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// CSS `filter: grayscale(0.3)` (Filter Effects spec matrix, amount 0.3).
const List<double> _grayscale03 = [
  0.2126 + 0.7874 * 0.7,
  0.7152 - 0.7152 * 0.7,
  0.0722 - 0.0722 * 0.7,
  0,
  0,
  0.2126 - 0.2126 * 0.7,
  0.7152 + 0.2848 * 0.7,
  0.0722 - 0.0722 * 0.7,
  0,
  0,
  0.2126 - 0.2126 * 0.7,
  0.7152 - 0.7152 * 0.7,
  0.0722 + 0.9278 * 0.7,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];
