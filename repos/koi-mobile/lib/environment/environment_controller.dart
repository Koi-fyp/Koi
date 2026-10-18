import 'package:flutter/foundation.dart';

import '../avatar/avatar_state.dart';
import 'environment_palette.dart';

/// Holds the background mood for one signed-in user, in memory only (never
/// persisted: a restart or another user starts at neutral).
///
/// Inputs: the chat stream's avatar events ([onAvatarEvent]) and the safety
/// state ([updateSafety]). Calm wins over any emotion while breathing or the
/// crisis flow is on screen (a HIGH / CRITICAL risk opens the crisis flow).
/// Afterwards: breathing → the last emotion; crisis → neutral until the next
/// emotion arrives.
class EnvironmentController extends ChangeNotifier {
  EnvironmentController({this.uid, this.safetyState});

  /// The conversation whose events count (Q5: conversationId = uid).
  final String? uid;

  /// Re-read before each avatar event: SafetyController.crisisResolutionSent
  /// does not notify, so the end of a crisis is seen with the next turn.
  final ({bool crisis, bool breathing}) Function()? safetyState;

  AvatarEmotion _emotion = AvatarEmotion.neutral;
  bool _crisis = false;
  bool _breathing = false;
  EnvironmentMood? _preview;
  bool _disposed = false;

  /// What the screens show.
  EnvironmentMood get mood {
    if (_preview != null) return _preview!;
    if (_crisis || _breathing) return EnvironmentMood.calm;
    return EnvironmentMood.fromEmotion(_emotion);
  }

  /// The latest companion emotion (kept while calm is shown).
  AvatarEmotion get emotion => _emotion;

  /// The debug menu's preview, if any.
  EnvironmentMood? get preview => _preview;

  /// An event from ChatController.avatarEvents. Other conversations' events
  /// are ignored; a new conversation starts at neutral.
  void onAvatarEvent(AvatarStateEvent event) {
    if (_disposed || event.sessionId != uid) return;
    final safety = safetyState?.call();
    if (safety != null) {
      updateSafety(crisis: safety.crisis, breathing: safety.breathing);
    }
    switch (event) {
      case AvatarSessionStarted():
        reset();
      case AvatarStateUpdate(:final emotion?):
        _set(() => _emotion = emotion);
      case AvatarStateUpdate():
        break;
    }
  }

  /// [crisis]: the crisis screen is open or its resolution is not sent yet.
  /// [breathing]: the breathing screen is open.
  void updateSafety({required bool crisis, required bool breathing}) {
    if (_disposed || (crisis == _crisis && breathing == _breathing)) return;
    _set(() {
      // Neutral after a crisis until the next emotion.
      if (crisis && !_crisis) _emotion = AvatarEmotion.neutral;
      _crisis = crisis;
      _breathing = breathing;
    });
  }

  /// Back to neutral (new conversation). Calm still follows the safety state.
  void reset() => _set(() {
    _emotion = AvatarEmotion.neutral;
    _preview = null;
  });

  /// Debug menu only: show [mood] regardless of the inputs; null clears it.
  void debugPreview(EnvironmentMood? mood) => _set(() => _preview = mood);

  void _set(VoidCallback change) {
    if (_disposed) return;
    final before = mood;
    change();
    if (mood != before) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
