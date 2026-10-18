import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/emotion.dart';

void main() {
  test('ATC-M2-29 the web union, in one place', () {
    expect(Emotion.values.map((e) => e.wire), [
      'happy',
      'sad',
      'anxious',
      'calm',
      'neutral',
    ]);
  });

  test(
    'ATC-M2-29 normalizeEmotion: known pass through, unknown/non-string → neutral',
    () {
      for (final e in Emotion.values) {
        expect(normalizeEmotion(e.wire), e);
      }
      expect(normalizeEmotion('joy'), Emotion.neutral);
      expect(normalizeEmotion('HAPPY'), Emotion.neutral);
      expect(normalizeEmotion(null), Emotion.neutral);
      expect(normalizeEmotion(3), Emotion.neutral);
    },
  );

  test('ATC-M2-29 fromWire for stored values', () {
    expect(Emotion.fromWire('calm'), Emotion.calm);
    expect(Emotion.fromWire('??'), Emotion.neutral);
  });
}
