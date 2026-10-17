/** @jest-environment jsdom */
import React, { StrictMode } from 'react';
import { act, render, waitFor, fireEvent, cleanup } from '@testing-library/react';
import { webcrypto } from 'crypto';
const mockAuth = jest.fn();
const mockSend = jest.fn();
let mockLocked = false;
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => mockAuth() }));
jest.mock('@/lib/conversation/conversationService', () => ({ sendMessage: (...args: unknown[]) => mockSend(...args) }));
jest.mock('@/lib/crypto', () => ({
  getActiveCryptoContext: async (uid: string) => { if (mockLocked) throw new Error('locked'); return { secret: uid, saltB64: 'fixture' }; },
  encrypt: async (text: string, secret: string) => 'fixture:' + btoa(secret + ':' + encodeURIComponent(text)),
  decrypt: async (text: string, secret: string) => { const value = atob(text.slice(8)); if (!value.startsWith(secret + ':')) throw new Error('wrong owner'); return decodeURIComponent(value.slice(secret.length + 1)); },
}));
import ConversationProvider from '@/contexts/ConversationContext';
import { useChat } from '@/hooks/useChat';
import { db } from '@/lib/db';
import { PersistentConversation } from '@/lib/conversation/PersistentConversation';
const response = { reply: 'Synthetic reply', companion_state: { emotion: 'joy' as const, intensity: 0.5 }, latency_ms: 1 };
let latest: ReturnType<typeof useChat>;
function Screen({ route }: { route: string }) {
  const chat = useChat(); latest = chat;
  return <div><span>{route}</span><span data-testid="id">{chat.conversationId}</span><span data-testid="count">{chat.messages.length}</span>
    <span data-testid="error">{chat.error}</span><button onClick={() => void chat.send('Synthetic user input')}>Send</button></div>;
}
function App({ route = 'chat' }: { route?: string }) { return <ConversationProvider>{route === 'progress' ? <div>Progress</div> : <Screen key={route} route={route} />}</ConversationProvider>; }
async function ready(view: ReturnType<typeof render>) { await waitFor(() => expect(view.getByTestId('id')).toBeInTheDocument()); }
beforeAll(() => { Object.defineProperty(globalThis, 'crypto', { value: webcrypto }); });
beforeEach(async () => {
  mockLocked = false; mockAuth.mockReturnValue({ user: { uid: 'owner-a' }, isLinked: false });
  mockSend.mockReset(); mockSend.mockResolvedValue(response);
  await db.conversations.clear(); await db.messages.clear();
});
afterEach(async () => { cleanup(); await act(async () => { await Promise.resolve(); }); });
it('reproduces the former route-local identity failure', () => {
  const { ConversationSession } = require('@/lib/conversation/ConversationSession');
  const adapter = { send: async () => response };
  const oldChat = new ConversationSession(adapter), oldAvatar = new ConversationSession(adapter);
  expect(oldChat.conversationId).not.toBe(oldAvatar.conversationId);
  oldChat.dispose(); oldAvatar.dispose();
});
it('keeps Chat to Progress to Chat and Chat to Avatar to Chat on one session, with no repeated POST', async () => {
  const view = render(<StrictMode><App /></StrictMode>); await ready(view);
  const id = latest.conversationId, session = latest.session;
  fireEvent.click(view.getByText('Send'));
  await waitFor(() => expect(latest.pending).toBe(false));
  fireEvent.click(view.getByText('Send'));
  await waitFor(() => expect(mockSend).toHaveBeenCalledTimes(2));
  await waitFor(() => expect(latest.messages).toHaveLength(4));
  for (const route of ['progress', 'chat', 'avatar', 'chat', 'progress', 'chat']) {
    view.rerender(<StrictMode><App route={route} /></StrictMode>);
    if (route !== 'progress') { await ready(view); expect(latest.session).toBe(session); expect(latest.conversationId).toBe(id); expect(latest.messages).toHaveLength(4); }
  }
  expect(mockSend).toHaveBeenCalledTimes(2);
  expect(mockSend.mock.calls[1][3].map((m: { role: string }) => m.role)).toEqual(['user', 'assistant']);
});
it('keeps an active SSE turn alive without subscribers, then reattaches once', async () => {
  let finish!: () => void; let options: any;
  mockSend.mockImplementation(async (...args) => { options = args[5]; options.onEvent({ event: 'delta', data: { text: 'Synthetic partial' } }); await new Promise<void>(resolve => { finish = resolve; }); return response; });
  const view = render(<App />); await ready(view); const session = latest.session;
  fireEvent.click(view.getByText('Send')); await waitFor(() => expect(finish).toBeDefined());
  view.rerender(<App route="progress" />);
  expect(options.signal.aborted).toBe(false);
  await act(async () => { options.onEvent({ event: 'delta', data: { text: ' more' } }); });
  view.rerender(<App route="avatar" />); await ready(view);
  expect(latest.session).toBe(session); expect(latest.messages).toHaveLength(2);
  await act(async () => finish()); await waitFor(() => expect(latest.pending).toBe(false));
  expect(latest.messages).toHaveLength(2); expect(mockSend).toHaveBeenCalledTimes(1);
});
it('restores encrypted identity/history after a full provider remount and sends valid prior context', async () => {
  const first = render(<App />); await ready(first); fireEvent.click(first.getByText('Send'));
  await waitFor(() => expect(latest.messages.every(m => m.status === 'completed')).toBe(true));
  await waitFor(async () => { const row = await db.conversations.get('owner-a'); expect(row?.encryptedState).toContain('fixture:'); expect(atob(row!.encryptedState!.slice(8))).toContain('completed'); });
  const id = latest.conversationId, ids = latest.messages.map(m => m.id); first.unmount(); await act(async () => { await Promise.resolve(); });
  const second = render(<App route="avatar" />); await ready(second);
  expect(latest.conversationId).toBe(id); expect(latest.messages.map(m => m.id)).toEqual(ids);
  fireEvent.click(second.getByText('Send')); await waitFor(() => expect(mockSend).toHaveBeenCalledTimes(2));
  expect(mockSend.mock.calls[1][3]).toHaveLength(2);
  expect(JSON.stringify(await db.conversations.get('owner-a'))).not.toContain('Synthetic user input');
});
it('purges old plaintext and cancels streaming on account change; returning owner recovers only its own record', async () => {
  let options: any;
  mockSend.mockImplementation(async (...args) => { options = args[5]; await new Promise((_, reject) => options.signal.addEventListener('abort', () => reject(new Error('aborted')))); });
  const view = render(<App />); await ready(view); fireEvent.click(view.getByText('Send'));
  await waitFor(() => expect(options).toBeDefined()); const old = latest.session;
  mockAuth.mockReturnValue({ user: { uid: 'owner-b' }, isLinked: false }); view.rerender(<App />); await ready(view);
  expect(options.signal.aborted).toBe(true); expect(old.getSnapshot().messages).toEqual([]);
  expect(latest.messages).toEqual([]); expect(latest.conversationId).not.toBe(old.conversationId);
  mockAuth.mockReturnValue({ user: { uid: 'owner-a' }, isLinked: false }); view.rerender(<App />); await ready(view);
  expect(latest.conversationId).toBe(old.conversationId); expect(latest.messages).toHaveLength(1);
  expect(latest.messages[0].status).toBe('cancelled'); expect(mockSend).toHaveBeenCalledTimes(1);
});
it('fails closed for locked/corrupt history and unavailable IndexedDB', async () => {
  mockLocked = true; const locked = render(<App />);
  await waitFor(() => expect(locked.getByRole('status')).toHaveTextContent(/could not be unlocked/)); expect(mockSend).not.toHaveBeenCalled();
  locked.unmount(); await act(async () => { await Promise.resolve(); }); mockLocked = false;
  await db.conversations.put({ uid: 'owner-a', conversationId: 'fixture-id', createdAt: new Date(), lastActiveAt: new Date(), status: 'active', revision: 0, encryptedState: 'invalid' });
  const corrupt = render(<App />); await waitFor(() => expect(corrupt.getByRole('status')).toHaveTextContent(/could not be unlocked/)); corrupt.unmount();
  await act(async () => { await Promise.resolve(); });
  const spy = jest.spyOn(db, 'transaction').mockRejectedValueOnce(new Error('unavailable') as never);
  const unavailable = render(<App />); await waitFor(() => expect(unavailable.getByRole('status')).toHaveTextContent(/could not be unlocked/)); spy.mockRestore();
});
it('preserves orphaned legacy rows without adopting them, and rejects stale cross-tab writes', async () => {
  await db.messages.put({ id: 'orphan', conversationId: 'legacy', sender: 'user', content: 'legacy-ciphertext', timestamp: new Date(), emotion: 'neutral', synced: false });
  const adapter = { send: async () => response };
  const a = new PersistentConversation('owner-a', adapter, { isLinked: false }); await a.initialize();
  const b = new PersistentConversation('owner-a', adapter, { isLinked: false }); await b.initialize();
  expect(a.session!.getSnapshot().messages).toEqual([]); await a.checkpoint();
  await expect(b.checkpoint()).rejects.toThrow(); expect(b.getSnapshot().error).toMatch(/storage/);
  expect(await db.messages.get('orphan')).toBeDefined(); a.dispose(); b.dispose();
});
it('retains signed exercise and unresolved safety state while consuming UI commands once', async () => {
  const view = render(<App />); await ready(view);
  const session = latest.session;
  act(() => { expect(session.consumeUiEvent(1)).toBe(true); expect(session.consumeUiEvent(1)).toBe(false); });
  act(() => session.queueCrisisPath('reached_out', { to: 'crisis', reason: 'synthetic' }));
  view.rerender(<App route="avatar" />); await ready(view);
  expect(latest.session.consumeUiEvent(1)).toBe(false);
  expect(latest.session.isHandoffResolved({ to: 'crisis', reason: 'synthetic' })).toBe(true);
  expect(latest.policyPathPending).toBe('reached_out');
});
