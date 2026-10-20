import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/account_widgets.dart';
import '../theme/koi_colors.dart';
import 'care_providers.dart';
import 'care_strings.dart';
import 'mock_care_backend.dart';

/// Debug + KOI_MOCKS only (see [simulatePsychologistMenuAllowed]): plays
/// the psychologist's side against the demo backend, then refreshes the
/// inbox (an application outcome there re-checks the capabilities, like a
/// real notification would). Strings are debug-only English.
Future<void> showSimulatePsychologistMenu(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!ref.read(simulatePsychologistMenuProvider)) return;
  final backend = ref.read(mockCareBackendProvider);
  final s = ref.read(careStringsProvider);
  final options = <(String, Key, void Function())>[
    for (final r in backend.awaitingDecision) ...[
      (
        'Accept application (${mockExpertName(r.psychologistUid)})',
        Key('simulate-accept-${r.id}'),
        () => backend.simulateDecision(r.id, accept: true),
      ),
      (
        'Decline application (${mockExpertName(r.psychologistUid)})',
        Key('simulate-decline-${r.id}'),
        () => backend.simulateDecision(r.id, accept: false),
      ),
    ],
    (
      'Psychologist sends a message',
      const Key('simulate-reply'),
      () => backend.simulateReply('Hello, this is a demo message.'),
    ),
    (
      'Propose a time for the newest request',
      const Key('simulate-propose'),
      backend.simulateProposeTime,
    ),
    (
      'Complete the confirmed appointment',
      const Key('simulate-complete'),
      backend.simulateCompleteConfirmed,
    ),
    (
      'Assign a questionnaire (notification only)',
      const Key('simulate-assign'),
      backend.simulateQuestionnaireAssigned,
    ),
    (
      'End the care relationship',
      const Key('simulate-end'),
      backend.simulateEndRelationship,
    ),
    // MOB-4: fictional codes for Care → "I have an invitation code".
    (
      'Copy a demo invitation code',
      const Key('simulate-invite-code'),
      () => unawaited(
        Clipboard.setData(
          const ClipboardData(text: MockCareBackend.demoInvitationCode),
        ),
      ),
    ),
    (
      'Copy an already used demo code',
      const Key('simulate-invite-used'),
      () => unawaited(
        Clipboard.setData(
          const ClipboardData(text: MockCareBackend.demoUsedInvitationCode),
        ),
      ),
    ),
  ];
  final picked = await showDialog<void Function()>(
    context: context,
    builder: (context) => SimpleDialog(
      key: const Key('simulate-menu'),
      title: Text(s.t(CareText.simulateTitle), style: koiTitleStyle(20)),
      backgroundColor: KoiColors.neoWhite,
      children: [
        for (final (label, key, run) in options)
          SimpleDialogOption(
            key: key,
            onPressed: () => Navigator.of(context).pop(run),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(label, style: koiBodyStyle()),
            ),
          ),
      ],
    ),
  );
  if (picked == null) return;
  picked();
  final session = ref.read(careSessionProvider);
  await session.notifications.refresh();
  // Closure has no notification kind: the app learns it from
  // /me/capabilities, which pull-to-refresh / resume also re-check.
  unawaited(ref.read(capabilityControllerProvider).refresh(silent: true));
}
