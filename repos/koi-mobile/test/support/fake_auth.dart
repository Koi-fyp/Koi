import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_mobile/app/providers.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/core/onboarding_store.dart';
import 'package:koi_mobile/onboarding/onboarding_service.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';

import 'chat_fakes.dart';

/// Scriptable AuthService for routing tests.
class FakeAuthService extends AuthService {
  FakeAuthService({
    this.fakeUser,
    this.fakeLoading = false,
    this.fakeError,
    this.fakeRestored = true,
    this.fakeToken,
  });

  bool fakeRestored;

  /// null = no Firebase user (getIdToken throws, like the stand-in).
  String? fakeToken;

  @override
  bool get sessionRestored => fakeRestored;

  @override
  Future<String> getIdToken() async =>
      fakeToken ?? (throw StateError('no Firebase user'));

  KoiUser? fakeUser;
  bool fakeLoading;
  Object? fakeError;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  KoiUser? get user => fakeUser;
  @override
  bool get loading => fakeLoading;
  @override
  Object? get error => fakeError;

  void set({KoiUser? user, bool? loading, Object? error}) {
    fakeUser = user;
    fakeLoading = loading ?? fakeLoading;
    fakeError = error;
    notifyListeners();
  }

  @override
  Future<void> signInAnonymously() async {
    signInCalls++;
    set(user: const KoiUser(uid: 'u1', isAnonymous: true), loading: false);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    set(user: null, loading: false);
  }
}

List<Override> overridesFor(
  AuthService auth,
  OnboardingStore onboarding, {
  OnboardingUserWriter? users,
  SettingsPrefsStore? settings,
}) => [
  authServiceProvider.overrideWith((ref) => auth),
  onboardingStoreProvider.overrideWith((ref) => onboarding),
  onboardingUserWriterProvider.overrideWithValue(
    users ?? RecordingUserWriter(),
  ),
  settingsPrefsStoreProvider.overrideWithValue(
    settings ?? MemorySettingsPrefsStore(),
  ),
  ...chatOverrides(),
];

/// Records local user-record writes (stands in for flutter_lib's Hive box).
class RecordingUserWriter implements OnboardingUserWriter {
  RecordingUserWriter({this.fail = false});
  final bool fail;
  final saved = <(String, OnboardingData)>[];

  @override
  Future<void> save(String uid, OnboardingData data) async {
    if (fail) throw StateError('disk full');
    saved.add((uid, data));
  }
}

OnboardingStore onboardingStore({bool complete = false}) => OnboardingStore(
  MemoryKeyValueStore({if (complete) OnboardingStore.key: 'true'}),
);
