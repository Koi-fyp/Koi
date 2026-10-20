import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_mobile/account/account_providers.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/account/secret_store.dart';
import 'package:koi_mobile/app/providers.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/checkins/checkin_providers.dart';
import 'package:koi_mobile/checkins/checkin_store.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/core/onboarding_store.dart';
import 'package:koi_mobile/core/sync_queue.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/experts/expert_api.dart';
import 'package:koi_mobile/questionnaires/draft_store.dart';
import 'package:koi_mobile/questionnaires/questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_providers.dart';

import 'chat_fakes.dart';
import 'fake_auth.dart';

/// A reversible cipher that, unlike FakeCipher, only opens a payload with
/// the SAME secret it was made with (like AES-GCM's MAC check).
class SecretCipher implements MessageCipher {
  int encrypts = 0;

  @override
  Future<String> encrypt(
    String plaintext,
    String secret,
    String saltB64,
  ) async {
    encrypts++;
    final tag = base64Encode(utf8.encode('$secret|$saltB64'));
    return 'v1:SEC:$tag:${base64Encode(utf8.encode(plaintext).reversed.toList())}';
  }

  @override
  Future<String> decrypt(String payload, String secret) async {
    final parts = payload.split(':');
    if (parts.length != 4 || parts[1] != 'SEC') {
      throw const FormatException('bad');
    }
    final tag = utf8.decode(base64Decode(parts[2]));
    if (tag.split('|').first != secret) throw StateError('MAC check failed');
    return utf8.decode(base64Decode(parts[3]).reversed.toList());
  }

  /// Which secret a payload was made with (test helper).
  static String secretOf(String payload) =>
      utf8.decode(base64Decode(payload.split(':')[2])).split('|').first;
}

/// FakeAuthService plus scriptable email accounts.
class AccountFakeAuth extends FakeAuthService {
  AccountFakeAuth({super.fakeUser, super.fakeToken = 'token'});

  /// email → (uid, password)
  final Map<String, (String, String)> accounts = {};
  final _tokens = StreamController<void>.broadcast();
  AccountAuthError? failNextLink;

  /// AUTH-ENTRY: the next link / sign-in / create / reset call fails.
  AccountAuthError? failNext;

  /// Emails a password reset was requested for.
  final List<String> resetEmails = [];
  int reauthCalls = 0;

  /// Holds the next account calls until completed (to see the loader).
  Completer<void>? callGate;

  Future<void> _maybeFail() async {
    final g = callGate;
    if (g != null) await g.future;
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw AccountAuthException(f);
    }
  }

  int refreshCalls = 0;

  void fireTokenChange() => _tokens.add(null);

  @override
  Stream<void> get tokenChanges => _tokens.stream;

  @override
  Future<String> refreshIdToken() async {
    refreshCalls++;
    return 'token-refreshed-$refreshCalls';
  }

  static KoiUser registered(String uid, String email) => KoiUser(
    uid: uid,
    isAnonymous: false,
    providerIds: const ['password'],
    email: email,
  );

  @override
  Future<void> linkWithEmail(String email, String password) async {
    final f = failNextLink;
    if (f != null) {
      failNextLink = null;
      throw AccountAuthException(f);
    }
    await _maybeFail();
    if (accounts.containsKey(email)) {
      throw const AccountAuthException(AccountAuthError.emailInUse);
    }
    final uid = user!.uid;
    accounts[email] = (uid, password);
    set(user: registered(uid, email));
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await _maybeFail();
    final a = accounts[email];
    if (a == null || a.$2 != password) {
      throw const AccountAuthException(AccountAuthError.wrongCredentials);
    }
    set(user: registered(a.$1, email));
  }

  @override
  Future<void> createAccountWithEmail(String email, String password) async {
    await _maybeFail();
    if (accounts.containsKey(email)) {
      throw const AccountAuthException(AccountAuthError.emailInUse);
    }
    final uid = 'new-${accounts.length}';
    accounts[email] = (uid, password);
    set(user: registered(uid, email));
  }

  @override
  Future<void> reauthenticate(String password) async {
    reauthCalls++;
    final email = user?.email;
    final a = email == null ? null : accounts[email];
    if (a == null || a.$2 != password) {
      throw const AccountAuthException(AccountAuthError.wrongCredentials);
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    await _maybeFail();
    resetEmails.add(email);
  }
}

/// Capabilities per uid; [gate] (when set) holds every fetch until
/// completed, to observe the loading state.
class ScriptedCapabilitiesSource implements CapabilitiesSource {
  ScriptedCapabilitiesSource([Map<String, KoiCapabilities>? byUid])
    : byUid = {...?byUid};

  final Map<String, KoiCapabilities> byUid;
  Object? error;
  Completer<void>? gate;
  int fetches = 0;
  bool mock = false;

  @override
  bool get isMock => mock;

  @override
  Future<KoiCapabilities> fetch(String uid) async {
    fetches++;
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return byUid[uid] ?? KoiCapabilities.none;
  }
}

const KoiCapabilities generalCaps = KoiCapabilities(
  role: KoiRole.general,
  expertDiscovery: true,
);

const KoiCapabilities patientCaps = KoiCapabilities(
  role: KoiRole.patient,
  expertDiscovery: true,
  questionnaires: true,
  relationship: RelationshipSummary(
    id: 'rel-1',
    active: true,
    psychologistDisplayName: 'Test Psychologist',
  ),
);

const KoiCapabilities psychologistCaps = KoiCapabilities(
  role: KoiRole.psychologist,
);

/// A resolver whose "Firestore" salt is salt-{uid}; never touches the
/// network. Call FlutterSecureStorage.setMockInitialValues({}) first.
CryptoContextResolver fakeResolver(AccountSecretStore secrets) =>
    CryptoContextResolver(
      anonymousSecret: secrets.anonymousSecret,
      fetchSalt: (uid) async => 'salt-$uid',
      createSaltOnce: (uid, candidate) async => 'salt-$uid',
      isOnline: () async => true,
      syncQueue: RecordingSyncQueue(),
      saltCache: SaltCache(onReplaced: () {}),
    );

/// Everything a MOB-1 widget test needs, wired to in-memory fakes.
class Mob1Harness {
  Mob1Harness({
    KoiUser? user,
    Map<String, KoiCapabilities>? caps,
    bool onboarded = true,
    QuestionnaireApi? questionnaires,
    ExpertDirectoryApi? experts,
    this.capabilities,
    this.chatApi,
  }) : auth = AccountFakeAuth(fakeUser: user),
       source = ScriptedCapabilitiesSource(caps),
       questionnaireApi = questionnaires,
       expertApi = experts {
    if (onboarded) {
      for (final uid in ['u1', 'u2', 'a1', 'b1', 'p1', 'g1', 'psy']) {
        prefs.values[OnboardingStore.keyFor(uid)] = 'true';
      }
    }
  }

  final AccountFakeAuth auth;
  final ScriptedCapabilitiesSource source;
  final QuestionnaireApi? questionnaireApi;
  final ExpertDirectoryApi? expertApi;

  /// MOB-2: replaces [source] (e.g. a MockCapabilitiesSource driven by the
  /// demo care backend).
  final CapabilitiesSource? capabilities;

  /// MOB-2: the companion chat client (to prove nothing reaches it).
  final ChatApiClient? chatApi;
  final MemorySettingsPrefsStore settings = MemorySettingsPrefsStore();
  final MemorySecureKv secureKv = MemorySecureKv();
  late final AccountSecretStore secrets = AccountSecretStore(secureKv);
  final MemoryKeyValueStore prefs = MemoryKeyValueStore();
  final MemoryMessageStore messages = MemoryMessageStore();
  final MemoryCheckInBox checkIns = MemoryCheckInBox();
  final MemoryDraftBox drafts = MemoryDraftBox();
  final SecretCipher cipher = SecretCipher();
  final RecordingSyncQueue queue = RecordingSyncQueue();

  late final OnboardingStore onboarding = OnboardingStore(prefs);

  List<Override> get overrides => [
    authServiceProvider.overrideWith((ref) => auth),
    onboardingStoreProvider.overrideWith((ref) => onboarding),
    onboardingUserWriterProvider.overrideWithValue(RecordingUserWriter()),
    settingsPrefsStoreProvider.overrideWithValue(settings),
    ...chatOverrides(
      store: messages,
      queue: queue,
      cipher: cipher,
      api: chatApi,
    ),
    cryptoContextResolverProvider.overrideWithValue(fakeResolver(secrets)),
    accountSecretStoreProvider.overrideWithValue(secrets),
    localPrefsProvider.overrideWithValue(prefs),
    checkInBoxProvider.overrideWithValue(checkIns),
    draftBoxProvider.overrideWithValue(drafts),
    capabilitiesSourceProvider.overrideWithValue(capabilities ?? source),
    if (questionnaireApi != null)
      questionnaireApiProvider.overrideWithValue(questionnaireApi!),
    if (expertApi != null)
      expertDirectoryApiProvider.overrideWithValue(expertApi!),
  ];
}

/// A queued item's owner + doc id, for assertions.
String itemKey(SyncItem i) => '${i.collection}/${i.docId}';
