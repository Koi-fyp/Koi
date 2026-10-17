import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'avatar_source.dart';
import 'avatar_state.dart';
import 'avatar_web_page.dart';

/// From KOI_AVATAR_URL. Overridden in tests.
final avatarSourceProvider = Provider<AvatarSource>(
  (ref) => AvatarSource.parse(koiAvatarUrl),
);

/// Makes the avatar WebView page. Overridden in tests with a fake.
final avatarWebPageFactoryProvider = Provider<AvatarWebPageFactory>(
  (ref) => WebViewAvatarPage.new,
);

/// Makes the call screen's conversation-state source (the screen disposes
/// it): the signed-in chat's stream (companion_state + thinking / speaking /
/// idle), or with the mock page in a debug build, the simulator stepping
/// through the emotions.
final avatarStateSourceFactoryProvider = Provider<AvatarStateSource Function()>(
  (ref) {
    final mock = ref.watch(avatarSourceProvider) == AvatarSource.mock;
    return () {
      if (mock && kDebugMode) return SimulatedAvatarStateSource.cycling();
      final uid = ref.read(authServiceProvider).user?.uid;
      if (uid == null) return NoAvatarStateSource();
      final chat = ref.read(chatControllerProvider(uid));
      return StreamAvatarStateSource(chat.conversationId, chat.avatarEvents);
    };
  },
);

/// The signed-in user's avatar (HiveUser.avatarType), shared live by the
/// Chat card, the call screen and Settings.
final selectedAvatarProvider =
    NotifierProvider<SelectedAvatarNotifier, AvatarType>(
      SelectedAvatarNotifier.new,
    );

class SelectedAvatarNotifier extends Notifier<AvatarType> {
  bool _chosen = false;

  @override
  AvatarType build() {
    _chosen = false;
    final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
    if (uid != null) _load(uid);
    return AvatarType.male;
  }

  Future<void> _load(String uid) async {
    try {
      final prefs = await ref.read(settingsPrefsStoreProvider).load(uid);
      final stillSame = ref.read(authServiceProvider).user?.uid == uid;
      if (stillSame && !_chosen) state = prefs.avatarType;
    } catch (e) {
      debugPrint('KOI: avatar choice not loaded: ${e.runtimeType}');
    }
  }

  /// Settings changed it (Settings saves it with the other prefs).
  void select(AvatarType avatar) {
    _chosen = true;
    state = avatar;
  }
}
