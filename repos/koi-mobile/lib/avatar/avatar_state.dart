import 'dart:async';

/// The avatar's expressions. Exactly the names the web avatar host accepts
/// (feat/avatar-webview-host VRMAvatarController.ts `KoiEmotion`); the
/// host turns anything else into 'neutral'.
///
/// Not the same thing as `Emotion` in core/emotion.dart, which is the
/// user-emotion label stored with messages.
enum AvatarEmotion { neutral, joy, angry, sorrow, fun }

/// What the companion is doing in the conversation. Same names as the web
/// host's `ConversationState` (VRMAvatarController.ts).
enum AvatarConversationState { idle, listening, thinking, speaking }

/// Which 3D avatar is shown. Stored in HiveUser.avatarType with the web
/// onboarding ids (lib/onboarding.ts); 'fox' is no longer offered (Q7).
enum AvatarType {
  male('male_human', 'male'),
  female('female_human', 'female');

  const AvatarType(this.stored, this.model);

  /// HiveUser.avatarType value.
  final String stored;

  /// The avatar host's `?model=` value (app/avatar-host/page.tsx).
  final String model;

  /// Anything else (null, the dropped 'fox') is the male default, as in
  /// onboarding (Q8: avatar step skipped, default male).
  static AvatarType fromStored(String? value) =>
      value == female.stored ? female : male;

  /// The still image (feat/avatar-webview-host public/Male.png and
  /// public/Female.png: renderer screenshots of each VRM, both 491×525).
  String get imageAsset => switch (this) {
    male => 'assets/images/Male.png',
    female => 'assets/images/Female.png',
  };
}

/// One Rhubarb mouth cue, as in the web branch's lib/speech/mouthCues.ts
/// (`{start, end, value}`, seconds on the audio clock, value A–H or X).
class MouthCue {
  const MouthCue({required this.start, required this.end, required this.value});
  final double start;
  final double end;
  final String value;
}

/// Something that tells the avatar what to show during a conversation.
sealed class AvatarStateEvent {
  const AvatarStateEvent(this.sessionId);
  final String sessionId;
}

/// A new conversation began; updates for any earlier id are now stale.
class AvatarSessionStarted extends AvatarStateEvent {
  const AvatarSessionStarted(super.sessionId);
}

/// Emotion and/or conversation state for the conversation [sessionId].
class AvatarStateUpdate extends AvatarStateEvent {
  const AvatarStateUpdate(
    super.sessionId, {
    this.emotion,
    this.intensity = 0,
    this.conversationState,
  });

  final AvatarEmotion? emotion;

  /// 0.0 to 1.0, used with [emotion].
  final double intensity;
  final AvatarConversationState? conversationState;
}

/// Where the call screen gets avatar updates from.
///
/// TODO(backend): a real source maps the chat stream's companion_state
/// {emotion, intensity} (Blueprint §4.1) onto [AvatarStateUpdate]s. Not
/// built yet: nothing here parses backend events or calls the backend.
abstract class AvatarStateSource {
  Stream<AvatarStateEvent> get events;
  void dispose();
}

/// The production default until the backend is connected: never emits.
class NoAvatarStateSource implements AvatarStateSource {
  @override
  Stream<AvatarStateEvent> get events => const Stream.empty();

  @override
  void dispose() {}
}

/// For tests and debug: emit events by hand, or with [SimulatedAvatarStateSource.cycling]
/// step through every emotion on a timer (used with the mock avatar page).
class SimulatedAvatarStateSource implements AvatarStateSource {
  SimulatedAvatarStateSource();

  /// Starts a session, then every [every] moves to the next emotion with a
  /// rising intensity.
  SimulatedAvatarStateSource.cycling({
    Duration every = const Duration(seconds: 4),
  }) {
    // After the creator has subscribed (broadcast streams drop earlier
    // events).
    scheduleMicrotask(() {
      if (_controller.isClosed) return;
      _cycle(startSession(), every);
    });
  }

  void _cycle(String id, Duration every) {
    var i = 0;
    _timer = Timer.periodic(every, (_) {
      i++;
      final emotion = AvatarEmotion.values[i % AvatarEmotion.values.length];
      emit(
        AvatarStateUpdate(
          id,
          emotion: emotion,
          intensity: (i % 4 + 1) / 4,
          conversationState: AvatarConversationState
              .values[i % AvatarConversationState.values.length],
        ),
      );
    });
  }

  final _controller = StreamController<AvatarStateEvent>.broadcast();
  Timer? _timer;
  int _sessions = 0;

  @override
  Stream<AvatarStateEvent> get events => _controller.stream;

  /// Starts a new session and returns its id.
  String startSession() {
    final id = 'sim-${++_sessions}';
    emit(AvatarSessionStarted(id));
    return id;
  }

  void emit(AvatarStateEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
