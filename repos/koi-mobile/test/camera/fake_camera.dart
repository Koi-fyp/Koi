import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:koi_mobile/camera/camera_session.dart';

/// Stand-in for the platform camera: counts opens / closes, can hold an
/// open ([hold]) or fail it ([error]).
class FakeLocalCamera implements LocalCamera {
  int opens = 0;
  int closes = 0;

  /// True between a finished open and the next close.
  bool isOpen = false;

  /// Thrown by the next open.
  Object? error;

  /// When set, open waits for it.
  Completer<void>? hold;

  @override
  Future<void> open() async {
    opens++;
    final h = hold;
    if (h != null) await h.future;
    final e = error;
    if (e != null) throw e;
    isOpen = true;
  }

  @override
  Widget preview() => const SizedBox(key: Key('fake-camera-preview'));

  @override
  Future<void> close() async {
    closes++;
    isOpen = false;
  }
}
