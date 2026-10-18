import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../avatar/avatar_providers.dart';
import '../../onboarding/steps/companion_step.dart';
import '../settings_prefs.dart';
import '../../theme/koi_colors.dart';
import '../../theme/koi_shadows.dart';
import '../../theme/koi_text.dart';
import '../../widgets/neo_button.dart';
import 'settings_widgets.dart';

/// The picker's result (web: onSave(avatar, name)).
typedef CompanionChoice = ({String companion, String name});

/// Opens the Settings companion picker. Resolves to the saved choice, or
/// null when closed via ✕, Cancel or a tap on the backdrop.
///
/// Decision 2026-10-13: mirror web's companions (Aisha / Raza / Koi 🦊) and
/// name field. Saving the companion also picks its avatar (Prompt 19, web
/// 223e97c settings/page.tsx:46-62).
///
/// Web keeps one AvatarPicker mounted and seeds its useState only once, so an
/// unsaved selection survives Cancel. Mobile seeds from the current values
/// every time it opens (see WEB_BUGS_FOUND_DURING_MOBILE.md).
Future<CompanionChoice?> showAvatarPicker(
  BuildContext context, {
  required String currentAvatar,
  required String currentName,
}) => showGeneralDialog<CompanionChoice>(
  context: context,
  barrierDismissible: false, // the backdrop below handles taps itself
  barrierColor: const Color(0x00000000),
  transitionDuration: const Duration(milliseconds: 300),
  pageBuilder: (context, animation, _) => AvatarPicker(
    animation: animation,
    currentAvatar: currentAvatar,
    currentName: currentName,
  ),
);

/// "Review companion selection" on the Chat card and call screen. Web links
/// to /onboarding (223e97c chat/page.tsx:146, companion-scene/page.tsx:41);
/// mobile can't reopen a finished onboarding, so this opens the Settings
/// picker over the current screen and saves like Settings does (decision
/// 2026-10-18).
Future<void> reviewCompanionSelection(
  BuildContext context,
  WidgetRef ref,
) async {
  final uid = ref.read(authServiceProvider).user?.uid;
  if (uid == null) return;
  final store = ref.read(settingsPrefsStoreProvider);
  final SettingsPrefs prefs;
  try {
    prefs = await store.load(uid);
  } catch (e) {
    debugPrint('KOI: companion not loaded: ${e.runtimeType}');
    ref.invalidate(selectedAvatarProvider); // try loading again
    return;
  }
  if (!context.mounted) return;
  final choice = await showAvatarPicker(
    context,
    currentAvatar: prefs.companion,
    currentName: prefs.name,
  );
  if (choice == null) return;
  final next = prefs.copyWith(companion: choice.companion, name: choice.name);
  ref.read(selectedAvatarProvider.notifier).select(next.avatar);
  try {
    await store.save(uid, next);
  } catch (e) {
    debugPrint('KOI: companion not saved: ${e.runtimeType}');
  }
}

/// Mirrors settings/components/AvatarPicker.tsx.
class AvatarPicker extends StatefulWidget {
  const AvatarPicker({
    super.key,
    required this.animation,
    this.currentAvatar = 'koi', // currentAvatar = 'koi'
    this.currentName = '', // currentName = ''
  });

  final Animation<double> animation;
  final String currentAvatar;
  final String currentName;

  // AvatarPicker.tsx:6-10 `companions` (223e97c). Web changed only the
  // onboarding cards to avatar previews; the picker keeps emoji and traits.
  static const List<KoiCompanion> companions = [
    KoiCompanion(
      'aisha',
      'Aisha',
      'Warm & caring',
      Color(0xFFFF4A60),
      icon: '👩',
    ),
    KoiCompanion(
      'raza',
      'Raza',
      'Calm & grounded',
      Color(0xFFFFC224),
      icon: '👨',
    ),
    KoiCompanion(
      'koi',
      'Koi',
      'Playful & curious',
      Color(0xFF06B6D4),
      icon: '🦊',
    ),
  ];

  @override
  State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  late String _selected = widget.currentAvatar;
  late final TextEditingController _name = TextEditingController(
    text: widget.currentName,
  );
  final FocusNode _nameFocus = FocusNode();

  // slideUpModal 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)
  static const Curve _slideCurve = Cubic(0.34, 1.56, 0.64, 1);

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _save() =>
      Navigator.of(context)
          .pop<CompanionChoice>((companion: _selected, name: _name.text));

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final a = widget.animation;
    return AnimatedBuilder(
      animation: a,
      builder: (context, child) {
        // fadeIn 0.2s on the overlay, slideUpModal 0.3s on the panel
        final fade = (a.value / (200 / 300)).clamp(0.0, 1.0);
        return Opacity(opacity: fade, child: child);
      },
      child: Stack(
        children: [
          // Overlay: rgba(0,0,0,0.6), backdrop-filter blur(8px); click closes.
          Positioned.fill(
            child: GestureDetector(
              key: const Key('avatar-picker-backdrop'),
              onTap: _close,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: const ColoredBox(color: Color(0x99000000)),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16), // padding 1rem
                child: AnimatedBuilder(
                  animation: a,
                  builder: (context, child) {
                    final t = a.value;
                    final c = _slideCurve.transform(t);
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 40 * (1 - c)),
                        child: Transform.scale(
                          scale: 0.95 + 0.05 * c,
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 900,
                      maxHeight: 0.9 * size.height, // 90vh
                    ),
                    child: _panel(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel() => Material(
    type: MaterialType.transparency,
    child: Container(
      key: const Key('avatar-picker'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: KoiColors.neoWhite,
        border: Border.all(width: 3),
        borderRadius: BorderRadius.circular(32), // 2rem
        boxShadow: KoiShadows.hard(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(29),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32), // 2rem
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              const SizedBox(height: 32), // header marginBottom 2rem
              _cards(),
              const SizedBox(height: 32), // grid marginBottom 2rem
              _nameField(),
              const SizedBox(height: 32), // marginBottom 2rem
              _actions(),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Choose Your Companion',
              // 2rem, 900, letter-spacing -0.02em
              style: settingsText(
                32,
                weight: FontWeight.w900,
                letterSpacing: -0.02 * 32,
              ),
            ),
          ),
          GestureDetector(
            key: const Key('avatar-picker-close'),
            onTap: _close,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF0F0F0),
                border: Border.all(width: 2),
              ),
              child: Text(
                '✕',
                style: settingsText(20, weight: FontWeight.w700, height: 1),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8), // marginBottom 0.5rem
      Text(
        'Pick the personality that resonates with you',
        style: settingsText(15.2, color: const Color(0xFF666666)),
      ),
    ],
  );

  // grid repeat(auto-fit, minmax(200px, 1fr)), gap 1.5rem.
  Widget _cards() => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 24.0;
      final cols = ((constraints.maxWidth + gap) / (200 + gap)).floor().clamp(
        1,
        AvatarPicker.companions.length,
      );
      final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final c in AvatarPicker.companions)
            SizedBox(
              width: w,
              child: CompanionCard(
                keyPrefix: 'picker',
                companion: c,
                isSelected: _selected == c.id,
                onSelect: () => setState(() => _selected = c.id),
              ),
            ),
        ],
      );
    },
  );

  Widget _nameField() {
    final focused = _nameFocus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Name (Optional)',
          style: settingsText(14.4, weight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200), // all 0.2s ease
          curve: Curves.ease,
          decoration: BoxDecoration(
            // #F9F9F9; focus: #fff + 0 0 0 4px rgba(45, 99, 235, 0.1)
            color: focused ? KoiColors.neoWhite : const Color(0xFFF9F9F9),
            border: Border.all(width: 2.5),
            borderRadius: BorderRadius.circular(12),
            boxShadow: focused
                ? const [BoxShadow(color: Color(0x1A2D63EB), spreadRadius: 4)]
                : null,
          ),
          child: TextField(
            key: const Key('avatar-picker-name'),
            controller: _name,
            focusNode: _nameFocus,
            style: settingsText(16, weight: FontWeight.w500, height: null),
            cursorColor: KoiColors.neoBlack,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14, // 0.875rem
                horizontal: 20, // 1.25rem
              ),
              hintText: 'What should I call you?',
              // preflight input::placeholder colour (theme gray-400)
              hintStyle: settingsText(
                16,
                weight: FontWeight.w500,
                height: null,
                color: const Color(0xFF9CA3AF),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const String _cancelLabel = 'Cancel';
  static const String _saveLabel = 'Save Changes ✓';

  /// Web: `display: flex; gap: 1rem`, both buttons `flex: 1`. When a label
  /// would not fit its half-width button (360dp phones), the buttons stack
  /// full width in the same order instead (decision 2026-10-13); web lets
  /// the nowrap text overflow the modal.
  Widget _actions() {
    final cancel = NeoButton(
      key: const Key('avatar-picker-cancel'),
      variant: NeoButtonVariant.ghost,
      fullWidth: true,
      onPressed: _close,
      child: const Text(_cancelLabel),
    );
    final save = NeoButton(
      key: const Key('avatar-picker-save'),
      fullWidth: true,
      onPressed: _save,
      child: const Text(_saveLabel),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0; // gap 1rem
        final half = (constraints.maxWidth - gap) / 2;
        final scaler = MediaQuery.textScalerOf(context);
        final fits = [
          _cancelLabel,
          _saveLabel,
        ].every((l) => buttonWidthFor(l, scaler) <= half);
        if (fits) {
          return Row(
            children: [
              Expanded(child: cancel),
              const SizedBox(width: gap),
              Expanded(child: save),
            ],
          );
        }
        return Column(
          key: const Key('avatar-picker-actions-stacked'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cancel,
            const SizedBox(height: gap),
            save,
          ],
        );
      },
    );
  }

  /// Width a NeoButton needs for [label] on one line: text + padding
  /// 1.75rem * 2 + border 2.5px * 2.
  static double buttonWidthFor(String label, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: KoiText.display(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w + NeoButton.padding.horizontal + 2 * NeoButton.borderWidth;
  }
}
