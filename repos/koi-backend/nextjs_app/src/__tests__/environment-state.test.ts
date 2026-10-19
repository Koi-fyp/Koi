import { ConversationSession } from '@/lib/conversation/ConversationSession';
import { EnvironmentState } from '@/lib/environment/environmentState';
import type { ChatServerEvent } from '@/lib/conversation/chatContract';

function fixture() {
  let emit!: (event: ChatServerEvent) => void;
  let finish!: () => void;
  const session = new ConversationSession({ send: (_request, options) => new Promise(resolve => {
    emit = event => options?.onEvent?.(event);
    finish = () => resolve({ reply: 'Fixture reply', companion_state: { emotion: 'joy', intensity: 0.7 }, latency_ms: 1 });
  }) });
  const state = new EnvironmentState();
  const binding = state.bind(session);
  const emotion = (value: string) => emit({ event: 'companion_state', data: { emotion: value as 'joy', intensity: 0.7 } });
  return { session, state, binding, emotion, emit: (event: ChatServerEvent) => emit(event), finish: () => finish() };
}
const handoff = { to: 'crisis' as const, reason: 'fixture' };

it.each(['neutral', 'joy', 'angry', 'sorrow', 'fun', 'mystery'])('observes live %s', value => {
  const f = fixture(); void f.session.send('Hello'); f.emotion(value);
  expect(f.state.getSnapshot()).toBe(value === 'mystery' ? 'neutral' : value); f.session.dispose();
});
it.each(['HIGH', 'CRITICAL'])('%s overrides emotion through a pending decision; resolution waits for fresh emotion', category => {
  const f = fixture(); void f.session.send('Hello'); f.emotion('joy');
  f.emit({ event: 'risk', data: { status: 'ok', risk_category: category } } as ChatServerEvent);
  f.emotion('fun'); expect(f.state.getSnapshot()).toBe('calm');
  f.session.queueCrisisPath('reached_out', handoff); expect(f.state.getSnapshot()).toBe('calm');
  // Sending consumes the queued policy path and clears this turn's risk events.
  void f.session.send('Follow up'); expect(f.state.getSnapshot()).toBe('neutral');
  f.emotion('fun'); expect(f.state.getSnapshot()).toBe('fun');
  f.session.dispose();
});
it('observes handoff, dialog and pending choice independently', () => {
  const f = fixture(); void f.session.send('Hello'); f.emotion('joy');
  f.binding.dialog(true); expect(f.state.getSnapshot()).toBe('calm'); f.binding.dialog(false);
  f.emit({ event: 'handoff', data: handoff }); expect(f.state.getSnapshot()).toBe('calm');
  f.session.queueCrisisPath('misunderstanding', handoff); expect(f.state.getSnapshot()).toBe('calm');
  void f.session.send('Next'); expect(f.state.getSnapshot()).toBe('neutral'); f.session.dispose();
});
it('breathing reveals the latest valid emotion on completion/stop unless crisis remains', () => {
  const f = fixture(); void f.session.send('Hello'); f.emotion('joy');
  f.binding.breathing(true); f.emotion('sorrow'); expect(f.state.getSnapshot()).toBe('calm');
  f.binding.breathing(false); expect(f.state.getSnapshot()).toBe('sorrow');
  f.binding.breathing(true); f.emit({ event: 'handoff', data: handoff });
  f.binding.breathing(false); expect(f.state.getSnapshot()).toBe('calm'); f.session.dispose();
});
it('ignores restored emotion/events, but honors restored pending safety', () => {
  const session = new ConversationSession({ send: jest.fn() });
  const recovered = session.recoveryState();
  recovered.snapshot.companion = { emotion: 'fun', intensity: 1 };
  recovered.snapshot.serverEvents = [{ id: 9, event: { event: 'companion_state', data: recovered.snapshot.companion } }];
  recovered.eventSequence = 9; session.restore(recovered);
  const state = new EnvironmentState(); state.bind(session); expect(state.getSnapshot()).toBe('neutral');
  session.inputFocused(true); expect(state.getSnapshot()).toBe('neutral');
  session.queueCrisisPath('reached_out', handoff); expect(state.getSnapshot()).toBe('calm');
});
it('accepts JSON completion and done companion emotion without changing session recovery data', async () => {
  const f = fixture(); const pending = f.session.send('Hello');
  f.finish(); await pending; expect(f.state.getSnapshot()).toBe('joy');
  const before = JSON.stringify(f.session.recoveryState());
  f.binding.breathing(true); f.binding.dialog(true); f.binding.breathing(false); f.binding.dialog(false);
  expect(JSON.stringify(f.session.recoveryState())).toBe(before);
  void f.session.send('Again'); f.emit({ event: 'done', data: { full_text: 'Done', companion_state: { emotion: 'fun', intensity: 1 } } });
  expect(f.state.getSnapshot()).toBe('fun'); f.session.dispose();
});
it('new session/logout dispose resets memory; stale callbacks cannot affect the next session', () => {
  const f = fixture(); void f.session.send('Hello'); f.emotion('angry');
  f.binding.dispose(); expect(f.state.getSnapshot()).toBe('neutral');
  f.state.bind(new ConversationSession({ send: jest.fn() }));
  f.binding.breathing(true); f.binding.dialog(true); f.emotion('fun');
  expect(f.state.getSnapshot()).toBe('neutral');
  expect(new EnvironmentState().getSnapshot()).toBe('neutral'); f.session.dispose();
});
