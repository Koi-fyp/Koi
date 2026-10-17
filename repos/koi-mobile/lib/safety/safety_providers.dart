import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'safety_controller.dart';

/// The crisis-flow / breathing state for the signed-in shell.
// TODO(wiring): the chat stream owner feeds this and sets its callbacks.
final safetyControllerProvider = ChangeNotifierProvider<SafetyController>(
  (ref) => SafetyController(
    onClientEvent: (e) => debugPrint('KOI safety: client_event ${e.wire}'),
    onCrisisPath: (p) => debugPrint('KOI safety: crisis_path ${p.wire}'),
  ),
);

/// Whether the simulated-events debug menu exists. Debug builds only;
/// overridden in tests to check the release behaviour.
final safetyDebugMenuEnabledProvider = Provider<bool>((ref) => kDebugMode);
