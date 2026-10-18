import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart' show CameraException;
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/camera/camera_session.dart';

import 'fake_camera.dart';

void main() {
  late FakeLocalCamera camera;
  late CameraSession session;

  setUp(() {
    camera = FakeLocalCamera();
    session = CameraSession(camera);
  });

  group(
    'ATC-M20-13 CameraSession: on only after start(), released by stop()',
    () {
      test(
        'nothing opens until start(); stop() closes and stays off',
        () async {
          expect(session.state, CameraViewState.off);
          await pumpEventQueue();
          expect(camera.opens, 0);

          await session.start();
          expect(session.state, CameraViewState.on);
          expect(camera.isOpen, isTrue);

          session.stop();
          expect(session.state, CameraViewState.off);
          expect(camera.isOpen, isFalse);
          await pumpEventQueue();
          expect(camera.opens, 1, reason: 'never restarts on its own');
        },
      );

      test(
        'a permission refusal → denied, released; other errors → error',
        () async {
          for (final code in CameraSession.deniedCodes) {
            camera.error = CameraException(code, 'no');
            await session.start();
            expect(session.state, CameraViewState.denied, reason: code);
            expect(camera.isOpen, isFalse);
          }
          camera.error = CameraException('cameraNotReadable', 'busy');
          await session.start();
          expect(session.state, CameraViewState.error);
          camera.error = const NoFrontCameraException();
          await session.start();
          expect(session.state, CameraViewState.noDevice);
          camera.error = StateError('x');
          await session.start();
          expect(session.state, CameraViewState.error);
          expect(camera.closes, camera.opens, reason: 'every failure released');
        },
      );

      test('stop() while the open is pending: off at once, the camera is '
          'released when the open ends', () async {
        camera.hold = Completer<void>();
        final started = session.start();
        expect(session.state, CameraViewState.starting);
        expect(session.holdsCamera, isTrue);
        session.stop();
        expect(session.state, CameraViewState.off);
        camera.hold!.complete();
        await started;
        expect(session.state, CameraViewState.off);
        expect(camera.isOpen, isFalse);
        expect(camera.closes, 1);
      });

      test('dispose releases the camera', () async {
        await session.start();
        session.dispose();
        expect(camera.isOpen, isFalse);
      });

      test('texts: the disclosure is Prompt 29\'s exact sentence', () {
        expect(
          CameraTexts.disclosure,
          'This camera view is for you only. KOI does not record, store, send '
          'or analyze your video.',
        );
      });
    },
  );

  group('ATC-M20-14 source guard: preview only, no audio, no capture', () {
    final lib = Directory('lib');
    final dartFiles = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('only lib/camera/camera_session.dart imports package:camera', () {
      final importers = [
        for (final f in dartFiles)
          if (f.readAsStringSync().contains("import 'package:camera/"))
            f.path.replaceAll('\\', '/'),
      ];
      expect(importers, ['lib/camera/camera_session.dart']);
    });

    test('no recording, picture, frame stream or upload API is called', () {
      final banned = RegExp(
        r'\.(takePicture|startVideoRecording|prepareForVideoRecording|'
        r'startImageStream|resumeVideoRecording|stopVideoRecording)\(',
      );
      for (final f in dartFiles) {
        expect(banned.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });

    test('front lens, enableAudio: false', () {
      final src = File('lib/camera/camera_session.dart').readAsStringSync();
      expect(src, contains('CameraLensDirection.front'));
      expect(src, contains('enableAudio: false'));
    });
  });
}
