import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../safety/breathing_screen.dart';
import '../safety/safety_contract.dart' show UiAction;
import '../safety/safety_controller.dart';
import '../safety/safety_providers.dart';

/// The contract's example `start_breathing` args (§2, the same as the
/// safety debug menu): 4 s in, 6 s out, 6 cycles.
const UiAction localBreathingAction = UiAction(UiAction.startBreathing, {
  'pattern': 'slow_6_per_min',
  'inhale_s': 4,
  'exhale_s': 6,
  'cycles': 6,
  'cue_audio': ['Breathe in', 'Breathe out'],
  'minutes_note': "about one minute; 'at your own pace'",
});

/// MLT-4 "Breathing exercise" (Prompt 28, answer 3a): the existing
/// BreathingScreen, started through the existing SafetyController entry
/// point (`handleUiAction(start_breathing)`), but on a private controller
/// with no callbacks. Nothing reaches the chat session, so no
/// `client_event` is sent; the shared controller and its rules are not
/// touched. Not opened while the crisis flow is open or pending; closed if
/// the crisis flow opens meanwhile.
Future<void> openLocalBreathing(BuildContext context, WidgetRef ref) async {
  final shared = ref.read(safetyControllerProvider);
  if (shared.crisis != null ||
      shared.resolutionPending ||
      shared.breathing != null) {
    return;
  }
  final local = SafetyController()..handleUiAction(localBreathingAction);
  if (local.breathing == null) return;
  final nav = Navigator.of(context, rootNavigator: true);
  final route = MaterialPageRoute<void>(
    settings: const RouteSettings(name: 'local-breathing'),
    builder: (_) => BreathingScreen(controller: local),
  );
  var cleaned = false;
  late final VoidCallback onLocal;
  late final VoidCallback onShared;
  void cleanUp() {
    if (cleaned) return;
    cleaned = true;
    local.removeListener(onLocal);
    shared.removeListener(onShared);
    // Not disposed: close() runs inside its notification, and the private
    // controller owns no timers or streams.
  }

  void close() {
    if (route.isActive) nav.removeRoute(route);
    cleanUp();
  }

  onLocal = () {
    if (local.breathing == null) close();
  };
  onShared = () {
    if (shared.crisis != null) close();
  };
  local.addListener(onLocal);
  shared.addListener(onShared);
  await nav.push(route);
  cleanUp();
}
