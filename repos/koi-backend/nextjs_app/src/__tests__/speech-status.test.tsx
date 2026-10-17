import { act, fireEvent, render, screen } from '@testing-library/react';
import SpeechStatus from '@/components/avatar/SpeechStatus';
import { SpeechTurnController, type SpeechRequest, type TurnPlayback } from '@/lib/speech/SpeechTurnController';
import type { PlaybackSnapshot } from '@/lib/speech/SpeechPlayback';

function fakePlayback(): TurnPlayback & { loads: number; plays: number } {
  let snapshot: PlaybackSnapshot = { state: 'idle', time: 0, duration: 0, error: null };
  const listeners = new Set<() => void>();
  const set = (state: PlaybackSnapshot['state']) => { snapshot = { ...snapshot, state }; listeners.forEach(listener => listener()); };
  return {
    loads: 0, plays: 0,
    load() { this.loads++; set('idle'); },
    async play() { this.plays++; set('playing'); },
    clear() { set('stopped'); },
    dispose() { listeners.clear(); },
    getFrame: () => ({ active: snapshot.state === 'playing', time: 0, cues: [] }),
    getSnapshot: () => snapshot,
    subscribe: (listener) => { listeners.add(listener); return () => { listeners.delete(listener); }; },
  };
}
type Pending = { request: SpeechRequest; resolve: (value: unknown) => void; reject: (error: Error) => void };
function setup() {
  const pending: Pending[] = [], playback = fakePlayback();
  const controller = new SpeechTurnController({ playback, newGenerationId: () => `gen-${pending.length + 1}`,
    fetchSpeech: (request) => new Promise((resolve, reject) => { pending.push({ request, resolve, reject }); }) });
  return { pending, playback, controller };
}
// Chat-owned values: the speech layer receives a copy of the text and must never change these.
const done = Object.freeze({ type: 'done', full_text: 'Main yahan hoon. Aap kaisa mehsoos kar rahe hain?' });
const chat = Object.freeze({ messages: Object.freeze([Object.freeze({ role: 'assistant', text: done.full_text })]) });
function Reply({ controller }: { controller: SpeechTurnController }) {
  return <section><p data-testid="reply">{chat.messages[0].text}</p><SpeechStatus controller={controller} /></section>;
}

describe('SpeechStatus', () => {
  it('shows an honest retry state on speech failure while the reply text and chat state stay intact', async () => {
    const { pending, playback, controller } = setup();
    render(<Reply controller={controller} />);
    controller.setCompanion('raza');
    let speaking!: Promise<void>;
    act(() => { speaking = controller.speak({ text: done.full_text, companion: 'raza', language: 'ur' }); });
    expect(screen.getByRole('status')).toHaveTextContent('Preparing voice...');
    expect(pending[0].request).toEqual({ text: done.full_text, voice_id: 'ur_PK-fasih-medium', language: 'ur', generation_id: 'gen-1' });
    await act(async () => { pending[0].reject(new Error('503')); await speaking; });
    expect(screen.getByRole('status')).toHaveTextContent('Voice is unavailable for this reply. The text above is complete.');
    expect(screen.getByTestId('reply')).toHaveTextContent(done.full_text);
    expect(done.full_text).toBe('Main yahan hoon. Aap kaisa mehsoos kar rahe hain?');
    expect(chat.messages).toHaveLength(1);
    expect(playback.loads).toBe(0); expect(playback.plays).toBe(0);
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Retry voice' })); });
    expect(pending).toHaveLength(2);
    expect(pending[1].request.text).toBe(done.full_text);
    expect(pending[1].request.generation_id).not.toBe(pending[0].request.generation_id);
    expect(screen.getByRole('status')).toHaveTextContent('Preparing voice...');
    expect(screen.getByTestId('reply')).toHaveTextContent(done.full_text);
  });

  it('a response in the other companion voice fails honestly and never plays', async () => {
    const { pending, playback, controller } = setup();
    render(<Reply controller={controller} />);
    let speaking!: Promise<void>;
    act(() => { speaking = controller.speak({ text: done.full_text, companion: 'aisha', language: 'en' }); });
    expect(pending[0].request.voice_id).toBe('en_US-hfc_female-medium');
    await act(async () => { pending[0].resolve({ generation_id: 'gen-1', voice_id: 'en_US-hfc_male-medium' }); await speaking; });
    expect(screen.getByRole('status')).toHaveTextContent('Voice is unavailable');
    expect(playback.plays).toBe(0);
    expect(screen.getByTestId('reply')).toHaveTextContent(done.full_text);
  });

  it('cancellation shows no error and offers no retry; text untouched', async () => {
    const { pending, controller } = setup();
    render(<Reply controller={controller} />);
    let speaking!: Promise<void>;
    act(() => { speaking = controller.speak({ text: done.full_text, companion: 'raza', language: 'en' }); });
    act(() => { controller.cancel('crisis-handoff'); });
    await act(async () => { pending[0].reject(new Error('aborted')); await speaking; });
    expect(screen.queryByRole('status')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Retry voice' })).toBeNull();
    expect(controller.getSnapshot()).toMatchObject({ status: 'cancelled', reason: 'crisis-handoff', canRetry: false });
    expect(screen.getByTestId('reply')).toHaveTextContent(done.full_text);
  });

  it('a voice-less companion fails without any request', async () => {
    const { pending, controller } = setup();
    render(<Reply controller={controller} />);
    await act(async () => { await controller.speak({ text: done.full_text, companion: 'koi' as never, language: 'ur' }); });
    expect(pending).toHaveLength(0);
    expect(screen.getByRole('status')).toHaveTextContent('Voice is unavailable');
    expect(screen.getByTestId('reply')).toHaveTextContent(done.full_text);
  });
});
