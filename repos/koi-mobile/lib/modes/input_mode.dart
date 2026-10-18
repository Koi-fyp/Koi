import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart' show authServiceProvider;
import '../avatar/avatar_providers.dart' show selectedAvatarProvider;
import '../avatar/avatar_state.dart' show CompanionAvatar;
import '../core/key_value_store.dart';

/// How the user talks to the companion (Prompt 29, Ahmad's voice/camera
/// pathway 2026-10-18; web reference origin/avatar/vrm-emotion
/// contexts/InputModeContext.tsx). One setting per uid, local only.
enum KoiInputMode {
  text('text', 'Text'),
  voice('voice', 'Voice'),
  camera('camera', 'Camera view'),
  cameraVoice('camera-voice', 'Camera view + voice');

  const KoiInputMode(this.id, this.label);

  /// Stored value.
  final String id;

  /// Shown in the mode menus (exact labels, Prompt 29).
  final String label;

  /// The call screen's Mic button.
  bool get micInput => this == voice || this == cameraVoice;

  /// Completed replies are read out on the call screen.
  bool get spokenReplies => this == voice || this == cameraVoice;

  /// The call screen's local camera preview.
  bool get cameraView => this == camera || this == cameraVoice;

  static KoiInputMode? fromId(String? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// `koi_input_mode_{uid}` in `koi_local_prefs`. New users start on Text.
///
/// Existing users are migrated once from the Prompt 25 voice switch
/// (`koi_voice_enabled_{uid}`): 'true' → Voice, 'false' → Text; never set
/// but the call screen was used → Voice. The only stored trace of call
/// screen use is the Prompt 26 mic consent / denial (`koi_mic_consent_{uid}`,
/// `koi_mic_denied_{uid}`). The old key is then deleted.
class ModePrefs {
  ModePrefs(this._store);

  static const String key = 'koi_input_mode';
  static String keyFor(String uid) => '${key}_$uid';

  static String legacyVoiceKey(String uid) => 'koi_voice_enabled_$uid';
  static String legacyMicConsentKey(String uid) => 'koi_mic_consent_$uid';
  static String legacyMicDeniedKey(String uid) => 'koi_mic_denied_$uid';

  final KeyValueStore _store;

  KoiInputMode load(String uid) {
    final saved = KoiInputMode.fromId(_store.get(keyFor(uid)));
    if (saved != null) return saved;
    final voice = _store.get(legacyVoiceKey(uid));
    final usedCall =
        _store.get(legacyMicConsentKey(uid)) != null ||
        _store.get(legacyMicDeniedKey(uid)) != null;
    final mode = voice == 'true' || (voice == null && usedCall)
        ? KoiInputMode.voice
        : KoiInputMode.text;
    unawaited(() async {
      try {
        await _store.put(keyFor(uid), mode.id);
        if (voice != null) await _store.delete(legacyVoiceKey(uid));
      } catch (_) {}
    }());
    return mode;
  }

  Future<void> save(String uid, KoiInputMode mode) =>
      _store.put(keyFor(uid), mode.id);
}

/// The saved mode of one uid.
class InputModeController extends ChangeNotifier {
  InputModeController(this.uid, this._prefs) : _mode = _prefs.load(uid);

  final String uid;
  final ModePrefs _prefs;
  KoiInputMode _mode;

  KoiInputMode get mode => _mode;

  void select(KoiInputMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    unawaited(_prefs.save(uid, mode).catchError((_) {}));
  }
}

/// Overridden in main.dart with the `koi_local_prefs` box; in memory
/// otherwise (tests).
final modePrefsProvider = Provider<ModePrefs>(
  (ref) => ModePrefs(MemoryKeyValueStore()),
);

final inputModeControllerProvider =
    ChangeNotifierProvider.family<InputModeController, String>(
      (ref, uid) => InputModeController(uid, ref.read(modePrefsProvider)),
    );

/// Koi's fox chats by text only (Ahmad): the other modes are disabled and
/// the saved mode is kept for Raza / Aisha.
final foxTextOnlyProvider = Provider<bool>(
  (ref) => ref.watch(selectedAvatarProvider).valueOrNull == CompanionAvatar.koi,
);

/// The mode in force: Text while signed out or for the fox, otherwise the
/// saved mode.
final effectiveInputModeProvider = Provider<KoiInputMode>((ref) {
  final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
  if (uid == null || ref.watch(foxTextOnlyProvider)) return KoiInputMode.text;
  return ref.watch(inputModeControllerProvider(uid)).mode;
});
