import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/call_inputs.dart';

void main() {
  const text = CallInputs();
  const voice = CallInputs(modality: CallModality.voice);
  const textCam = CallInputs(camera: true);
  const voiceCam = CallInputs(modality: CallModality.voice, camera: true);

  test('starts as text only', () {
    expect(CallInputs.initial, text);
    expect(text.textOn, isTrue);
    expect(text.micOn, isFalse);
    expect(text.cameraOn, isFalse);
  });

  test('exactly the four allowed combinations', () {
    expect(
      CallInputs.allowed,
      unorderedEquals([text, voice, textCam, voiceCam]),
    );
  });

  test('mic on turns typing off; mic off goes back to text', () {
    expect(text.toggleMic(), voice);
    expect(voice.toggleMic(), text);
    expect(textCam.toggleMic(), voiceCam);
    expect(voiceCam.toggleMic(), textCam);
  });

  test('text chat turns the mic off and keeps the camera', () {
    expect(voice.selectText(), text);
    expect(voiceCam.selectText(), textCam);
    expect(text.selectText(), text); // already on: no change
    expect(textCam.selectText(), textCam);
  });

  test('camera toggles alongside whichever input is on', () {
    expect(text.toggleCamera(), textCam);
    expect(textCam.toggleCamera(), text);
    expect(voice.toggleCamera(), voiceCam);
    expect(voiceCam.toggleCamera(), voice);
  });

  test('mic and typing are never on together', () {
    for (final s in CallInputs.allowed) {
      expect(s.micOn && s.textOn, isFalse, reason: '$s');
      expect(s.micOn || s.textOn, isTrue, reason: '$s');
    }
  });

  test('every action from every state stays allowed (camera never alone)', () {
    // Breadth-first over all actions: the reachable set is exactly allowed.
    final seen = <CallInputs>{CallInputs.initial};
    final queue = [CallInputs.initial];
    while (queue.isNotEmpty) {
      final s = queue.removeLast();
      for (final next in [s.toggleMic(), s.selectText(), s.toggleCamera()]) {
        expect(CallInputs.allowed, contains(next), reason: '$s -> $next');
        expect(next.cameraOn && !next.micOn && !next.textOn, isFalse);
        if (seen.add(next)) queue.add(next);
      }
    }
    expect(seen, CallInputs.allowed.toSet());
  });

  test('value equality', () {
    expect(const CallInputs(camera: true), textCam);
    expect(textCam.hashCode, const CallInputs(camera: true).hashCode);
    expect(text == voice, isFalse);
  });
}
