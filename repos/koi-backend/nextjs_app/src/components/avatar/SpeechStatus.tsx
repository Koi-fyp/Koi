'use client';
import { useSyncExternalStore } from 'react';
import type { SpeechTurnController, SpeechTurnSnapshot } from '../../lib/speech/SpeechTurnController';

const SERVER: SpeechTurnSnapshot = { status: 'idle', generationId: null, reason: null, error: null, canRetry: false };
export function useSpeechTurn(controller: SpeechTurnController): SpeechTurnSnapshot {
  return useSyncExternalStore(controller.subscribe, controller.getSnapshot, () => SERVER);
}

/** Voice state only. Never renders or edits the reply text; a failure leaves the text as the answer. */
export default function SpeechStatus({ controller }: { controller: SpeechTurnController }) {
  const { status, error, canRetry } = useSpeechTurn(controller);
  if (status === 'requesting') return <p role="status" data-speech-status={status}>Preparing voice...</p>;
  if (status !== 'failed') return null;
  return (
    <p role="status" data-speech-status={status} style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap', margin: '5px 0 0' }}>
      <span>{error}</span>
      {canRetry && <button type="button" onClick={() => { void controller.retry(); }}
        style={{ padding: '4px 12px', border: '2px solid #171717', borderRadius: 10, background: 'var(--neo-yellow, #ffd100)', cursor: 'pointer', fontWeight: 700 }}>Retry voice</button>}
    </p>
  );
}
