import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../onboarding/step_layout.dart' show bodyText, displayText;
import '../theme/koi_colors.dart';
import 'camera_session.dart';

/// The platform camera; tests override it.
final localCameraFactoryProvider = Provider<LocalCamera Function()>(
  (ref) => PluginLocalCamera.new,
);

/// The call screen's self-view (web reference components/camera/
/// CameraPip.tsx): the local preview with a red-dot "Camera on" label and a
/// one-tap off, or the state's message. Nothing here reads frames.
class CameraPip extends StatelessWidget {
  const CameraPip({super.key, required this.session});

  final CameraSession session;

  /// CameraPip.tsx `#d92d20` dot.
  static const Color dot = Color(0xFFD92D20);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final state = session.state;
      if (state == CameraViewState.off) return const SizedBox.shrink();
      final on = state == CameraViewState.on;
      final message = state == CameraViewState.starting
          ? CameraTexts.starting
          : CameraTexts.message(state);
      return Container(
        key: const Key('camera-pip'),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: KoiColors.neoWhite,
          border: Border.all(width: 3),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(offset: Offset(4, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (on)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ColoredBox(
                    color: KoiColors.neoBlack,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: 300,
                        height: 400,
                        child: session.camera.preview(),
                      ),
                    ),
                  ),
                ),
              )
            else if (message != null)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    key: const Key('camera-message'),
                    style: bodyText(12, weight: FontWeight.w600, height: 1.3),
                  ),
                ),
              ),
            if (on) ...[
              const SizedBox(height: 6),
              Semantics(
                liveRegion: true,
                child: Row(
                  key: const Key('camera-on'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(CameraTexts.on, style: displayText(12)),
                    ),
                  ],
                ),
              ),
            ],
            if (on || state == CameraViewState.starting) ...[
              const SizedBox(height: 6),
              Semantics(
                button: true,
                label: CameraTexts.turnOff,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const Key('camera-off'),
                  behavior: HitTestBehavior.opaque,
                  onTap: session.stop,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: KoiColors.neoWhite,
                      border: Border.all(width: 2),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Text('Turn off', style: displayText(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// The privacy line shown in both camera modes (exact text, Prompt 29).
class CameraDisclosureLine extends StatelessWidget {
  const CameraDisclosureLine({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
    child: Text(
      CameraTexts.disclosure,
      key: const Key('camera-disclosure'),
      textAlign: TextAlign.center,
      // #4B5563, as the waking / mic lines (min 5.36:1 on the tints).
      style: bodyText(12, height: 1.35, color: const Color(0xFF4B5563)),
    ),
  );
}
