import 'package:flutter/material.dart';

import '../../theme/koi_colors.dart';
import '../../widgets/neo_button.dart';
import '../../widgets/neo_card.dart';
import '../step_layout.dart';

/// Picks a time; injectable for tests. Returns null when cancelled.
typedef TimePicker = Future<TimeOfDay?> Function(
  BuildContext context,
  TimeOfDay initial,
);

Future<TimeOfDay?> _materialTimePicker(
  BuildContext context,
  TimeOfDay initial,
) => showTimePicker(context: context, initialTime: initial);

/// Mirrors src/components/onboarding/NotificationStep.tsx.
///
/// The web `<input type="time">` becomes a tap target that opens Flutter's
/// built-in time picker. The value is stored as 'HH:mm' like the input's
/// value. Like web, min/max (06:00–23:00) are only shown as a hint, not
/// enforced (an HTML time input's min/max do not block onChange).
class NotificationStep extends StatefulWidget {
  const NotificationStep({
    super.key,
    required this.onComplete,
    this.pickTime = _materialTimePicker,
  });

  final void Function(String notificationTime, bool notificationsEnabled)
  onComplete;
  final TimePicker pickTime;

  /// Default [TimePicker]: Flutter's built-in Material time picker.
  static Future<TimeOfDay?> defaultPicker(BuildContext c, TimeOfDay t) =>
      _materialTimePicker(c, t);

  @override
  State<NotificationStep> createState() => _NotificationStepState();
}

class _NotificationStepState extends State<NotificationStep> {
  bool _enabled = true; // useState(true)
  String _time = '20:00'; // useState('20:00')

  static String format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pick() async {
    final parts = _time.split(':');
    final picked = await widget.pickTime(
      context,
      TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked != null && mounted) setState(() => _time = format(picked));
  }

  @override
  Widget build(BuildContext context) {
    return StepLayout(
      buttonGap: 24,
      button: NeoButton(
        key: const Key('notification-complete'),
        variant: NeoButtonVariant.secondary,
        fullWidth: true,
        onPressed: () => widget.onComplete(_time, _enabled),
        child: const Text("Let's Go ✦"),
      ),
      children: [
        const StepTitle('Daily Check-ins', bottom: 6),
        const StepSubtitle(
          "KOI can gently check in with you each day to see how you're feeling.",
          bottom: 28,
        ),
        SizedBox(
          width: double.infinity,
          child: NeoCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Enable daily reminders', style: displayText(14.4)),
                      const SizedBox(height: 2),
                      Text(
                        'A gentle nudge each day',
                        style: bodyText(12.48, color: const Color(0xFF999999)),
                      ),
                    ],
                  ),
                ),
                _Switch(
                  value: _enabled,
                  onTap: () => setState(() => _enabled = !_enabled),
                ),
              ],
            ),
          ),
        ),
        if (_enabled) ...[
          const SizedBox(height: 12), // mb-3
          SizedBox(
            width: double.infinity,
            child: NeoCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reminder time', style: displayText(14)),
                  const SizedBox(height: 10),
                  // .neo-input + inline style (display 700 1.5rem, centred,
                  // letter-spacing 0.04em)
                  Semantics(
                    button: true,
                    label: 'Reminder time',
                    value: _time,
                    child: GestureDetector(
                      key: const Key('notif-time'),
                      onTap: _pick,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: KoiColors.neoWhite,
                          border: Border.all(width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _time,
                          textAlign: TextAlign.center,
                          style: displayText(24, letterSpacing: 0.04 * 24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Available 6:00 AM – 11:00 PM',
                    style: bodyText(11.52, color: const Color(0xFFAAAAAA)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The role="switch" button: 52x28, radius 14, 2px black border, neo-blue
/// when on else #ddd; knob 20x20 white with 1.5px border at left 24 / 2;
/// transitions 0.2s ease.
class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.onTap});
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    child: GestureDetector(
      key: const Key('notif-switch'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.ease,
        width: 52,
        height: 28,
        decoration: BoxDecoration(
          color: value ? KoiColors.neoBlue : const Color(0xFFDDDDDD),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(width: 2),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.ease,
              top: 2,
              left: value ? 24 : 2,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: KoiColors.neoWhite,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
