import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/core/onboarding_store.dart';

void main() {
  test('uses the web key and value (onboarding.ts)', () async {
    final kv = MemoryKeyValueStore();
    final store = OnboardingStore(kv);
    expect(store.isComplete, isFalse);

    var notified = 0;
    store.addListener(() => notified++);
    await store.markComplete();

    expect(kv.values, {'koi_onboarding_complete': 'true'});
    expect(store.isComplete, isTrue);
    expect(notified, 1);
  });

  test("only the exact string 'true' counts as complete", () {
    for (final v in ['TRUE', '1', 'yes', '']) {
      final store = OnboardingStore(
        MemoryKeyValueStore({OnboardingStore.key: v}),
      );
      expect(store.isComplete, isFalse, reason: v);
    }
  });
}
