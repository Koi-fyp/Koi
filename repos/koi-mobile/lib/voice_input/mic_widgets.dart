import 'package:flutter/material.dart';

import '../onboarding/step_layout.dart' show bodyText, displayText;
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';
import 'mic_controller.dart';

/// Mobile-only texts (no web version), approved 2026-10-18 (Prompt 26;
/// consent replaced in Prompt 29).
abstract final class MicTexts {
  /// Prompt 29 (exact text).
  static const String consent =
      "Your recording is sent to KOI's speech-recognition service to be "
      'turned into text, then discarded. The text is sent to the reply model '
      'like typed text. Recordings are not saved.';
  static const String consentContinue = 'Continue';
  static const String consentNotNow = 'Not now';
  static const String denied = 'Microphone is off. You can still type.';
  static const String deniedSettings =
      'Microphone is off. You can still type. Turn it on in Android Settings.';
  static const String unclear = "Couldn't hear that clearly. Try again?";
  static const String sendFailed = "Couldn't send your voice message.";
  static const String retry = 'Retry';
  static const String recording = 'Recording';
  static const String cancel = 'Cancel';

  static String? notice(MicNotice n) => switch (n) {
    MicNotice.none => null,
    MicNotice.denied => denied,
    MicNotice.deniedSettings => deniedSettings,
    MicNotice.unclear => unclear,
    MicNotice.sendFailed => sendFailed,
  };
}

/// The opt-in explanation shown before the first recording (once per uid).
/// true = Continue; Not now, back or a tap outside = false.
Future<bool> showMicConsent(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => const MicConsentDialog(),
    ) ??
    false;

class MicConsentDialog extends StatelessWidget {
  const MicConsentDialog({super.key});

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('mic-consent'),
    backgroundColor: KoiColors.neoWhite,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    shape: RoundedRectangleBorder(
      side: const BorderSide(width: 3),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            MicTexts.consent,
            style: bodyText(15, weight: FontWeight.w600, height: 1.5),
          ),
          const SizedBox(height: 20),
          NeoButton(
            key: const Key('mic-consent-continue'),
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(MicTexts.consentContinue),
          ),
          const SizedBox(height: 12),
          NeoButton(
            key: const Key('mic-consent-not-now'),
            variant: NeoButtonVariant.secondary,
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(MicTexts.consentNotNow),
          ),
        ],
      ),
    ),
  );
}

/// m:ss
String micTime(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// While recording: red dot, "Recording m:ss" (danger colour from
/// [MicController.warnAt]) and Cancel. The mic button sends.
class MicRecordingStrip extends StatelessWidget {
  const MicRecordingStrip({super.key, required this.mic});
  final MicController mic;

  @override
  Widget build(BuildContext context) {
    final color = mic.warning ? KoiColors.danger : KoiColors.neoBlack;
    return Padding(
      key: const Key('mic-recording'),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: KoiColors.danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              liveRegion: mic.warning,
              child: Text(
                '${MicTexts.recording} ${micTime(mic.elapsed)}',
                key: const Key('mic-timer'),
                style: displayText(14, color: color),
              ),
            ),
          ),
          _TextLink(
            key: const Key('mic-cancel'),
            label: MicTexts.cancel,
            onTap: mic.cancel,
          ),
        ],
      ),
    );
  }
}

/// Permission and send errors, with Retry after a failed send.
class MicNoticeLine extends StatelessWidget {
  const MicNoticeLine({super.key, required this.mic});
  final MicController mic;

  @override
  Widget build(BuildContext context) {
    final text = MicTexts.notice(mic.notice);
    if (text == null) return const SizedBox.shrink();
    return Padding(
      key: const Key('mic-notice'),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                // Same muted line as WakingLine (gray-600).
                style: bodyText(13, color: const Color(0xFF4B5563)),
              ),
            ),
            if (mic.canRetry)
              _TextLink(
                key: const Key('mic-retry'),
                label: MicTexts.retry,
                onTap: mic.retry,
              ),
          ],
        ),
      ),
    );
  }
}

class _TextLink extends StatelessWidget {
  const _TextLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Center(
          widthFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: displayText(14)
                  .copyWith(decoration: TextDecoration.underline),
            ),
          ),
        ),
      ),
    ),
  );
}
