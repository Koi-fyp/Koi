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

/// Which 3D avatar model the avatar host shows.
enum AvatarType {
  male('male_human', 'male'),
  female('female_human', 'female');

  const AvatarType(this.stored, this.model);

  /// HiveUser.avatarType / Firestore profile.avatar value.
  final String stored;

  /// The avatar host's `?model=` value (app/avatar-host/page.tsx).
  final String model;

  /// The still image (feat/avatar-webview-host public/Male.png and
  /// public/Female.png: renderer screenshots of each VRM, both 491×525).
  String get imageAsset => switch (this) {
    male => 'assets/images/Male.png',
    female => 'assets/images/Female.png',
  };
}

/// One companion choice selects the matching avatar: Aisha/female,
/// Raza/male, Koi/fox (web 223e97c lib/avatar/avatarPreference.ts:13-17
/// `BY_COMPANION`). Koi has no model or image on web either.
enum CompanionAvatar {
  aisha('aisha', 'female_human', 'Aisha', AvatarType.female),
  raza('raza', 'male_human', 'Raza', AvatarType.male),
  koi('koi', 'fox', 'Koi', null);

  const CompanionAvatar(this.companion, this.avatarId, this.name, this.model);

  /// UserRecord.companion: 'aisha' | 'raza' | 'koi'.
  final String companion;

  /// UserRecord.avatar / Firestore profile.avatar: 'female_human' |
  /// 'male_human' | 'fox'.
  final String avatarId;
  final String name;

  /// The 3D model and still image; null for Koi's fox.
  final AvatarType? model;

  static CompanionAvatar? fromCompanion(String? id) {
    for (final c in values) {
      if (c.companion == id) return c;
    }
    return null;
  }

  /// avatarPreference.ts:20-28 resolveRepresentation(): the companion is
  /// canonical; an avatar-only (legacy) record maps back to its companion.
  /// Null when neither is valid (web: 'unselected').
  static CompanionAvatar? resolve({String? companion, String? avatar}) {
    final byCompanion = fromCompanion(companion);
    if (byCompanion != null) return byCompanion;
    for (final c in values) {
      if (c.avatarId == avatar) return c;
    }
    return null;
  }
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
abstract class AvatarStateSource {
  Stream<AvatarStateEvent> get events;
  void dispose();
}

/// The live source: starts session [sessionId], then passes on [updates]
/// (ChatController.avatarEvents: the chat stream's companion_state
/// {emotion, intensity} and the thinking / speaking / idle state).
class StreamAvatarStateSource implements AvatarStateSource {
  StreamAvatarStateSource(this.sessionId, this.updates);

  final String sessionId;
  final Stream<AvatarStateEvent> updates;

  // A plain controller rather than `async* { yield ...; yield* updates; }`:
  // cancelling that generator's subscription never completed in tests.
  @override
  Stream<AvatarStateEvent> get events {
    StreamSubscription<AvatarStateEvent>? sub;
    late final StreamController<AvatarStateEvent> out;
    out = StreamController<AvatarStateEvent>(
      onListen: () {
        out.add(AvatarSessionStarted(sessionId));
        sub = updates.listen(out.add, onDone: out.close);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  void dispose() {}
}

/// Never emits (no signed-in chat).
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
