/// Which way the user talks to the companion during an avatar call.
enum CallModality { text, voice }

/// The input controls of the avatar call screen (mobile-only, no web
/// version yet), as a plain value with the rules built in.
///
/// Only these combinations exist: text only, voice only, text + camera,
/// voice + camera. Text and voice are mutually exclusive, and exactly one
/// of them is always on, so the camera can never be on alone.
class CallInputs {
  const CallInputs({this.modality = CallModality.text, this.camera = false});

  /// Starting state: text only.
  static const CallInputs initial = CallInputs();

  /// Every reachable state.
  static const List<CallInputs> allowed = [
    CallInputs(),
    CallInputs(modality: CallModality.voice),
    CallInputs(camera: true),
    CallInputs(modality: CallModality.voice, camera: true),
  ];

  final CallModality modality;
  final bool camera;

  bool get textOn => modality == CallModality.text;
  bool get micOn => modality == CallModality.voice;
  bool get cameraOn => camera;

  /// Mic button: on turns typing off; off goes back to text (something has
  /// to stay on, or the camera could end up alone).
  CallInputs toggleMic() => CallInputs(
    modality: micOn ? CallModality.text : CallModality.voice,
    camera: camera,
  );

  /// Text-chat button: turns typing on and the mic off. Already on → no
  /// change (turning it off would leave nothing, or the camera alone).
  CallInputs selectText() => CallInputs(camera: camera);

  /// Camera button: always allowed, since text or voice is always on.
  CallInputs toggleCamera() => CallInputs(modality: modality, camera: !camera);

  @override
  bool operator ==(Object other) =>
      other is CallInputs &&
      other.modality == modality &&
      other.camera == camera;

  @override
  int get hashCode => Object.hash(modality, camera);

  @override
  String toString() =>
      'CallInputs(${modality.name}${camera ? ' + camera' : ''})';
}
