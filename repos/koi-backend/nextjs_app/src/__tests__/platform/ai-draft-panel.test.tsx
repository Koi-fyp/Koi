jest.mock('server-only', () => ({}), { virtual: true });
import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { TextEncoder } from 'node:util';
import { webcrypto } from 'node:crypto';
import ProfessionalWorkspace from '@/components/professional/ProfessionalWorkspace';
import { PlatformService } from '@/lib/platform/server/service';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import { actor, manualContent, MemoryPlatformStore, registered, testTime } from '../../../test/platform-memory';

Object.defineProperty(globalThis, 'TextEncoder', { value: TextEncoder, configurable: true });
Object.defineProperty(globalThis.crypto, 'subtle', { value: webcrypto.subtle, configurable: true });
const AI_PATH = '/api/v1/professional/questionnaire-drafts/ai';
let store: MemoryPlatformStore, service: PlatformService, aiCall: jest.Mock;
/** Real service for saving and confirming; only the AI endpoint and the network are doubles. */
function bridge(): ProfessionalApi {
  let counter = 0;
  return { dispose: jest.fn(), request: jest.fn(async (path: string, method = 'GET', body?: any) => {
    const url = new URL(path, 'http://localhost'), parts = url.pathname.split('/'), key = `ai_${++counter}`, user = actor('clinician_a');
    try {
      if (path === '/api/v1/me/capabilities') return await service.capabilities(user);
      if (path === AI_PATH) return await aiCall(body);
      if (parts[4] === 'questionnaires') {
        if (parts[6] === 'confirm-review') return await service.confirmAiDraftReview(user, parts[5], body, key);
        if (parts[6] === 'publish') return await service.publish(user, parts[5], body, key);
        if (parts[5]) return method === 'PUT' ? await service.updateDraft(user, parts[5], body, key) : await service.getDraft(user, parts[5]);
        return method === 'POST' ? await service.createDraft(user, body, key) : await service.listDrafts(user, url.searchParams.get('organization_id')!, 25, undefined);
      }
      throw new Error('Unrecognized endpoint');
    } catch (error: any) { throw error instanceof PlatformClientError ? error : new PlatformClientError(error.status ?? 503, error.code ?? 'unavailable'); }
  }) as any };
}
const aiContent = () => ({ ...manualContent(), origin: 'ai_drafted' as const, title: { en: 'AI sleep check' } });
const provenance = { provider: 'fictional-provider', model_id: 'model-9', prompt_version: 'prompt-v4', sources: ['Source A'] };
beforeEach(async () => {
  store = new MemoryPlatformStore(); registered(store, 'clinician_a');
  service = new PlatformService(store, 'functional-key-with-at-least-32-characters', () => testTime);
  await service.createOrganization(actor('clinician_a'), { name: 'Fictional practice' }, 'org_key');
  aiCall = jest.fn(async () => ({ content: aiContent(), provenance, notice: 'AI draft, not validated; the psychologist must review every question' }));
  jest.spyOn(window, 'confirm').mockReturnValue(true); window.history.replaceState({}, '', '/professional?view=questionnaires');
});
afterEach(() => jest.restoreAllMocks());
const fill = () => { fireEvent.change(screen.getByRole('textbox', { name: 'AI topic' }), { target: { value: 'Sleep' } }); fireEvent.change(screen.getByRole('textbox', { name: 'AI audience' }), { target: { value: 'Adults' } }); };
const open = async () => { render(<ProfessionalWorkspace api={bridge()} onSessionExpired={jest.fn()} />); fireEvent.click(await screen.findByRole('button', { name: 'Draft with AI' })); await screen.findByRole('heading', { level: 2, name: 'Draft with AI' }); };

it('offers English, Urdu and Roman Urdu with 8 questions by default and needs topic and audience', async () => {
  await open();
  expect(screen.getByRole('spinbutton', { name: 'Number of questions' })).toHaveValue(8);
  expect(screen.getByRole('combobox', { name: 'AI language' }).textContent).toBe('EnglishاردوRoman Urdu');
  expect(screen.getByRole('button', { name: 'Generate draft' })).toBeDisabled();
  fill(); expect(screen.getByRole('button', { name: 'Generate draft' })).toBeEnabled();
});
it('loads the AI draft unsaved with banner and provenance; saving keeps ai_drafted and publish stays blocked until the server confirmation', async () => {
  await open(); fill(); fireEvent.change(screen.getByRole('combobox', { name: 'AI language' }), { target: { value: 'roman_ur' } });
  fireEvent.click(screen.getByRole('button', { name: 'Generate draft' }));
  await screen.findByText('AI draft, not validated: review every question before saving.');
  expect(aiCall).toHaveBeenCalledWith({ topic: 'Sleep', audience: 'Adults', language: 'roman_ur', count: 8 });
  expect(screen.getByText(/fictional-provider/)).toBeVisible(); expect(screen.getByText(/model-9/)).toBeVisible(); expect(screen.getByText(/prompt-v4/)).toBeVisible(); expect(screen.getByText(/Source A/)).toBeVisible();
  expect(screen.getByRole('textbox', { name: 'Title · English' })).toHaveValue('AI sleep check'); expect(screen.getByText('Unsaved changes')).toBeVisible();
  expect(store.count('questionnaires')).toBe(0);
  const box = screen.getByRole('checkbox', { name: 'I reviewed this draft' }); expect(box).toBeDisabled();
  fireEvent.click(screen.getByRole('button', { name: 'Save draft' })); await screen.findByText('Draft saved. Revision 1.');
  expect(store.read<any>('questionnaires', Object.keys(Object.fromEntries(store.data)).find(k => k.startsWith('questionnaires/'))!.split('/')[1]).content.origin).toBe('ai_drafted');
  expect(screen.getByRole('button', { name: 'Publish saved revision' })).toBeDisabled(); expect(screen.getByText(/cannot be published/)).toBeVisible();
  expect(box).toBeEnabled(); fireEvent.click(box);
  await screen.findByText('Review confirmed. Revision 2 can now be published.');
  expect(screen.queryByText('AI draft, not validated: review every question before saving.')).toBeNull();
  expect(screen.getByRole('button', { name: 'Publish saved revision' })).toBeEnabled();
  expect([...store.data.values()].some((v: any) => v?.operation === 'confirmAiDraftReview')).toBe(true);
});
it.each([
  ['not configured', new PlatformClientError(503, 'ai_unavailable'), /not configured/],
  ['rate limited', new PlatformClientError(429, 'rate_limited'), /busy or your limit/],
  ['provider error', new PlatformClientError(502, 'ai_provider_error'), /could not produce a usable draft/],
])('shows a clear %s state with a build-manually fallback', async (_name, failure, message) => {
  aiCall.mockRejectedValue(failure); await open(); fill();
  fireEvent.click(screen.getByRole('button', { name: 'Generate draft' }));
  expect(await screen.findByText(message)).toBeVisible(); expect(store.count('questionnaires')).toBe(0);
  fireEvent.click(screen.getByRole('button', { name: 'Build manually instead' }));
  await screen.findByRole('heading', { name: 'New manual questionnaire' });
  expect(screen.queryByText(message)).toBeNull();
});
it('shows progress while generating', async () => {
  let release: (value: unknown) => void = () => {}; aiCall.mockImplementation(() => new Promise(resolve => { release = resolve; }));
  await open(); fill(); fireEvent.click(screen.getByRole('button', { name: 'Generate draft' }));
  expect(await screen.findByText(/up to 60 seconds/)).toBeVisible();
  release({ content: aiContent(), provenance, notice: 'x' });
  await waitFor(() => expect(screen.queryByText(/up to 60 seconds/)).toBeNull());
});
