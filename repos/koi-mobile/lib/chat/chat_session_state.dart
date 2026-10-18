import '../safety/safety_contract.dart';
import 'chat_api.dart';

/// What one chat request sent from [ChatSessionState] (see
/// [ChatSessionState.beginTurn]).
class ChatTurnSnapshot {
  const ChatTurnSnapshot._({
    required this.sequence,
    required this.exerciseState,
    required this.clientEvent,
    required this.crisisPath,
    required this._clientEventVersion,
    required this._crisisPathVersion,
  });

  final int sequence;
  final String? exerciseState;
  final ClientEvent clientEvent;
  final CrisisPath? crisisPath;
  final int _clientEventVersion;
  final int _crisisPathVersion;
}

/// The conversation state the client carries between chat requests
/// (reference client `KoiConversationState`):
/// - [exerciseState]: opaque signed token, echoed exactly (§1);
/// - [pendingClientEvent]: from SafetyController.onClientEvent, sent with
///   the NEXT request, back to `none` only after a successful stream;
/// - [pendingCrisisPath]: from SafetyController.onCrisisPath, sent once with
///   `policy_event: "crisis_resolved"`, kept until a stream succeeds.
///
/// A value set while a request is in flight (e.g. `playback_stopped` when
/// the crisis flow opens mid-stream) is newer than the one that request
/// sent, so a success clears only what it actually sent.
class ChatSessionState {
  String? exerciseState;
  ClientEvent pendingClientEvent = ClientEvent.none;
  CrisisPath? pendingCrisisPath;

  int _turnSeq = 0;
  int _clientEventVersion = 0;
  int _crisisPathVersion = 0;

  void setClientEvent(ClientEvent event) {
    pendingClientEvent = event;
    _clientEventVersion++;
  }

  void setCrisisPath(CrisisPath path) {
    pendingCrisisPath = path;
    _crisisPathVersion++;
  }

  /// Takes what the next request sends.
  ChatTurnSnapshot beginTurn() => ChatTurnSnapshot._(
    sequence: ++_turnSeq,
    exerciseState: exerciseState,
    clientEvent: pendingClientEvent,
    crisisPath: pendingCrisisPath,
    clientEventVersion: _clientEventVersion,
    crisisPathVersion: _crisisPathVersion,
  );

  /// The request body for [turn] (contract §1).
  Map<String, Object?> requestBody(
    ChatTurnSnapshot turn, {
    required String message,
    required List<ChatTurn> sessionHistory,
  }) => chatRequestBody(
    message: message,
    sessionHistory: sessionHistory,
    exerciseState: turn.exerciseState,
    clientEvent: turn.clientEvent,
    crisisPath: turn.crisisPath,
  );

  /// The stream for [turn] completed. Returns true when it carried a
  /// crisis path (the caller then calls SafetyController
  /// .crisisResolutionSent()).
  bool turnSucceeded(ChatTurnSnapshot turn, ChatStreamResult result) {
    if (turn._clientEventVersion == _clientEventVersion) {
      pendingClientEvent = ClientEvent.none;
    }
    final sentPath = turn.crisisPath != null;
    if (sentPath && turn._crisisPathVersion == _crisisPathVersion) {
      pendingCrisisPath = null;
    }
    if (result.exerciseStateChanged) exerciseState = result.exerciseState;
    return sentPath;
  }
}
