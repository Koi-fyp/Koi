import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'safety_controller.dart';

/// The crisis-flow / breathing state for the signed-in shell. The chat
/// stream feeds it (ChatController), and chatSessionStateProvider replaces
/// these log-only callbacks with ones that send the values on the next chat
/// request.
final safetyControllerProvider = ChangeNotifierProvider<SafetyController>(
  (ref) => SafetyController(
    onClientEvent: (e) => debugPrint('KOI safety: client_event ${e.wire}'),
    onCrisisPath: (p) => debugPrint('KOI safety: crisis_path ${p.wire}'),
  ),
);

/// Whether the simulated-events debug menu exists. Debug builds only;
/// overridden in tests to check the release behaviour.
final safetyDebugMenuEnabledProvider = Provider<bool>((ref) => kDebugMode);
