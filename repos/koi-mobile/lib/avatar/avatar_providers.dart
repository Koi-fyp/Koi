import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../settings/settings_prefs.dart';
import 'avatar_source.dart';
import 'avatar_state.dart';
import 'avatar_web_page.dart';
import 'local_avatar_server.dart';

/// From KOI_AVATAR_URL. Overridden in tests.
final avatarSourceProvider = Provider<AvatarSource>(
  (ref) => AvatarSource.parse(koiAvatarUrl),
);

/// Makes the avatar WebView page. Overridden in tests with a fake.
final avatarWebPageFactoryProvider = Provider<AvatarWebPageFactory>(
  (ref) => WebViewAvatarPage.new,
);

/// Makes the loopback server for KOI_AVATAR_URL=local. Overridden in tests.
final avatarLocalHostFactoryProvider = Provider<LocalAvatarHostFactory>(
  (ref) => LocalAvatarServer.new,
);

/// Whether the call screen uses the emotion simulator instead of the chat
/// stream: only for the mock page in a debug build when there is no chat
/// service to drive it (KOI_API_BASE empty or invalid).
bool useSimulatedAvatar({
  required bool mock,
  required bool chatConfigured,
  bool debug = kDebugMode,
}) => mock && debug && !chatConfigured;

/// Makes the call screen's conversation-state source (the screen disposes
/// it): the signed-in chat's stream (companion_state + thinking / speaking /
/// idle), or the simulator stepping through the emotions (see
/// [useSimulatedAvatar]).
final avatarStateSourceFactoryProvider = Provider<AvatarStateSource Function()>(
  (ref) {
    final mock = ref.watch(avatarSourceProvider) == AvatarSource.mock;
    return () {
      final simulated = useSimulatedAvatar(
        mock: mock,
        chatConfigured: ref.read(chatApiProvider).isConfigured,
      );
      if (simulated) return SimulatedAvatarStateSource.cycling();
      final uid = ref.read(authServiceProvider).user?.uid;
      if (uid == null) return NoAvatarStateSource();
      final chat = ref.read(chatControllerProvider(uid));
      return StreamAvatarStateSource(chat.conversationId, chat.avatarEvents);
    };
  },
);

/// The signed-in user's companion and its avatar, shared live by the Chat
/// card, the call screen and Settings (web 223e97c
/// hooks/useAvatarPreference.ts: loading / error / ready). The avatar always
/// follows the saved companion (lib/avatar/avatarPreference.ts:20-28).
final selectedAvatarProvider =
    NotifierProvider<SelectedAvatarNotifier, AsyncValue<CompanionAvatar>>(
      SelectedAvatarNotifier.new,
    );

class SelectedAvatarNotifier extends Notifier<AsyncValue<CompanionAvatar>> {
  bool _chosen = false;

  @override
  AsyncValue<CompanionAvatar> build() {
    _chosen = false;
    final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
    if (uid != null) _load(uid);
    return const AsyncLoading();
  }

  Future<void> _load(String uid) async {
    final store = ref.read(settingsPrefsStoreProvider);
    final SettingsPrefs prefs;
    try {
      prefs = await store.load(uid);
    } catch (e, st) {
      debugPrint('KOI: avatar choice not loaded: ${e.runtimeType}');
      if (ref.read(authServiceProvider).user?.uid == uid && !_chosen) {
        state = AsyncError(e, st);
      }
      return;
    }
    if (ref.read(authServiceProvider).user?.uid != uid || _chosen) return;
    state = AsyncData(prefs.avatar);
    // Records saved before the companion picked the avatar (onboarding
    // always wrote male_human): store the matching avatar once, locally and
    // (through SyncingSettingsPrefsStore) as Firestore profile.avatar.
    if (!prefs.avatarOutOfDate) return;
    try {
      await store.save(uid, prefs);
    } catch (e) {
      debugPrint('KOI: avatar repair not saved: ${e.runtimeType}');
    }
  }

  /// The companion picker saved [companion] (the caller saves the prefs).
  void select(CompanionAvatar companion) {
    _chosen = true;
    state = AsyncData(companion);
  }
}
