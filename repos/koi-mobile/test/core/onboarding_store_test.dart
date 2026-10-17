import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/core/onboarding_store.dart';

void main() {
  test('per-uid key and the web value (onboarding.ts)', () async {
    final kv = MemoryKeyValueStore();
    final store = OnboardingStore(kv);
    expect(store.isCompleteFor('u1'), isFalse);

    var notified = 0;
    store.addListener(() => notified++);
    await store.markComplete('u1');

    expect(kv.values, {'koi_onboarding_complete_u1': 'true'});
    expect(store.isCompleteFor('u1'), isTrue);
    expect(notified, 1);
  });

  test('same uid stays complete; a new uid is not complete', () async {
    final store = OnboardingStore(MemoryKeyValueStore());
    await store.markComplete('u1');
    expect(store.isCompleteFor('u1'), isTrue);
    expect(store.isCompleteFor('u2'), isFalse);
    expect(store.isCompleteFor(null), isFalse);
  });

  test("only the exact string 'true' counts as complete", () {
    for (final v in ['TRUE', '1', 'yes', '']) {
      final store = OnboardingStore(
        MemoryKeyValueStore({OnboardingStore.keyFor('u1'): v}),
      );
      expect(store.isCompleteFor('u1'), isFalse, reason: v);
    }
  });

  group('migrateDeviceFlag (old per-device flag)', () {
    test('goes to the persisted debug uid only; device key removed', () async {
      final kv = MemoryKeyValueStore({OnboardingStore.key: 'true'});
      final store = OnboardingStore(kv);
      await store.migrateDeviceFlag('debug-abc');
      expect(store.isCompleteFor('debug-abc'), isTrue);
      expect(store.isCompleteFor('firebase-uid'), isFalse);
      expect(kv.values.containsKey(OnboardingStore.key), isFalse);
    });

    test('no debug uid → dropped, nobody inherits it', () async {
      final kv = MemoryKeyValueStore({OnboardingStore.key: 'true'});
      final store = OnboardingStore(kv);
      await store.migrateDeviceFlag(null);
      expect(kv.values, isEmpty);
    });

    test('not "true" → nothing marked; no flag → no-op', () async {
      final kv = MemoryKeyValueStore({OnboardingStore.key: 'yes'});
      await OnboardingStore(kv).migrateDeviceFlag('debug-abc');
      expect(kv.values, isEmpty);

      final empty = MemoryKeyValueStore({OnboardingStore.keyFor('u1'): 'true'});
      await OnboardingStore(empty).migrateDeviceFlag('debug-abc');
      expect(empty.values, {OnboardingStore.keyFor('u1'): 'true'});
    });
  });
}
