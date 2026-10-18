import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../avatar/avatar_state.dart' show MouthCue;
import '../chat/chat_api.dart';
import 'speech_api.dart';
import 'speech_source.dart';
import 'voice_controller.dart';

final speechApiProvider = Provider<SpeechApiClient>(
  (ref) => SpeechApiClient(baseUrl: koiSpeechBase),
);

/// The speech service's `GET /health` (same redirect handling as chat).
final speechHealthClientProvider = Provider<ChatApiClient>(
  (ref) => ChatApiClient(baseUrl: koiSpeechBase),
);

final speechWarmupProvider = Provider<SpeechWarmup>((ref) {
  final client = ref.watch(speechHealthClientProvider);
  return SpeechWarmup(health: client.isConfigured ? client.checkHealth : null);
});

/// 10 requests/min, per signed-in user.
final speechRateLimiterProvider = Provider<SpeechRateLimiter>((ref) {
  ref.watch(authServiceProvider.select((a) => a.user?.uid));
  return SpeechRateLimiter();
});

/// Platform audio and text-to-speech; tests override these.
final clipPlayerFactoryProvider = Provider<ClipPlayer Function()>(
  (ref) => AudioplayersClipPlayer.new,
);
final ttsEngineFactoryProvider = Provider<TtsEngine Function()>(
  (ref) => FlutterTtsEngine.new,
);

/// A new VoiceController for the call screen.
final voiceControllerFactoryProvider =
    Provider<
      VoiceController Function({
        required void Function(List<MouthCue> cues) onMouth,
      })
    >((ref) {
      return ({required onMouth}) {
        final api = ref.read(speechApiProvider);
        final warmup = ref.read(speechWarmupProvider);
        return VoiceController(
          server: api.isConfigured
              ? ServerSpeechSource(
                  api: api,
                  idToken: () => ref.read(authServiceProvider).getIdToken(),
                  player: ref.read(clipPlayerFactoryProvider)(),
                  limiter: ref.read(speechRateLimiterProvider),
                )
              : null,
          device: DeviceSpeechSource(ref.read(ttsEngineFactoryProvider)()),
          serverUnavailable: () => warmup.isUnavailable,
          onMouth: onMouth,
        );
      };
    });
