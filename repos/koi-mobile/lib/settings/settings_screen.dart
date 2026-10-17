import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../avatar/avatar_providers.dart';
import '../avatar/avatar_state.dart';
import '../onboarding/steps/ai_disclosure_step.dart' show AIDisclosureStep;
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';
import '../chat/widgets/chat_widgets.dart' show StrokeIcon;
import 'export_screen.dart';
import 'import_screen.dart';
import 'privacy_screen.dart';
import 'settings_prefs.dart';
import 'widgets/avatar_picker.dart';
import 'widgets/settings_widgets.dart';

/// Opens a `tel:` URL. Injectable for tests.
typedef TelOpener = Future<void> Function(Uri uri);

/// The Settings tab. Web's /settings/privacy, /export and /import live inside
/// the same (authenticated) layout, so the top nav stays visible; a nested
/// Navigator does the same here, and Android back pops it first.
class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    this.openTel = AIDisclosureStep.defaultOpen,
    this.navigatorKey,
  });
  final TelOpener openTel;

  /// When the shell passes a key, the shell's own back handler pops this
  /// nested navigator first (so back from Privacy goes to Settings, not to
  /// Chat) and this tab installs no handler of its own. Without a key (e.g.
  /// used on its own), the tab handles back itself.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final GlobalKey<NavigatorState> _nav =
      widget.navigatorKey ?? GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator(
      key: _nav,
      onGenerateRoute: (settings) =>
          settingsRoute(SettingsScreen(openTel: widget.openTel)),
    );
    if (widget.navigatorKey != null) return navigator;
    return NavigatorPopHandler(
      onPopWithResult: (_) => _nav.currentState?.maybePop(),
      child: navigator,
    );
  }
}

/// Web route changes are instant (no page transition).
Route<void> settingsRoute(Widget page) => PageRouteBuilder<void>(
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => page,
);

/// Mirrors src/app/(authenticated)/settings/page.tsx.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.openTel = AIDisclosureStep.defaultOpen,
  });
  final TelOpener openTel;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  SettingsPrefs _prefs = const SettingsPrefs();
  ToastMessage? _toast;
  int _toastSeq = 0;
  String? _expandedHelp;

  String? get _uid => ref.read(authServiceProvider).user?.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final prefs = await ref.read(settingsPrefsStoreProvider).load(uid);
      if (mounted) setState(() => _prefs = prefs);
    } catch (e) {
      debugPrint('KOI: settings load failed: $e');
    }
  }

  /// Web only updates React state; mobile also saves (decision 2026-10-13).
  void _update(SettingsPrefs next) {
    setState(() => _prefs = next);
    final uid = _uid;
    if (uid == null) return;
    ref.read(settingsPrefsStoreProvider).save(uid, next).catchError((Object e) {
      debugPrint('KOI: settings save failed: $e');
    });
  }

  void _showToast(String message, ToastType type) =>
      setState(() => _toast = ToastMessage(message, type, ++_toastSeq));

  Future<void> _openAvatarPicker() async {
    final choice = await showAvatarPicker(
      context,
      currentAvatar: _prefs.companion,
      currentName: _prefs.name,
    );
    if (choice == null || !mounted) return;
    // handleAvatarSave
    _update(_prefs.copyWith(companion: choice.companion, name: choice.name));
    _showToast('Companion updated successfully!', ToastType.success);
  }

  /// Mobile-only row (no web equivalent): switches the 3D avatar between
  /// male and female, saved to HiveUser.avatarType, live everywhere.
  void _toggleAvatarType() {
    final next = _prefs.avatarType == AvatarType.male
        ? AvatarType.female
        : AvatarType.male;
    _update(_prefs.copyWith(avatarType: next));
    ref.read(selectedAvatarProvider.notifier).select(next);
    _showToast('Avatar changed to ${avatarTypeLabel(next)}', ToastType.info);
  }

  static String avatarTypeLabel(AvatarType t) =>
      t == AvatarType.female ? 'Female' : 'Male';

  void _toggleLanguage() {
    // handleLanguageToggle: the toast reads the language from BEFORE the
    // toggle.
    final wasEn = _prefs.language == 'en';
    _update(_prefs.copyWith(language: wasEn ? 'ur' : 'en'));
    _showToast(
      wasEn ? 'Language changed to Urdu' : 'Language changed to English',
      ToastType.info,
    );
  }

  void _clearHistory() {
    // handleClearHistory: web only shows the toast and deletes nothing.
    // Mirrored as-is (decision 2026-10-13); see WEB_BUGS_FOUND_DURING_MOBILE.md.
    // TODO(product): clear the local koi_messages box (and Firestore once
    // connected) when the web behaviour is defined.
    _showToast('All conversations cleared', ToastType.success);
  }

  void _toggleNotifications() {
    // handleNotificationToggle: toast reads the value from BEFORE the toggle.
    final wasOn = _prefs.notificationsEnabled;
    _update(_prefs.copyWith(notificationsEnabled: !wasOn));
    _showToast(
      wasOn ? 'Daily check-in disabled' : 'Daily check-in enabled',
      ToastType.info,
    );
  }

  void _push(Widget page) => Navigator.of(context).push(settingsRoute(page));

  void _toggleHelp(String section) =>
      setState(() => _expandedHelp = _expandedHelp == section ? null : section);

  // getAvatarDisplay()
  static String avatarDisplay(String id) =>
      const {'aisha': 'Aisha 👩', 'raza': 'Raza 👨', 'koi': 'Koi 🦊'}[id] ??
      'Koi 🦊';

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: KoiColors.background,
    child: Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            key: const Key('settings-scroll'),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: _content(),
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

  Widget _content() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Text(
          'Settings',
          // 900, 2rem, letter-spacing -0.03em, #000
          style: settingsText(
            32,
            weight: FontWeight.w900,
            letterSpacing: -0.03 * 32,
          ),
        ),
      ),

      const SettingsSectionLabel('Account'),
      SettingsCard(
        child: Column(
          children: [
            SettingsRow(
              key: const Key('row-avatar'),
              icon: '👤',
              label: 'Avatar & Name',
              desc: avatarDisplay(_prefs.companion),
              onTap: _openAvatarPicker,
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const Key('row-avatar-type'),
              icon: '🧍',
              label: 'Avatar',
              desc: avatarTypeLabel(_prefs.avatarType),
              onTap: _toggleAvatarType,
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const Key('row-language'),
              icon: '🌐',
              label: 'Language',
              desc: _prefs.language == 'en' ? 'English' : 'Urdu',
              onTap: _toggleLanguage,
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const Key('row-clear'),
              icon: '🗑',
              label: 'Clear History',
              desc: 'Delete all conversations',
              danger: true,
              onTap: _clearHistory,
            ),
          ],
        ),
      ),

      const SettingsSectionLabel('Notifications'),
      SettingsCard(
        color: KoiColors.neoYellow, // var(--neo-yellow)
        child: Column(
          children: [
            SettingsRow(
              key: const Key('row-checkin'),
              icon: '🔔',
              label: 'Daily Check-in',
              // Web shows this fixed text, not the stored notificationTime.
              desc: _prefs.notificationsEnabled
                  ? 'Every day at 8:00 PM'
                  : 'Disabled',
              toggle: true,
              on: _prefs.notificationsEnabled,
              onTap: _toggleNotifications,
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const Key('row-reminder'),
              icon: '⏰',
              label: 'Reminder Time',
              desc: 'Tap to change',
              onTap: () =>
                  _showToast('Time picker coming soon!', ToastType.info),
            ),
          ],
        ),
      ),

      const SettingsSectionLabel('Privacy'),
      SettingsCard(
        child: Column(
          children: [
            SettingsRow(
              key: const Key('row-encryption'),
              icon: '🔐',
              label: 'Encryption',
              desc: 'AES-256, on-device',
              onTap: () => _push(const PrivacyScreen()),
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const Key('row-data'),
              icon: '👁',
              label: 'Data Collection',
              desc: 'Anonymous only',
              onTap: () => _push(const PrivacyScreen()),
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const Key('row-export'),
              icon: '📤',
              label: 'Export My Data',
              desc: 'Download a copy',
              onTap: () => _push(const ExportScreen()),
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const Key('row-import'),
              icon: '📥',
              label: 'Import Data',
              desc: 'Restore from backup',
              onTap: () => _push(const ImportScreen()),
            ),
          ],
        ),
      ),

      const SettingsSectionLabel('Storage'),
      const SettingsCard(
        padding: EdgeInsets.all(20), // 1.25rem
        child: _StorageCard(),
      ),

      const SettingsSectionLabel('About & Help'),
      SettingsCard(
        bottom: 24, // 1.5rem
        child: Column(
          children: [
            _HelpRow(
              id: 'version',
              icon: 'ℹ️',
              iconColor: KoiColors.neoGray,
              label: 'Version Info',
              desc: 'KOI v1.0.0',
              expanded: _expandedHelp == 'version',
              onTap: _toggleHelp,
              body: const _HelpBody(
                children: [
                  _LabelledLine('Release Date:', ' January 2025', bottom: 8),
                  _LabelledLine('Build:', ' Production', bottom: 8),
                  // settings/page.tsx:439 says "Web App"; mobile says
                  // "Mobile App" (decision 2026-10-13).
                  _LabelledLine('Platform:', ' Mobile App'),
                ],
              ),
            ),
            const SettingsDivider(),
            _HelpRow(
              id: 'whatsnew',
              icon: '✨',
              iconColor: KoiColors.neoYellow,
              label: "What's New",
              desc: 'Latest updates & features',
              expanded: _expandedHelp == 'whatsnew',
              onTap: _toggleHelp,
              body: _HelpBody(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '🎉 v1.0.0 Release',
                      style: _HelpBody.style.copyWith(
                        fontWeight: FontWeight.w600,
                        color: KoiColors.neoBlack,
                      ),
                    ),
                  ),
                  SettingsPlainList(
                    itemGap: 8,
                    style: _HelpBody.style,
                    items: const [
                      'Enhanced avatar animations',
                      'Improved offline support',
                      'New privacy controls',
                      'Performance optimizations',
                    ],
                  ),
                ],
              ),
            ),
            const SettingsDivider(),
            _HelpRow(
              id: 'crisis',
              icon: '🆘',
              iconColor: const Color(0xFFFF4A60),
              label: 'Crisis Resources',
              desc: '24/7 helplines (Pakistan)',
              expanded: _expandedHelp == 'crisis',
              onTap: _toggleHelp,
              body: _HelpBody(
                children: [
                  // page.tsx lists the same three helplines, names, numbers
                  // and tel: hrefs as AIDisclosureStep.tsx.
                  for (final (i, h) in AIDisclosureStep.helplines.indexed)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i < AIDisclosureStep.helplines.length - 1
                            ? 12
                            : 0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              h.name,
                              style: _HelpBody.style.copyWith(
                                fontWeight: FontWeight.w600,
                                color: KoiColors.neoBlack,
                              ),
                            ),
                          ),
                          Semantics(
                            link: true,
                            child: GestureDetector(
                              key: Key('tel-${h.href}'),
                              onTap: () => widget.openTel(Uri.parse(h.href)),
                              child: Text(
                                h.tel,
                                style: _HelpBody.style.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFFF4A60),
                                ),
                              ),
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

      const _AppInfo(),

      // Developer-only: web Settings has no sign-out. Kept so the temporary
      // debug sign-in can be reset on device. TODO(Q1, firebase): remove or
      // replace once the real AuthService exists.
      if (kDebugMode)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Center(
            child: NeoButton(
              key: const Key('debug-sign-out'),
              variant: NeoButtonVariant.ghost,
              onPressed: () => ref.read(authServiceProvider).signOut(),
              child: const Text('Sign out (debug)'), // developer label
            ),
          ),
        ),
    ],
  );
}

/// page.tsx Storage card. Values are hardcoded on web ("1%", "42 KB of 5 MB
/// used") and mirrored as-is (decision 2026-10-13).
class _StorageCard extends StatelessWidget {
  const _StorageCard();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 80,
        height: 80,
        child: CustomPaint(
          painter: const _StorageRingPainter(),
          child: Center(
            child: Text(
              '1%',
              style: settingsText(20, weight: FontWeight.w900, height: 1),
            ),
          ),
        ),
      ),
      const SizedBox(width: 16), // gap 1rem
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Local Storage',
                style: settingsText(15.2, weight: FontWeight.w700),
              ),
            ),
            Text(
              '42 KB of 5 MB used',
              style: settingsText(12.8, color: const Color(0xFF666666)),
            ),
            const SizedBox(height: 12), // marginTop 0.75rem
            Container(
              height: 6,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(width: 1, color: const Color(0xFFDDDDDD)),
              ),
              child: const FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.01, // width: 1%
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF2D63EB), Color(0xFF06B6D4)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// The SVG ring: r=32, stroke 8, track #F0F0F0, arc #2D63EB with round caps,
/// rotated -90deg. Web's strokeDasharray is "2.01π·32 200.96π·32"; the dash
/// (≈202.1) is longer than the circumference (2π·32 ≈ 201.1), so the browser
/// draws a FULL blue ring despite the "1%" label. Mirrored as rendered.
class _StorageRingPainter extends CustomPainter {
  const _StorageRingPainter();

  static const double r = 32;
  static const double dash = 2.01 * math.pi * r;
  static const double circumference = 2 * math.pi * r;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(c, r, stroke..color = const Color(0xFFF0F0F0));
    final sweep = math.min(dash, circumference) / r;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      sweep,
      false,
      stroke
        ..color = const Color(0xFF2D63EB)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_StorageRingPainter old) => false;
}

/// One About & Help row (page.tsx inline `<button>` + max-height panel).
class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.id,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.desc,
    required this.expanded,
    required this.onTap,
    required this.body,
  });

  final String id;
  final String icon;
  final Color iconColor;
  final String label;
  final String desc;
  final bool expanded;
  final ValueChanged<String> onTap;
  final Widget body;

  static const Duration _transition = Duration(milliseconds: 300); // 0.3s

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        button: true,
        expanded: expanded,
        child: GestureDetector(
          key: Key('help-$id'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                SettingsIconTile(icon, color: iconColor),
                const SizedBox(width: 14),
                Expanded(
                  child: SettingsRowText(label: label, desc: desc),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: _transition,
                  curve: Curves.ease,
                  child: StrokeIcon(
                    paths: chevronDownPaths,
                    size: 18,
                    strokeWidth: 2,
                    color: const Color(0xFFCCCCCC),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // max-height 0 → 200/300px, overflow hidden, 0.3s ease
      ClipRect(
        child: AnimatedAlign(
          key: Key('help-$id-body'),
          alignment: Alignment.topCenter,
          heightFactor: expanded ? 1 : 0,
          duration: _transition,
          curve: Curves.ease,
          child: body,
        ),
      ),
    ],
  );
}

/// Expanded panel: padding 0 0 1rem 3.375rem; 0.85rem, #666, line-height 1.6.
class _HelpBody extends StatelessWidget {
  const _HelpBody({required this.children});
  final List<Widget> children;

  static TextStyle get style =>
      settingsText(13.6, color: const Color(0xFF666666), height: 1.6);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 54, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

/// `<p><strong>Label</strong> value</p>`.
class _LabelledLine extends StatelessWidget {
  const _LabelledLine(this.label, this.value, {this.bottom = 0});
  final String label;
  final String value;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottom),
    child: Text.rich(
      TextSpan(
        children: [
          // <strong>: font-weight bolder → 700
          TextSpan(
            text: label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
      style: _HelpBody.style,
    ),
  );
}

/// page.tsx "App info" footer.
class _AppInfo extends StatelessWidget {
  const _AppInfo();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24), // paddingBottom 1.5rem
    child: Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(width: 2, color: const Color(0xFFE5E5E5)),
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: KoiColors.neoBlue,
                  border: Border.all(width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'K',
                  style: settingsText(
                    12,
                    weight: FontWeight.w800,
                    color: KoiColors.neoWhite,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('KOI', style: settingsText(12.8, weight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text(
                'v1.0.0',
                style: settingsText(12.48, color: const Color(0xFFBBBBBB)),
              ),
            ],
          ),
        ),
        Text(
          'Made with care · Private by design',
          style: settingsText(12, color: const Color(0xFFCCCCCC)),
        ),
      ],
    ),
  );
}
