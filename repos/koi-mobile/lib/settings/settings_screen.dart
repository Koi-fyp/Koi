import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_version.dart';
import '../app/providers.dart';
import '../avatar/avatar_providers.dart';
import '../avatar/avatar_source.dart';
import '../onboarding/steps/ai_disclosure_step.dart' show AIDisclosureStep;
import '../safety/safety_debug_menu.dart';
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';
import '../chat/widgets/chat_widgets.dart' show StrokeIcon;
import 'export_screen.dart';
import 'import_screen.dart';
import 'privacy_screen.dart';
import 'settings_prefs.dart';
import 'storage_usage.dart';
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
    this.now = DateTime.now,
  });
  final TelOpener openTel;

  /// Device clock for the reminder status line. Injectable for tests.
  final DateTime Function() now;

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
      onGenerateRoute: (settings) => settingsRoute(
        SettingsScreen(openTel: widget.openTel, now: widget.now),
      ),
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
    this.now = DateTime.now,
  });
  final TelOpener openTel;
  final DateTime Function() now;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  SettingsPrefs _prefs = const SettingsPrefs();

  /// Web avatarPreference.status === 'ready': the saved prefs are loaded.
  bool _loaded = false;
  bool _saving = false;
  late DateTime _now = widget.now();
  Timer? _clock;
  ToastMessage? _toast;
  int _toastSeq = 0;
  String? _expandedHelp;

  String? get _uid => ref.read(authServiceProvider).user?.uid;

  /// settings/page.tsx:33 preferenceDisabled.
  bool get _preferenceDisabled => !_loaded || _saving;

  @override
  void initState() {
    super.initState();
    _load();
    // page.tsx:32: the status line re-reads the clock every minute.
    _clock = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() => _now = widget.now()),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final prefs = await ref.read(settingsPrefsStoreProvider).load(uid);
      if (mounted) {
        setState(() {
          _prefs = prefs;
          _loaded = true;
        });
      }
    } catch (e) {
      // Stays not loaded, so the preference rows stay disabled (web status
      // 'error').
      debugPrint('KOI: settings load failed: ${e.runtimeType}');
    }
  }

  /// page.tsx:34-40 updatePreference(): saves, then reports the result. The
  /// page only shows the new value once it is saved.
  Future<void> _update(SettingsPrefs next) async {
    final uid = _uid;
    if (uid == null || _preferenceDisabled) return;
    setState(() => _saving = true);
    try {
      await ref.read(settingsPrefsStoreProvider).save(uid, next);
      if (!mounted) return;
      setState(() => _prefs = next);
      _showToast('Preference saved on this device.', ToastType.success);
    } catch (e) {
      debugPrint('KOI: settings save failed: ${e.runtimeType}');
      if (mounted) {
        _showToast(
          'Preference could not be saved. Please retry.',
          ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showToast(String message, ToastType type) =>
      setState(() => _toast = ToastMessage(message, type, ++_toastSeq));

  Future<void> _openAvatarPicker() => showAvatarPicker(
    context,
    currentAvatar: _prefs.companion,
    currentName: _prefs.displayName,
    onSave: _saveCompanion,
  );

  /// page.tsx:46-62 handleAvatarSave: the companion and its avatar are saved
  /// as a pair (avatarPreference.ts:41-46), so the Chat card and call screen
  /// follow once saved. Returns the picker's error toast, or null when saved.
  Future<String?> _saveCompanion(CompanionChoice choice) async {
    final uid = _uid;
    if (uid == null || !_loaded) {
      return 'Wait for your saved companion to load before saving.';
    }
    final next = _prefs.copyWith(
      companion: choice.companion,
      displayName: choice.displayName.trim(),
    );
    try {
      await ref.read(settingsPrefsStoreProvider).save(uid, next);
    } catch (e) {
      debugPrint('KOI: companion not saved: ${e.runtimeType}');
      return 'Companion could not be saved. Please retry.';
    }
    if (!mounted) return null;
    setState(() => _prefs = next);
    ref.read(selectedAvatarProvider.notifier).select(next.avatar);
    _showToast('Companion saved on this device.', ToastType.success);
    return null;
  }

  // page.tsx:64 handleLanguageToggle.
  void _toggleLanguage() =>
      _update(_prefs.copyWith(language: _prefs.language == 'en' ? 'ur' : 'en'));

  // page.tsx:66 handleNotificationToggle.
  void _toggleNotifications() => _update(
    _prefs.copyWith(notificationsEnabled: _prefs.notificationsEnabled != true),
  );

  /// page.tsx:193-200: web opens an inline `<input type="time">` labelled
  /// "Preferred time (device timezone)" and saves on blur; mobile opens the
  /// system time picker and saves the chosen 'HH:mm' (decision 2026-10-18).
  Future<void> _pickReminderTime() async {
    if (_preferenceDisabled) return;
    final saved = _prefs.notificationTime;
    final initial = saved != null && validTime(saved)
        ? TimeOfDay(
            hour: int.parse(saved.substring(0, 2)),
            minute: int.parse(saved.substring(3)),
          )
        : TimeOfDay.fromDateTime(widget.now());
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Preferred time (device timezone)',
    );
    if (picked == null || !mounted) return;
    String two(int v) => v.toString().padLeft(2, '0');
    await _update(
      _prefs.copyWith(
        notificationTime: '${two(picked.hour)}:${two(picked.minute)}',
      ),
    );
  }

  void _push(Widget page) => Navigator.of(context).push(settingsRoute(page));

  void _toggleHelp(String section) =>
      setState(() => _expandedHelp = _expandedHelp == section ? null : section);

  /// getAvatarDisplay() (page.tsx:72-79): the companion, then the nickname.
  static String avatarDisplay(String id, [String displayName = '']) {
    final companion =
        const {'aisha': 'Aisha 👩', 'raza': 'Raza 👨', 'koi': 'Koi 🦊'}[id] ??
        'Koi 🦊';
    return displayName.isEmpty ? companion : '$companion · $displayName';
  }

  // page.tsx:136
  String get _languageDesc => switch (_prefs.language) {
    'en' => 'English (preference)',
    'ur' => 'Urdu (preference)',
    _ => 'No language preference saved',
  };

  // page.tsx:183
  String get _checkInDesc {
    final time = _prefs.notificationTime;
    return switch (_prefs.notificationsEnabled) {
      true =>
        'Preferred time: ${time != null && validTime(time) ? time : 'not set'}',
      false => 'Preference off',
      null => 'No preference saved',
    };
  }

  // page.tsx:192
  String get _reminderDesc {
    final time = _prefs.notificationTime;
    return time != null && validTime(time)
        ? time
        : 'Choose a local preferred time';
  }

  static String _buildMode() => kReleaseMode
      ? 'Release build'
      : kProfileMode
      ? 'Profile build'
      : 'Debug build';

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
        // Debug builds: long-press for simulated safety events.
        child: SafetyDebugTrigger(
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
      ),

      const SettingsSectionLabel('Account'),
      SettingsCard(
        child: Column(
          children: [
            SettingsRow(
              key: const Key('row-avatar'),
              icon: '👤',
              label: 'Avatar & Name',
              desc: avatarDisplay(_prefs.companion, _prefs.displayName),
              onTap: _openAvatarPicker,
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const Key('row-language'),
              icon: '🌐',
              label: 'Language',
              desc: _languageDesc,
              disabled: _preferenceDisabled,
              onTap: _toggleLanguage,
            ),
            const SettingsDivider(),
            // page.tsx:140-147: disabled, so its handleClearHistory toast
            // (page.tsx:65) never shows. Nothing is deleted.
            const SettingsRow(
              key: Key('row-clear'),
              icon: '🗑',
              label: 'Clear History',
              desc: 'Unavailable until deletion scope is approved',
              disabled: true,
              danger: true,
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
              desc: _checkInDesc,
              disabled: _preferenceDisabled,
              toggle: true,
              on: _prefs.notificationsEnabled == true,
              onTap: _toggleNotifications,
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const Key('row-reminder'),
              icon: '⏰',
              label: 'Reminder Time',
              desc: _reminderDesc,
              disabled: _preferenceDisabled,
              onTap: _pickReminderTime,
            ),
          ],
        ),
      ),
      // page.tsx:201 <p role="status" className="text-xs mb-4">: 0.75rem,
      // line-height 1rem, margin-bottom 1rem.
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Semantics(
          liveRegion: true,
          child: Text(
            '${reminderStatus(_loaded ? _prefs : null, _now)} Language is a '
            'saved preference; replies and interface translation are not '
            'guaranteed.',
            key: const Key('settings-status'),
            style: settingsText(12, height: 16 / 12),
          ),
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
              desc: 'Storage and inference privacy', // page.tsx:243
              onTap: () => _push(const PrivacyScreen()),
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const Key('row-export'),
              icon: '📤',
              label: 'Export My Data',
              desc: 'Wellness export currently unavailable', // page.tsx:250
              onTap: () => _push(const ExportScreen()),
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const Key('row-import'),
              icon: '📥',
              label: 'Import Data',
              desc: 'Coming soon; import unavailable', // page.tsx:257
              onTap: () => _push(const ImportScreen()),
            ),
          ],
        ),
      ),

      const SettingsSectionLabel('Storage'),
      SettingsCard(
        padding: const EdgeInsets.all(20), // 1.25rem
        child: _StorageCard(bytes: ref.watch(koiStorageBytesProvider)),
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
              desc: 'KOI Mobile preview', // page.tsx:429 "KOI Web preview"
              expanded: _expandedHelp == 'version',
              onTap: _toggleHelp,
              body: _HelpBody(
                children: [
                  // Mobile-only line: the version from pubspec.yaml.
                  const _LabelledLine('Version:', ' $koiAppVersion', bottom: 8),
                  // page.tsx:460
                  const _LabelledLine(
                    'Release Date:',
                    ' Not published',
                    bottom: 8,
                  ),
                  // page.tsx:463 shows NODE_ENV as "Production/Development
                  // mode"; mobile names the Flutter build mode instead.
                  _LabelledLine('Runtime:', ' ${_buildMode()}', bottom: 8),
                  // page.tsx:466 says "Web App"; mobile says "Mobile App"
                  // (decision 2026-10-13).
                  const _LabelledLine('Platform:', ' Mobile App'),
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
                      'Current implemented features', // page.tsx:539
                      style: _HelpBody.style.copyWith(
                        fontWeight: FontWeight.w600,
                        color: KoiColors.neoBlack,
                      ),
                    ),
                  ),
                  // page.tsx:542-545. "Enhanced avatar animations" only when
                  // this build has an animated avatar (KOI_AVATAR_URL set);
                  // otherwise the avatar is a still image.
                  SettingsPlainList(
                    itemGap: 8,
                    style: _HelpBody.style,
                    items: [
                      if (ref.watch(avatarSourceProvider).kind !=
                          AvatarSourceKind.placeholder)
                        'Enhanced avatar animations',
                      'Encrypted local history recovery',
                      'Local companion and reminder preferences',
                      'Audio and camera remain unavailable',
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
              desc: 'Support contacts (hours not verified)', // page.tsx:588
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

      // Debug builds only: web Settings has no sign-out. Signs out of
      // Firebase (or the debug stand-in). For an anonymous Firebase user this
      // abandons the account: the next sign-in creates a new uid.
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

/// page.tsx:262-362 Storage card. Web shows navigator.storage.estimate()
/// (hooks/useStorageEstimate.ts). Mobile has no quota to compare with, so
/// the ring shows web's "—" (percent null) and the text gives the size of
/// KOI's own saved records ([koiHiveBytes]), or web's unavailable text.
class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.bytes});
  final AsyncValue<int?> bytes;

  /// useStorageEstimate.ts:16 mb(): bytes / 1048576, 2 decimals.
  static String mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(2)} MB';

  String get _label {
    final b = bytes.valueOrNull;
    if (b == null) return 'Device storage estimate unavailable.';
    return 'Approximately ${mb(b)} of KOI data on this device (saved '
        'records only; app files and caches are not counted).';
  }

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
              '—', // storage.percent === null
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
                'Device Storage Estimate', // page.tsx:336 "Browser …"
                style: settingsText(15.2, weight: FontWeight.w700),
              ),
            ),
            Text(
              _label,
              key: const Key('storage-label'),
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
              // Fill width (storage.percent ?? 0)%: always empty here.
            ),
          ],
        ),
      ),
    ],
  );
}

/// The SVG ring: r=32, stroke 8, track #F0F0F0. Web's #2D63EB arc has
/// strokeDasharray "(percent ?? 0)/100·2π·32 2π·32" (page.tsx:313), so with
/// no percent it has zero length; only the track is drawn.
class _StorageRingPainter extends CustomPainter {
  const _StorageRingPainter();

  static const double r = 32;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = const Color(0xFFF0F0F0),
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
                'Mobile preview', // page.tsx:674 "Web preview"
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
