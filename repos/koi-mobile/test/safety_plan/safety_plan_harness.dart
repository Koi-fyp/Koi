import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/app/providers.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_controller.dart';
import 'package:koi_mobile/safety/safety_providers.dart';
import 'package:koi_mobile/safety_plan/safety_plan_models.dart';
import 'package:koi_mobile/safety_plan/safety_plan_providers.dart';
import 'package:koi_mobile/safety_plan/safety_plan_store.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';

import '../support/chat_fakes.dart';
import '../support/fake_auth.dart';
import '../support/mob1_fakes.dart';

/// Everything a safety plan widget test needs, in memory: the signed-in
/// user, the plan box (SecretCipher, a different secret per uid), the
/// Settings language, a recording sync queue and the safety controller.
class PlanEnv {
  PlanEnv({String uid = 'u1', String? language})
    : auth = FakeAuthService(fakeUser: KoiUser(uid: uid, isAnonymous: true)),
      settings = MemorySettingsPrefsStore({
        if (language != null) uid: SettingsPrefs(language: language),
      }) {
    safety = SafetyController(
      onClientEvent: events.add,
      onCrisisPath: paths.add,
    );
  }

  /// Replaced by a new one (same user) on every [overrides] call: the
  /// ProviderScope disposes it with the page.
  FakeAuthService auth;
  final MemorySettingsPrefsStore settings;
  final box = MemorySafetyPlanBox();
  final cipher = SecretCipher();
  final queue = RecordingSyncQueue();
  final events = <ClientEvent>[];
  final paths = <CrisisPath>[];
  late final SafetyController safety;

  /// When set, every plan decrypt/encrypt context lookup throws.
  Object? cryptoError;

  /// When set, context lookups wait for it (a plan that is still loading).
  Future<void>? cryptoGate;

  List<Override> overrides({bool onboardingDone = true}) {
    auth = FakeAuthService(fakeUser: auth.fakeUser);
    return _overrides(onboardingDone);
  }

  List<Override> _overrides(bool onboardingDone) => [
    ...overridesFor(
      auth,
      onboardingStore(complete: onboardingDone),
      settings: settings,
    ),
    // chatOverrides() without its crypto context (one per uid here).
    onlineStatusProvider.overrideWithValue(FakeOnlineStatus()),
    messageStoreProvider.overrideWithValue(MemoryMessageStore()),
    syncQueueProvider.overrideWithValue(queue),
    messageCipherProvider.overrideWithValue(cipher),
    chatApiProvider.overrideWithValue(ChatApiClient(baseUrl: '')),
    cryptoContextGetterProvider.overrideWithValue((uid) async {
      final gate = cryptoGate;
      if (gate != null) await gate;
      final e = cryptoError;
      if (e != null) throw e;
      return CryptoContext(secret: 'sec-$uid', saltB64: 's');
    }),
    safetyPlanBoxProvider.overrideWithValue(box),
    safetyPlanClockProvider.overrideWithValue(() => DateTime(2026, 10, 20, 9)),
    safetyControllerProvider.overrideWith((ref) => safety),
  ];

  SafetyPlanRepository repo() => SafetyPlanRepository(
    box: box,
    cipher: cipher,
    cryptoContext: (uid) async =>
        CryptoContext(secret: 'sec-$uid', saltB64: 's'),
  );

  Future<void> seed(String uid, SafetyPlan plan) =>
      repo().save(uid, plan, DateTime(2026, 10, 20, 8));
}

final SafetyPlan samplePlan = SafetyPlan(
  items: {
    SafetyPlanSection.warningSigns: [
      const SafetyPlanItem(id: 'w1', text: 'Not sleeping'),
    ],
    SafetyPlanSection.peopleToAsk: [
      const SafetyPlanItem(id: 'p1', text: 'My sister', phone: '0321 7654321'),
    ],
    SafetyPlanSection.reasons: [
      const SafetyPlanItem(id: 'r1', text: 'میری بہن'),
    ],
  },
);

/// Phone sizes in logical pixels.
Future<void> setPhone(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.reset);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}
