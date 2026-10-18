import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// Prompt 29 texts. [disclosure] and the messages are the web reference's
/// (origin/avatar/vrm-emotion lib/camera/cameraPrivacyGuard.ts
/// CAMERA_DISCLOSURE, components/camera/CameraView.tsx MESSAGES).
abstract final class CameraTexts {
  static const String disclosure =
      'This camera view is for you only. KOI does not record, store, send or '
      'analyze your video.';
  static const String on = 'Camera on';
  static const String turnOff = 'Turn off camera';
  static const String starting = 'Starting camera…';
  static const String denied =
      'Camera permission was denied. Text chat still works.';
  static const String noDevice =
      'No camera was found on this device. Text chat still works.';
  static const String error =
      'The camera could not start (it may be in use by another app). Text '
      'chat still works.';

  static String? message(CameraViewState s) => switch (s) {
    CameraViewState.denied => denied,
    CameraViewState.noDevice => noDevice,
    CameraViewState.error => error,
    _ => null,
  };
}

enum CameraViewState { off, starting, on, denied, noDevice, error }

/// The device's front camera as a local preview, and nothing else: no
/// audio track, no recording, no pictures, no frames. Tests replace it.
abstract class LocalCamera {
  /// Opens the front camera. Throws [CameraException] (permission codes
  /// below) or [NoFrontCameraException].
  Future<void> open();

  /// The live preview; only valid between [open] and [close].
  Widget preview();

  /// Releases the camera. Safe to call at any time.
  Future<void> close();
}

class NoFrontCameraException implements Exception {
  const NoFrontCameraException();
}

/// The `camera` plugin (0.12.1): front lens, `enableAudio: false`, only
/// [CameraController.initialize], [CameraPreview] and
/// [CameraController.dispose] are used. takePicture, startVideoRecording
/// and startImageStream are never called (guarded by a source test).
class PluginLocalCamera implements LocalCamera {
  CameraController? _controller;

  @override
  Future<void> open() async {
    final cameras = await availableCameras();
    CameraDescription? front;
    for (final c in cameras) {
      if (c.lensDirection == CameraLensDirection.front) {
        front = c;
        break;
      }
    }
    if (front == null) throw const NoFrontCameraException();
    final controller = _controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();
  }

  @override
  Widget preview() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
    return CameraPreview(c);
  }

  @override
  Future<void> close() async {
    final c = _controller;
    _controller = null;
    try {
      await c?.dispose();
    } catch (_) {}
  }
}

/// One camera view (web cameraSession.ts): starts only from [start] (a
/// tap), [stop] releases the device at once, and a [stop] or newer [start]
/// wins over an open still in progress (its camera is closed when it
/// arrives).
class CameraSession extends ChangeNotifier {
  CameraSession(this.camera);

  final LocalCamera camera;

  /// Codes the Android / iOS plugins use for a refused permission.
  static const Set<String> deniedCodes = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  };

  CameraViewState _state = CameraViewState.off;
  int _token = 0;
  bool _opening = false;
  bool _opened = false;
  bool _disposed = false;

  CameraViewState get state => _state;
  bool get isOn => _state == CameraViewState.on;

  /// True from a [start] until its [stop]: the device may be in use.
  bool get holdsCamera => _opening || _opened;

  void _set(CameraViewState s) {
    if (_state == s || _disposed) return;
    _state = s;
    notifyListeners();
  }

  Future<void> start() async {
    if (_disposed || _opening || _opened) return;
    final mine = ++_token;
    _set(CameraViewState.starting);
    CameraViewState result;
    _opening = true;
    try {
      await camera.open();
      result = CameraViewState.on;
    } on CameraException catch (e) {
      result = deniedCodes.contains(e.code)
          ? CameraViewState.denied
          : CameraViewState.error;
    } on NoFrontCameraException {
      result = CameraViewState.noDevice;
    } catch (_) {
      result = CameraViewState.error;
    }
    _opening = false;
    if (mine != _token || _disposed || result != CameraViewState.on) {
      // Failed, or stop() / dispose won the race: release what opened.
      await camera.close();
      if (mine == _token) _set(result);
      return;
    }
    _opened = true;
    _set(CameraViewState.on);
  }

  /// Turns the camera off and releases it (an open still in progress is
  /// released when it ends). Never restarts it.
  void stop() {
    _token++;
    if (_opened) {
      _opened = false;
      unawaited(camera.close());
    }
    _set(CameraViewState.off);
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    super.dispose();
  }
}
