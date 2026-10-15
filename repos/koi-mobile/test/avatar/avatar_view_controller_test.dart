import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_view.dart';

void main() {
  test('AvatarEmotion is exactly the avatar set', () {
    expect(AvatarEmotion.values.map((e) => e.name), [
      'neutral',
      'joy',
      'angry',
      'sorrow',
      'fun',
    ]);
  });

  test('starts neutral, loading', () {
    final c = AvatarViewController();
    expect(c.emotion, AvatarEmotion.neutral);
    expect(c.intensity, 0);
    expect(c.status, AvatarStatus.loading);
    expect(c.isReady, isFalse);
  });

  test('setEmotion stores, clamps 0..1, and rejects NaN', () {
    final c = AvatarViewController();
    var notified = 0;
    c.addListener(() => notified++);

    c.setEmotion(AvatarEmotion.joy, 0.7);
    expect((c.emotion, c.intensity), (AvatarEmotion.joy, 0.7));
    c.setEmotion(AvatarEmotion.joy, 0.7); // same: no notification
    expect(notified, 1);

    c.setEmotion(AvatarEmotion.angry, 2);
    expect(c.intensity, 1.0);
    c.setEmotion(AvatarEmotion.sorrow, -0.5);
    expect(c.intensity, 0.0);
    expect(
      () => c.setEmotion(AvatarEmotion.fun, double.nan),
      throwsArgumentError,
    );
    expect(c.emotion, AvatarEmotion.sorrow);
  });

  test('status: ready, failed, reconnect', () {
    final c = AvatarViewController();
    c.markReady();
    expect(c.isReady, isTrue);
    c.markFailed();
    expect(c.status, AvatarStatus.failed);
    c.reconnect();
    expect(c.status, AvatarStatus.loading);
  });
}
