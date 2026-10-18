import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/chat_session_state.dart';
import 'package:koi_mobile/safety/safety_contract.dart';

ChatStreamResult _result({bool changed = false, String? state}) =>
    ChatStreamResult(
      fullText: 'ok',
      companionState: CompanionState.fallback,
      latencyMs: null,
      exerciseStateChanged: changed,
      exerciseState: state,
    );

Map<String, Object?> _body(ChatSessionState s, ChatTurnSnapshot t) =>
    s.requestBody(t, message: 'm', sessionHistory: const []);

void main() {
  test('ATC-M12-14 client_event is sent once, then reset to none', () {
    final s = ChatSessionState()..setClientEvent(ClientEvent.playbackDone);
    final t1 = s.beginTurn();
    expect(_body(s, t1)['client_event'], 'playback_done');
    s.turnSucceeded(t1, _result());
    expect(_body(s, s.beginTurn())['client_event'], 'none');
  });

  test('ATC-M12-14 crisis_path + policy_event once; true → crisisResolutionSent', () {
    final s = ChatSessionState()..setCrisisPath(CrisisPath.misunderstanding);
    final t1 = s.beginTurn();
    final body = _body(s, t1);
    expect(body['policy_event'], 'crisis_resolved');
    expect(body['crisis_path'], 'misunderstanding');
    expect(s.turnSucceeded(t1, _result()), isTrue);

    final t2 = s.beginTurn();
    expect(_body(s, t2)['policy_event'], isNull);
    expect(_body(s, t2)['crisis_path'], isNull);
    expect(s.turnSucceeded(t2, _result()), isFalse);
  });

  test('ATC-M12-14 on failure (no turnSucceeded) both are kept for the next send', () {
    final s = ChatSessionState()
      ..setClientEvent(ClientEvent.playbackStopped)
      ..setCrisisPath(CrisisPath.reachedOut);
    s.beginTurn(); // this request failed
    final retry = _body(s, s.beginTurn());
    expect(retry['client_event'], 'playback_stopped');
    expect(retry['crisis_path'], 'reached_out');
  });

  test('ATC-M12-14 a value set while the request is in flight is not cleared', () {
    final s = ChatSessionState()..setClientEvent(ClientEvent.playbackDone);
    final t1 = s.beginTurn();
    // Crisis opens mid-stream and stops breathing → playback_stopped.
    s.setClientEvent(ClientEvent.playbackStopped);
    s.turnSucceeded(t1, _result());
    expect(s.pendingClientEvent, ClientEvent.playbackStopped);

    // Even the same value set again is newer.
    s.setClientEvent(ClientEvent.playbackStopped);
    final t2 = s.beginTurn();
    s.setClientEvent(ClientEvent.playbackStopped);
    s.turnSucceeded(t2, _result());
    expect(s.pendingClientEvent, ClientEvent.playbackStopped);

    final p = ChatSessionState()..setCrisisPath(CrisisPath.reachedOut);
    final t3 = p.beginTurn();
    p.setCrisisPath(CrisisPath.saidButDidNot);
    expect(p.turnSucceeded(t3, _result()), isTrue);
    expect(p.pendingCrisisPath, CrisisPath.saidButDidNot);
  });

  test('ATC-M2-10 exercise_state: echoed exactly; explicit null clears; '
      'unchanged otherwise (contract §1)', () {
    final s = ChatSessionState();
    final t1 = s.beginTurn();
    expect(_body(s, t1)['exercise_state'], isNull);
    s.turnSucceeded(t1, _result(changed: true, state: 'sig.ABC+/='));
    final t2 = s.beginTurn();
    expect(_body(s, t2)['exercise_state'], 'sig.ABC+/=');
    s.turnSucceeded(t2, _result()); // no state change
    expect(s.exerciseState, 'sig.ABC+/=');
    s.turnSucceeded(s.beginTurn(), _result(changed: true));
    expect(s.exerciseState, isNull);
  });
}
