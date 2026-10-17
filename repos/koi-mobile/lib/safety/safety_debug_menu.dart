import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_text.dart';
import '../widgets/neo_button.dart';
import 'safety_contract.dart';
import 'safety_controller.dart';
import 'safety_providers.dart';

/// SIMULATED backend events for trying the crisis and breathing screens
/// without a backend. Shapes follow KOI_CLIENT_CONTRACT_v1.md; the texts are
/// obviously fake and never shown outside debug builds.
abstract final class SimulatedSafetyEvents {
  static RiskResult high() => RiskResult.fromJson({
    'status': 'ok',
    'risk_category': 'HIGH',
    'crisis_score': 0.75,
    'confidence': 'standard',
    'confidence_reasons': <String>[],
    'modalities_used': ['text'],
    'trigger_flags': <String>[],
    'intervention_content': {
      'source': 'grounded',
      'language': 'en',
      'items': [
        for (var i = 1; i <= 4; i++) // 4 → only 3 are kept
          {
            'text': '[Simulated grounded item $i — not real content]',
            'chunk_id': 'sim-$i',
            'source_corpus': 'simulated',
            'evidence_role': 'simulated',
            'review_status': 'simulated',
          },
      ],
      'helpline': {
        'name': 'Sehat Tahaffuz 1166 (Humraaz mental health service)',
        'number': '1166',
        'verified': false,
      },
    },
    'model': {'version': 'simulated', 'calibrated': false},
  });

  static RiskResult critical() => RiskResult.fromJson({
    'status': 'ok',
    'risk_category': 'CRITICAL',
    'crisis_score': 0.95,
    'confidence': 'reduced',
    'confidence_reasons': ['reduced_modality_set'],
    'modalities_used': ['text'],
    'trigger_flags': <String>[],
    'intervention_content': {
      'source': 'fallback',
      'language': 'en',
      'items': [
        {
          'text': '[Simulated fallback item — not real content]',
          'chunk_id': 'sim-fallback',
          'source_corpus': 'simulated',
          'evidence_role': 'simulated',
          'review_status': 'simulated',
        },
      ],
      // No helpline: the screen falls back to the 1166 default.
    },
    'model': {'version': 'simulated', 'calibrated': false},
  });

  /// The contract's `start_breathing` example args (§2).
  static UiAction startBreathing() => const UiAction(UiAction.startBreathing, {
    'pattern': 'slow_6_per_min',
    'inhale_s': 4,
    'exhale_s': 6,
    'cycles': 6,
    'cue_audio': ['Breathe in', 'Breathe out'],
    'minutes_note': "about one minute; 'at your own pace'",
  });
}

/// Debug builds only: long-press [child] to open the simulated-events menu.
/// In release builds (or when [safetyDebugMenuEnabledProvider] is false)
/// this is just [child].
/// Debug builds only: a small visible "DEBUG" button that opens the same
/// simulated-events menu as [SafetyDebugTrigger]. Nothing (an empty box) in
/// release builds: `kDebugMode` is a compile-time false there.
class SafetyDebugButton extends ConsumerWidget {
  const SafetyDebugButton({super.key});

  static const String label = 'DEBUG';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode || !ref.watch(safetyDebugMenuEnabledProvider)) {
      return const SizedBox.shrink();
    }
    return Material(
      color: KoiColors.neoWhite,
      shape: const StadiumBorder(
        side: BorderSide(color: KoiColors.danger, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('safety-debug-button'),
        onTap: () =>
            showSafetyDebugMenu(context, ref.read(safetyControllerProvider)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: KoiText.body(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: KoiColors.danger,
            ),
          ),
        ),
      ),
    );
  }
}

class SafetyDebugTrigger extends ConsumerWidget {
  const SafetyDebugTrigger({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(safetyDebugMenuEnabledProvider)) return child;
    return GestureDetector(
      key: const Key('safety-debug-trigger'),
      behavior: HitTestBehavior.opaque,
      onLongPress: () =>
          showSafetyDebugMenu(context, ref.read(safetyControllerProvider)),
      child: child,
    );
  }
}

Future<void> showSafetyDebugMenu(
  BuildContext context,
  SafetyController controller,
) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  builder: (sheet) {
    Widget item(String key, String label, VoidCallback action) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: NeoButton(
        key: Key('safety-debug-$key'),
        variant: NeoButtonVariant.secondary,
        fullWidth: true,
        onPressed: () {
          Navigator.of(sheet).pop();
          action();
        },
        child: Text(label),
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Debug: simulated safety events',
              style: KoiText.display(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            item(
              'high',
              'HIGH crisis',
              () => controller.handleRisk(SimulatedSafetyEvents.high()),
            ),
            item(
              'critical',
              'CRITICAL crisis',
              () => controller.handleRisk(SimulatedSafetyEvents.critical()),
            ),
            item(
              'handoff',
              'Handoff only',
              () => controller.handleHandoff(
                const Handoff(to: 'crisis', reason: 'simulated'),
              ),
            ),
            item(
              'start',
              'start_breathing',
              () => controller.handleUiAction(
                SimulatedSafetyEvents.startBreathing(),
              ),
            ),
            item(
              'pause',
              'pause_breathing',
              () => controller.handleUiAction(
                const UiAction(UiAction.pauseBreathing),
              ),
            ),
            item(
              'stop',
              'stop_breathing',
              () => controller.handleUiAction(
                const UiAction(UiAction.stopBreathing),
              ),
            ),
            item(
              'resolved',
              'crisis_resolved sent',
              controller.crisisResolutionSent,
            ),
          ],
        ),
      ),
    );
  },
);
