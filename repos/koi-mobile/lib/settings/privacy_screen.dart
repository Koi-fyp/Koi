import 'package:flutter/material.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_motion.dart';
import '../theme/koi_text.dart';
import 'widgets/settings_widgets.dart';

/// Mirrors src/app/(authenticated)/settings/privacy/page.tsx.
///
/// Web moves each block by `scrollY * speed` (parallax, 0.1s transition);
/// mobile applies the same offsets from the page's scroll position.
/// "Recent Activity" is a hardcoded list on web and "Delete My Account" has
/// no handler; both are mirrored as-is (decision 2026-10-13).
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// getParallaxStyle(speed): translateY(scrollY * speed).
  Widget _parallax(double speed, Widget child) => AnimatedBuilder(
    animation: _scroll,
    builder: (context, child) => Transform.translate(
      offset: Offset(0, (_scroll.hasClients ? _scroll.offset : 0) * speed),
      child: child,
    ),
    child: child,
  );

  static TextStyle h3({Color color = KoiColors.neoBlack}) =>
      settingsText(17.6, weight: FontWeight.w800, color: color); // 1.1rem

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFFAFAFA), // minHeight 100vh, background #FAFAFA
    child: SingleChildScrollView(
      key: const Key('privacy-scroll'),
      controller: _scroll,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BackToSettingsButton(),
                _parallax(0.05, _hero()),
                const SizedBox(height: 32),
                _parallax(0.02, _encryptionCard()),
                const SizedBox(height: 24),
                _parallax(0.03, _dataBreakdown()),
                const SizedBox(height: 24),
                _parallax(0.01, _auditLog()),
                const SizedBox(height: 24),
                _parallax(0.015, _dangerZone()),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _hero() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 3rem, floatY 3s ease-in-out infinite, margin-bottom 1rem
      const KoiFloatY(
        spec: KoiAnimationSpec(duration: Duration(seconds: 3), repeat: true),
        child: Text('🔐', style: TextStyle(fontSize: 48, height: 1.5)),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Privacy Center',
          // 900, 2.25rem, letter-spacing -0.03em, line-height 1.2
          style: settingsText(
            36,
            weight: FontWeight.w900,
            letterSpacing: -0.03 * 36,
            height: 1.2,
          ),
        ),
      ),
      Text(
        "Your data, your control. Here's everything we do to keep your "
        'conversations private.',
        style: settingsText(15.2, color: const Color(0xFF666666), height: 1.6),
      ),
    ],
  );

  /// Shared card: #fff, border 2.5px, radius 1.5rem, shadow 6px, padding
  /// 1.5rem.
  Widget _card({required Widget child, Key? key}) => Container(
    key: key,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: KoiColors.neoWhite,
      border: Border.all(width: 2.5),
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [BoxShadow(offset: Offset(6, 6))],
    ),
    child: child,
  );

  Widget _encryptionCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2DD36F),
                border: Border.all(width: 2.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('✓', style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('Encryption Active', style: h3()),
                  ),
                  Text(
                    'AES-256 • Military-grade',
                    style: settingsText(13.6, color: const Color(0xFF666666)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20), // marginBottom 1.25rem
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9F9),
            border: Border.all(width: 2, color: const Color(0xFFE5E5E5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'All your conversations are encrypted on your device before '
            'being stored. Not even we can read them — your data stays '
            'completely private.',
            style: settingsText(
              13.6,
              color: const Color(0xFF333333),
              height: 1.6,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _dataBreakdown() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text('📊 What We Store', style: h3()),
        ),
        const _StoreBox(
          gradient: [Color(0xFFE3F2FD), Color(0xFFF3E5F5)],
          title: '📱 On Your Device',
          badge: 'Encrypted',
          badgeColor: Color(0xFF2D63EB),
          badgeText: KoiColors.neoWhite,
          items: [
            'All conversation messages',
            'Your preferences & settings',
            'Avatar choice',
          ],
        ),
        const SizedBox(height: 16), // gap 1rem
        const _StoreBox(
          gradient: [Color(0xFFFFF9C4), Color(0xFFFFE0B2)],
          title: '☁️ Cloud (Optional)',
          badge: 'Anonymous',
          badgeColor: Color(0xFFFFD100),
          badgeText: KoiColors.neoBlack,
          items: [
            'Session ID only (no personal info)',
            'Usage statistics',
            'Crash reports',
          ],
        ),
        const SizedBox(height: 16),
        const _StoreBox(
          gradient: [Color(0xFFFFEBEE), Color(0xFFFCE4EC)],
          title: '🚫 Never Stored',
          badge: 'Protected',
          badgeColor: Color(0xFFFF4A60),
          badgeText: KoiColors.neoWhite,
          items: [
            'Your real name or email',
            'Location data',
            'Payment information',
            'Shared with third parties',
          ],
        ),
      ],
    ),
  );

  static const List<(String, String, String)> _activity = [
    ('Conversation saved', '2 minutes ago', '💬'),
    ('Settings updated', '1 hour ago', '⚙️'),
    ('Data synced', '3 hours ago', '🔄'),
    ('Avatar changed', 'Yesterday', '👤'),
  ];

  Widget _auditLog() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text('📝 Recent Activity', style: h3()),
        ),
        for (final (i, (action, time, icon)) in _activity.indexed) ...[
          if (i > 0) const SizedBox(height: 12), // gap 0.75rem
          // slideRight 0.3s ease ${i * 0.1}s both
          KoiSlideRight(
            spec: KoiAnimationSpec(
              duration: const Duration(milliseconds: 300),
              delay: Duration(milliseconds: 100 * i),
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F9F9),
                border: Border.all(width: 1.5, color: const Color(0xFFE5E5E5)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2.4),
                          child: Text(
                            action,
                            style: settingsText(13.6, weight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          time,
                          style: settingsText(
                            12,
                            color: const Color(0xFF999999),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _dangerZone() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: cssGradient135(const [Color(0xFFFFEBEE), Color(0xFFFCE4EC)]),
      border: Border.all(width: 2.5, color: KoiColors.danger),
      borderRadius: BorderRadius.circular(24),
      // 6px 6px 0 rgba(255, 65, 54, 0.3); 0.3 * 255 ≈ 77 = 0x4D
      boxShadow: const [
        BoxShadow(color: Color(0x4DFF4136), offset: Offset(6, 6)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Danger Zone',
                      style: h3(color: KoiColors.danger),
                    ),
                  ),
                  Text(
                    'Deleting your account will permanently remove all your '
                    'data from our servers. This action cannot be undone.',
                    style: settingsText(
                      13.6,
                      color: const Color(0xFF666666),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _DeleteAccountButton(),
      ],
    ),
  );
}

/// One "What We Store" box: padding 1rem, 135deg gradient, border 2px #000,
/// radius 12px; header row (700 0.9rem + badge), then the list
/// (0.8rem, #333, line-height 1.6, padding-left 1.25rem).
class _StoreBox extends StatelessWidget {
  const _StoreBox({
    required this.gradient,
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.badgeText,
    required this.items,
  });

  final List<Color> gradient;
  final String title;
  final String badge;
  final Color badgeColor;
  final Color badgeText;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: cssGradient135(gradient),
      border: Border.all(width: 2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: settingsText(14.4, weight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(width: 1.5),
              ),
              child: Text(
                badge,
                style: settingsText(
                  12,
                  weight: FontWeight.w700,
                  color: badgeText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SettingsPlainList(
          items: items,
          style: settingsText(
            12.8,
            color: const Color(0xFF333333),
            height: 1.6,
          ),
        ),
      ],
    ),
  );
}

/// "Delete My Account": .neo-btn-ghost with inline border/colour #FF4136 and
/// box-shadow 0 3px 0 0 #FF4136 (the inline shadow also wins over :active,
/// so only the translateY(2px) press remains). Web has no onClick.
class _DeleteAccountButton extends StatefulWidget {
  const _DeleteAccountButton();

  @override
  State<_DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends State<_DeleteAccountButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      key: const Key('delete-account'),
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      // TODO(firebase): web has no handler. Account deletion needs the real
      // AuthService + Firestore; wire it when the web behaviour exists.
      onTap: () {},
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100), // 0.1s ease
        curve: Curves.ease,
        transform: Matrix4.translationValues(0, _down ? 2 : 0, 0),
        child: CustomPaint(
          // background: transparent, so the shadow must only be painted
          // OUTSIDE the button (CSS box-shadow never shows through it).
          painter: const _OuterStadiumShadow(KoiColors.danger, Offset(0, 3)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
            alignment: Alignment.center,
            decoration: const ShapeDecoration(
              shape: StadiumBorder(
                side: BorderSide(width: 2.5, color: KoiColors.danger),
              ),
            ),
            // .neo-btn-*: display font, 700, 1rem, nowrap
            child: Text(
              'Delete My Account',
              softWrap: false,
              style: KoiText.display(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KoiColors.danger,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A zero-blur stadium shadow painted only where it sticks out from under
/// the (transparent) button.
class _OuterStadiumShadow extends CustomPainter {
  const _OuterStadiumShadow(this.color, this.offset);
  final Color color;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final box = RRect.fromRectAndRadius(Offset.zero & size, r);
    final shadow = Path.combine(
      PathOperation.difference,
      Path()..addRRect(box.shift(offset)),
      Path()..addRRect(box),
    );
    canvas.drawPath(shadow, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OuterStadiumShadow old) =>
      old.color != color || old.offset != offset;
}
