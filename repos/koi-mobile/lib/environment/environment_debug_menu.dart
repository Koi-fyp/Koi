import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/koi_text.dart';
import '../widgets/neo_button.dart';
import 'environment_controller.dart';
import 'environment_palette.dart';

const String environmentDebugLabel = 'Set environment emotion';
const String environmentDebugClear = 'Clear (follow the chat)';

/// Debug builds only (opened from the safety debug menu): preview each
/// background palette for the demo. Nothing is saved; does nothing in
/// release builds.
Future<void> showEnvironmentDebugMenu(
  BuildContext context,
  EnvironmentController controller,
) async {
  if (!kDebugMode) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) {
      Widget item(String key, String label, EnvironmentMood? mood) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: NeoButton(
          key: Key('environment-debug-$key'),
          variant: NeoButtonVariant.secondary,
          fullWidth: true,
          onPressed: () {
            Navigator.of(sheet).pop();
            controller.debugPreview(mood);
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
                'Debug: $environmentDebugLabel',
                style: KoiText.display(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final mood in EnvironmentMood.values)
                item(mood.name, mood.name, mood),
              item('clear', environmentDebugClear, null),
            ],
          ),
        ),
      );
    },
  );
}
