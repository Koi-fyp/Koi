/** @jest-environment jsdom */
import React, { useEffect } from 'react';
import { act, render, waitFor, cleanup } from '@testing-library/react';
import { webcrypto } from 'crypto';
const mockSend = jest.fn();
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { uid: 'provider-owner' }, isLinked: false }) }));
jest.mock('@/lib/firebase', () => ({ firestore: null, auth: { currentUser: { uid: 'provider-owner' } } }));
jest.mock('firebase/auth', () => ({ onAuthStateChanged: () => () => {} }));
jest.mock('@/lib/conversation/conversationService', () => ({ sendMessage: (...args: unknown[]) => mockSend(...args) }));
jest.mock('@/lib/crypto', () => ({
  getActiveCryptoContext: async (uid: string) => ({ secret: uid, saltB64: 'fixture' }),
  encrypt: async (text: string, secret: string) => 'fixture:' + btoa(secret + ':' + encodeURIComponent(text)),
  decrypt: async (text: string, secret: string) => { const value = atob(text.slice(8)); if (!value.startsWith(secret + ':')) throw new Error('wrong owner'); return decodeURIComponent(value.slice(secret.length + 1)); },
}));
import ConversationProvider, { useOwnedConversationActions } from '@/contexts/ConversationContext';
import { useChat } from '@/hooks/useChat';
import { db } from '@/lib/db';
let latest: ReturnType<typeof useChat>;
let actions: ReturnType<typeof useOwnedConversationActions>;
const lifecycle = { mounts: 0, unmounts: 0 };
function RouteState() {
  const chat = useChat(); latest = chat; actions = useOwnedConversationActions();
  // Stands in for speech playback, mic capture and exercise timers bound to this session.
  useEffect(() => { lifecycle.mounts++; return () => { lifecycle.unmounts++; }; }, []);
  return <span data-testid="id">{chat.conversationId}</span>;
}
beforeAll(() => { Object.defineProperty(globalThis, 'crypto', { configurable: true, value: webcrypto }); });
beforeEach(async () => {
  lifecycle.mounts = 0; lifecycle.unmounts = 0;
  mockSend.mockReset().mockResolvedValue({ reply: 'Synthetic reply', companion_state: { emotion: 'neutral', intensity: 0 }, latency_ms: 1 });
  for (const table of db.tables) await table.clear();
});
afterEach(async () => { cleanup(); await act(async () => { await Promise.resolve(); }); });
it('a committed New Chat remounts route state once and leaves the old session inert', async () => {
  const view = render(<ConversationProvider><RouteState /></ConversationProvider>);
  await waitFor(() => expect(view.getByTestId('id')).toBeInTheDocument());
  await act(async () => { await latest.send('Synthetic A'); });
  const oldSession = latest.session, a = latest.conversationId;
  expect(lifecycle).toEqual({ mounts: 1, unmounts: 0 });
  await act(async () => { await actions.createOwned(); });
  expect(latest.conversationId).not.toBe(a); expect(latest.messages).toEqual([]);
  expect(lifecycle).toEqual({ mounts: 2, unmounts: 1 });
  // A late callback from the unmounted route (e.g. an exercise stop) cannot reach the new conversation.
  oldSession.queueClientEvent('playback_stopped');
  expect(latest.session.getSnapshot().clientEventPending).toBeNull();
  await act(async () => { await actions.openOwned(a); });
  expect(latest.conversationId).toBe(a); expect(latest.messages.map(m => m.content)).toEqual(['Synthetic A', 'Synthetic reply']);
  expect(mockSend).toHaveBeenCalledTimes(1);
});
it('retries queued cloud writes when the signed-in app starts', async () => {
  const { syncQueue } = jest.requireActual('@/lib/firestore/sync');
  const flush = jest.spyOn(syncQueue, 'flush').mockResolvedValue(undefined);
  const view = render(<ConversationProvider><RouteState /></ConversationProvider>);
  await waitFor(() => expect(view.getByTestId('id')).toBeInTheDocument());
  expect(flush).toHaveBeenCalled();
  flush.mockRestore();
});
