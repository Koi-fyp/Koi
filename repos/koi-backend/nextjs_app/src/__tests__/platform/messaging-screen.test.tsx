import React from 'react';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import MessagesScreen from '@/components/messaging/MessagesScreen';
import { PlatformClientError, professionalApi } from '@/lib/platform/client';
import type { CareNotification, HumanMessage } from '@/lib/platform/community-types';
import { unreadStore } from '@/lib/platform/messaging/unread-store';

const msg = (id: string, created_at: string, body: string, sender_uid: string): HumanMessage => ({ id, relationship_id: 'rel1', sender_uid, body, created_at });
const notice = (id: string, messageId: string): CareNotification => ({ id, event_id: id, kind: 'new_message', reference: { message_id: messageId }, created_at: new Date().toISOString() });
const today = new Date().toISOString(), yesterday = new Date(Date.now() - 86400000).toISOString();
const relationships = [{ relationship_id: 'rel1', psychologist_uid: 'psy1' }];
type Handler = (path: string, method?: string, body?: unknown) => unknown;
const makeApi = (handler: Handler) => ({ request: jest.fn(async (path: string, method?: string, body?: unknown) => handler(path, method, body)) as never, dispose: jest.fn() }) as unknown as Parameters<typeof MessagesScreen>[0]['api'] & { request: jest.Mock };
const baseThread: HumanMessage[] = [msg('message_zz', today, 'newer from patient', 'pat1'), msg('message_aa', yesterday, 'older from psychologist', 'psy1')];
const threadHandler = (list: () => HumanMessage[] = () => baseThread): Handler => path => { if (path.includes('/messages?limit=')) return { items: list(), next_cursor: null }; throw new Error(`unexpected ${path}`); };
const open = async (api: ReturnType<typeof makeApi>, onError = jest.fn()) => {
  render(<MessagesScreen api={api} role="patient" patientRelationships={relationships} onError={onError} />);
  fireEvent.click(await screen.findByRole('button', { name: /Your psychologist/ }));
  await within(await screen.findByRole('log')).findByText('newer from patient');
  return onError;
};
const inLog = () => within(screen.getByRole('log'));
beforeEach(() => { unreadStore.reset(); });

describe('conversation list and chat pane', () => {
  it('retains an unsent draft through an authorized refresh and removes a revoked conversation', async () => {
    const first = makeApi(threadHandler()), next = makeApi(threadHandler());
    const all = [...relationships, { relationship_id: 'rel2', psychologist_uid: 'psy2' }];
    const view = render(<MessagesScreen api={first} role="patient" patientRelationships={all} onError={jest.fn()} />);
    fireEvent.click(await screen.findByRole('button', { name: /Your psychologist.*psy1/ }));
    fireEvent.change(await screen.findByRole('textbox', { name: 'Message' }), { target: { value: 'Unsent fixture draft' } });
    view.rerender(<MessagesScreen api={next} role="patient" patientRelationships={all} active={false} onError={jest.fn()} />);
    view.rerender(<MessagesScreen api={next} role="patient" patientRelationships={relationships} onError={jest.fn()} />);
    expect(await screen.findByRole('textbox', { name: 'Message' })).toHaveValue('Unsent fixture draft');
    view.rerender(<MessagesScreen api={next} role="patient" patientRelationships={[]} onError={jest.fn()} />);
    expect(screen.queryByRole('textbox', { name: 'Message', hidden: true })).not.toBeInTheDocument();
    expect([...first.request.mock.calls, ...next.request.mock.calls].every(([, method]) => !method || method === 'GET')).toBe(true);
  });
  it('shows one conversation with preview, ordered messages, date separators, times and dir=auto', async () => {
    const api = makeApi(threadHandler());
    render(<MessagesScreen api={api} role="patient" patientRelationships={relationships} onError={jest.fn()} />);
    const button = await screen.findByRole('button', { name: /Your psychologist/ });
    await waitFor(() => expect(within(button).getByText('newer from patient')).toBeInTheDocument());
    fireEvent.click(button);
    const log = await screen.findByRole('log');
    const bodies = within(log).getAllByText(/from (patient|psychologist)/).map(n => n.textContent);
    expect(bodies).toEqual(['older from psychologist', 'newer from patient']); // time order, not API order
    expect(screen.getAllByTestId('day-separator').map(n => n.textContent)).toEqual(['Yesterday', 'Today']);
    expect(inLog().getByText('newer from patient')).toHaveAttribute('dir', 'auto');
    expect(log.querySelectorAll('time')).toHaveLength(2);
    expect(log).toHaveAttribute('aria-live', 'polite');
  });
  it('shows an empty state without relationships and never calls professional endpoints for patients', async () => {
    const api = makeApi(threadHandler());
    const { unmount } = render(<MessagesScreen api={api} role="patient" patientRelationships={[]} onError={jest.fn()} />);
    expect(await screen.findByText(/No conversations yet/)).toBeInTheDocument(); unmount();
    render(<MessagesScreen api={api} role="patient" patientRelationships={relationships} onError={jest.fn()} />);
    await screen.findByRole('button', { name: /Your psychologist/ });
    await waitFor(() => expect(api.request).toHaveBeenCalled());
    for (const [path] of api.request.mock.calls) expect(String(path)).not.toContain('/professional/');
  });
  it('renders hostile and RTL text as plain text with no auto-linking', async () => {
    const hostile = [msg('m1', today, '<img src=x onerror=alert(1)> http://example.com سلام', 'psy1')];
    await open(makeApi(threadHandler(() => [...baseThread, ...hostile])));
    const body = inLog().getByText(/onerror=alert/);
    expect(body.querySelector('img, a')).toBeNull(); expect(body).toHaveAttribute('dir', 'auto'); expect(body).toHaveStyle({ whiteSpace: 'pre-wrap' });
  });
  it('lists professional conversations from the practice roster only', async () => {
    const api = makeApi(path => path.startsWith('/api/v1/professional/patient-relationships') ? { items: [{ id: 'rel1', patient_uid: 'patient-abcd', state: 'active', revision: 1 }, { id: 'rel2', patient_uid: 'patient-zzzz', state: 'closed', revision: 2 }], next_cursor: null } : { items: [], next_cursor: null });
    render(<MessagesScreen api={api} role="professional" organizationId="org1" onError={jest.fn()} />);
    expect(await screen.findByRole('button', { name: /Patient · abcd/ })).toBeInTheDocument();
    expect(screen.queryByText(/zzzz/)).not.toBeInTheDocument();
  });
});

describe('sending', () => {
  it('shows an optimistic Sending bubble, then Sent, and sends with the exact body', async () => {
    let release: (m: HumanMessage) => void = () => undefined;
    const api = makeApi((path, method) => method === 'POST' ? new Promise<HumanMessage>(r => { release = r; }) : threadHandler()(path));
    await open(api);
    fireEvent.change(screen.getByLabelText('Message'), { target: { value: 'hello there' } }); fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    expect(await screen.findByText(/Sending\.\.\./)).toBeInTheDocument();
    expect(api.request).toHaveBeenCalledWith('/api/v1/messages', 'POST', { relationship_id: 'rel1', body: 'hello there' });
    expect(screen.getByLabelText('Message')).toHaveValue('');
    await act(async () => release(msg('message_new', new Date().toISOString(), 'hello there', 'pat1')));
    await waitFor(() => expect(screen.queryByText(/Sending\.\.\./)).not.toBeInTheDocument());
    expect(inLog().getAllByText('hello there')).toHaveLength(1);
  });
  it('marks a failure Not sent and retries with identical request arguments', async () => {
    let fail = true;
    const api = makeApi((path, method) => { if (method === 'POST') { if (fail) throw new PlatformClientError(503, 'unavailable'); return msg('message_new', new Date().toISOString(), 'retry me', 'pat1'); } return threadHandler()(path); });
    await open(api);
    fireEvent.change(screen.getByLabelText('Message'), { target: { value: 'retry me' } }); fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    const retry = await screen.findByRole('button', { name: 'Not sent. Tap to retry' });
    fail = false; fireEvent.click(retry);
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Not sent. Tap to retry' })).not.toBeInTheDocument());
    const posts = api.request.mock.calls.filter(c => c[1] === 'POST');
    expect(posts).toHaveLength(2); expect(posts[1]).toEqual(posts[0]);
    expect(inLog().getAllByText('retry me')).toHaveLength(1);
  });
  it('keeps the typed text when re-authentication is cancelled and succeeds on retry', async () => {
    let cancelled = true;
    const api = makeApi((path, method) => { if (method === 'POST') { if (cancelled) throw new PlatformClientError(0, 'reauth_cancelled'); return msg('message_new', new Date().toISOString(), 'needs fresh sign-in', 'pat1'); } return threadHandler()(path); });
    const onError = await open(api);
    fireEvent.change(screen.getByLabelText('Message'), { target: { value: 'needs fresh sign-in' } }); fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    expect(await within(await screen.findByRole('log')).findByText('needs fresh sign-in')).toBeInTheDocument();
    const retry = await screen.findByRole('button', { name: 'Not sent. Tap to retry' }); expect(onError).not.toHaveBeenCalled();
    cancelled = false; fireEvent.click(retry);
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Not sent. Tap to retry' })).not.toBeInTheDocument());
    expect(api.request.mock.calls.filter(c => c[1] === 'POST')).toHaveLength(2);
  });
  it('sends on Enter, keeps Shift+Enter for a newline, and disables Send when empty or too long', async () => {
    const api = makeApi((path, method) => method === 'POST' ? msg('message_new', new Date().toISOString(), 'x', 'pat1') : threadHandler()(path));
    await open(api);
    const box = screen.getByLabelText('Message'), send = screen.getByRole('button', { name: 'Send' });
    expect(send).toBeDisabled();
    fireEvent.change(box, { target: { value: '   ' } }); expect(send).toBeDisabled();
    fireEvent.change(box, { target: { value: 'a'.repeat(4001) } }); expect(send).toBeDisabled(); expect(screen.getByText(/Too long: 4001\/4000/)).toBeInTheDocument();
    fireEvent.change(box, { target: { value: 'a'.repeat(3700) } }); expect(send).toBeEnabled(); expect(screen.getByText('3700/4000')).toBeInTheDocument();
    fireEvent.change(box, { target: { value: 'line' } });
    fireEvent.keyDown(box, { key: 'Enter', shiftKey: true }); expect(api.request.mock.calls.filter(c => c[1] === 'POST')).toHaveLength(0);
    fireEvent.keyDown(box, { key: 'Enter' }); await waitFor(() => expect(api.request.mock.calls.filter(c => c[1] === 'POST')).toHaveLength(1));
  });
  it('sends queued messages one at a time', async () => {
    const releases: Array<(m: HumanMessage) => void> = [];
    const api = makeApi((path, method) => method === 'POST' ? new Promise<HumanMessage>(r => releases.push(r)) : threadHandler()(path));
    await open(api);
    for (const text of ['same', 'same']) { fireEvent.change(screen.getByLabelText('Message'), { target: { value: text } }); fireEvent.click(screen.getByRole('button', { name: 'Send' })); }
    await waitFor(() => expect(releases).toHaveLength(1));
    await act(async () => releases[0](msg('message_s1', new Date().toISOString(), 'same', 'pat1')));
    await waitFor(() => expect(releases).toHaveLength(2));
  });
});

describe('access, unread and polling', () => {
  it('marks the open conversation notices read once its messages are loaded', async () => {
    const markRead = jest.fn().mockResolvedValue(undefined); unreadStore.markRead = markRead;
    unreadStore.publish('pat1', [notice('n1', 'message_aa'), notice('n2', 'unrelated')]);
    render(<MessagesScreen api={makeApi(threadHandler())} role="patient" patientRelationships={relationships} onError={jest.fn()} />);
    const button = await screen.findByRole('button', { name: /Your psychologist/ });
    await waitFor(() => expect(within(button).getByLabelText('1 unread')).toBeInTheDocument());
    fireEvent.click(button);
    await waitFor(() => expect(markRead).toHaveBeenCalledWith(['n1']));
    expect(markRead).toHaveBeenCalledTimes(1);
  });
  it('stops, clears messages and reports access lost on 403', async () => {
    let forbidden = false;
    const api = makeApi(path => { if (forbidden) throw new PlatformClientError(403, 'forbidden'); return threadHandler()(path); });
    const onError = await open(api);
    forbidden = true; jest.useFakeTimers();
    try {
      window.dispatchEvent(new Event('focus'));
      await act(async () => { await jest.advanceTimersByTimeAsync(0); });
    } finally { jest.useRealTimers(); }
    await waitFor(() => expect(onError).toHaveBeenCalledTimes(1));
    expect(screen.queryByText('newer from patient')).not.toBeInTheDocument();
    const calls = api.request.mock.calls.length; window.dispatchEvent(new Event('focus')); await new Promise(r => setTimeout(r, 20)); expect(api.request.mock.calls.length).toBe(calls);
  });
  it('polls the open conversation on the configured interval', async () => {
    jest.useFakeTimers();
    try {
      const api = makeApi(threadHandler());
      render(<MessagesScreen api={api} role="patient" patientRelationships={relationships} onError={jest.fn()} />);
      await act(async () => { await jest.advanceTimersByTimeAsync(0); });
      fireEvent.click(screen.getByRole('button', { name: /Your psychologist/ }));
      await act(async () => { await jest.advanceTimersByTimeAsync(0); });
      const before = api.request.mock.calls.length;
      await act(async () => { await jest.advanceTimersByTimeAsync(8000); });
      expect(api.request.mock.calls.length).toBeGreaterThan(before);
    } finally { jest.useRealTimers(); }
  });
});

describe('idempotency key reuse in the real client', () => {
  it('reuses the same Idempotency-Key when a send is retried after a network failure', async () => {
    if (!globalThis.crypto?.randomUUID) Object.defineProperty(globalThis, 'crypto', { value: { randomUUID: () => `id-${Math.random().toString(36).slice(2)}-${Date.now()}` }, configurable: true });
    const seen: string[] = []; let attempt = 0;
    const fetcher = jest.fn(async (_path: string, init: RequestInit) => { seen.push((init.headers as Record<string, string>)['Idempotency-Key']); if (++attempt === 1) throw new TypeError('network'); return { ok: true, status: 201, json: async () => ({ id: 'message_1' }) } as Response; });
    const user = { uid: 'u1', getIdToken: async () => 'token' };
    const api = professionalApi('u1', () => user, fetcher as unknown as typeof fetch);
    const body = { relationship_id: 'rel1', body: 'hi' };
    await expect(api.request('/api/v1/messages', 'POST', body)).rejects.toMatchObject({ status: 503 });
    await api.request('/api/v1/messages', 'POST', body);
    expect(seen).toHaveLength(2); expect(seen[1]).toBe(seen[0]); expect(seen[0]).toBeTruthy();
  });
});
