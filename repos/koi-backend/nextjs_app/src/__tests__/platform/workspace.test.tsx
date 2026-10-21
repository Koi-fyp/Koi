jest.mock('server-only', () => ({}), { virtual: true });
import React from 'react';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { TextEncoder } from 'node:util';
import { webcrypto } from 'node:crypto';
import ProfessionalWorkspace from '@/components/professional/ProfessionalWorkspace';
import { FeedbackProviders } from '@/components/ui/feedback';
import { PlatformService } from '@/lib/platform/server/service';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import { MemoryPlatformStore, registered, actor, testTime } from '../../../test/platform-memory';

Object.defineProperty(globalThis, 'TextEncoder', { value: TextEncoder, configurable: true });
Object.defineProperty(globalThis.crypto, 'subtle', { value: webcrypto.subtle, configurable: true });
let store: MemoryPlatformStore, service: PlatformService;
/** Real service and contract validation; only identity/network/persistent database are test doubles. */
function bridge(uid = 'clinician_a'): ProfessionalApi {
  let counter = 0;
  return { dispose: jest.fn(), request: jest.fn(async (path: string, method = 'GET', body?: any) => {
    const url = new URL(path, 'http://localhost'), parts = url.pathname.split('/');
    const key = `functional_${++counter}`, user = actor(uid);
    try {
      if (path === '/api/v1/me/capabilities') return await service.capabilities(user);
      if (path === '/api/v1/professional/organizations') return await service.createOrganization(user, body, key);
      if (parts[4] === 'questionnaire-versions') return await service.getVersion(user, parts[5]);
      if (parts[4] === 'questionnaires') {
        if (parts[6] === 'publish') return await service.publish(user, parts[5], body, key);
        if (parts[5]) return method === 'PUT' ? await service.updateDraft(user, parts[5], body, key) : await service.getDraft(user, parts[5]);
        return method === 'POST' ? await service.createDraft(user, body, key) : await service.listDrafts(user, url.searchParams.get('organization_id')!, 25, url.searchParams.get('cursor') ?? undefined);
      }
      throw new Error('Unrecognized functional endpoint');
    } catch (error: any) { throw new PlatformClientError(error.status ?? 503, error.code ?? 'unavailable'); }
  }) as any };
}
beforeEach(() => { store = new MemoryPlatformStore(); registered(store, 'clinician_a'); service = new PlatformService(store, 'functional-key-with-at-least-32-characters', () => testTime); jest.spyOn(window, 'confirm').mockReturnValue(true); window.history.replaceState({}, '', '/professional?view=questionnaires'); });
afterEach(() => jest.restoreAllMocks());
const text = (name: string, value: string) => fireEvent.change(screen.getByRole('textbox', { name }), { target: { value } });

async function newSavedForm(api: ProfessionalApi) {
  render(<ProfessionalWorkspace api={api} onSessionExpired={jest.fn()} />, { wrapper: FeedbackProviders });
  await screen.findByRole('heading', { name: 'Create your organization' });
  text('Organization name', 'Fictional practice'); fireEvent.click(screen.getByRole('button', { name: 'Create organization' }));
  await screen.findByText('Organization created.'); fireEvent.click(screen.getByRole('button', { name: 'Create manually' }));
  text('Title · English', 'Original manual form'); text('Question 1 · English', 'What would you like to discuss?');
  fireEvent.click(screen.getByRole('button', { name: 'Save draft' })); await screen.findByText('Draft saved. Revision 1.');
}
it('completes organization -> manual form with picture -> save -> immutable publish -> later reopen/inspect', async () => {
  const api = bridge(); const view = render(<ProfessionalWorkspace api={api} onSessionExpired={jest.fn()} />, { wrapper: FeedbackProviders });
  await screen.findByRole('heading', { name: 'Create your organization' });
  text('Organization name', 'Fictional practice'); fireEvent.click(screen.getByRole('button', { name: 'Create organization' }));
  await screen.findByText('Organization created.'); fireEvent.click(screen.getByRole('button', { name: 'Create manually' }));
  text('Title · English', 'Original manual form'); text('Question 1 · English', 'What would you like to discuss?');
  fireEvent.click(screen.getByRole('button', { name: 'Add question' }));
  fireEvent.change(screen.getByRole('combobox', { name: 'Question 2 type' }), { target: { value: 'image_single_choice' } });
  text('Question 2 · English', 'Choose a shape');
  fireEvent.click(within(screen.getByRole('group', { name: 'Question 2 option 1 picture' })).getByRole('button', { name: /Triangle/ }));
  fireEvent.click(screen.getByRole('button', { name: 'Save draft' })); await screen.findByText('Draft saved. Revision 1.');
  fireEvent.click(screen.getByRole('button', { name: 'Publish saved revision' }));
  // Themed dialog replaces the native confirm: confirm explicitly, then the success snackbar appears.
  fireEvent.click(within(await screen.findByRole('alertdialog', { name: 'Publish revision 1?' })).getByRole('button', { name: 'Publish revision' }));
  await screen.findByText('Published. This version is immutable.'); expect(await screen.findByText('Revision published')).toBeInTheDocument(); expect(window.confirm).not.toHaveBeenCalled();
  expect(within(screen.getByRole('region', { name: 'Published questionnaire' })).getByText('Original manual form')).toBeVisible();
  text('Title · English', 'Edited manual form'); expect(screen.getByRole('button', { name: 'Publish saved revision' })).toBeDisabled();
  fireEvent.click(screen.getByRole('button', { name: 'Save draft' })); await screen.findByText('Draft saved. Revision 2.');
  expect(within(screen.getByRole('region', { name: 'Published questionnaire' })).getByText('Original manual form')).toBeVisible();
  view.unmount();
  render(<ProfessionalWorkspace api={bridge()} onSessionExpired={jest.fn()} />);
  fireEvent.click(await screen.findByRole('button', { name: 'Open draft: Edited manual form' }));
  await screen.findByRole('heading', { name: 'Edit draft · Revision 2' });
  fireEvent.change(screen.getByRole('spinbutton', { name: 'Published revision to inspect' }), { target: { value: '1' } });
  fireEvent.click(screen.getByRole('button', { name: 'Inspect published revision' }));
  await screen.findByRole('region', { name: 'Published questionnaire' });
  expect(within(screen.getByRole('region', { name: 'Published questionnaire' })).getByText('Original manual form')).toBeVisible();
  expect(store.count('questionnaire_versions')).toBe(1); expect(store.count('ai_jobs')).toBe(0);
});
it('preserves unsaved edits on a revision conflict and allows deliberate reload', async () => {
  const api = bridge(); await newSavedForm(api);
  const draft: any = [...store.data.entries()].find(([key]) => key.startsWith('questionnaires/'))![1];
  await service.updateDraft(actor(), draft.id, { expected_revision: 1, content: { ...draft.content, title: { en: 'Another device title' } } }, 'other_device');
  text('Title · English', 'My unsaved title'); fireEvent.click(screen.getByRole('button', { name: 'Save draft' }));
  await screen.findByRole('alert'); expect(screen.getByRole('textbox', { name: 'Title · English' })).toHaveValue('My unsaved title');
  fireEvent.click(screen.getByRole('button', { name: 'Reload saved draft' }));
  fireEvent.click(await screen.findByRole('button', { name: 'Discard edits' }));
  await waitFor(() => expect(screen.getByRole('textbox', { name: 'Title · English' })).toHaveValue('Another device title'));
});
it('clears protected editor content when verification is suspended before an action', async () => {
  const api = bridge(); await newSavedForm(api);
  const verification = store.read('psychologist_verifications', 'clinician_a'); store.seed('psychologist_verifications', 'clinician_a', { ...verification, state: 'suspended' });
  text('Title · English', 'Unsaved after suspension'); fireEvent.click(screen.getByRole('button', { name: 'Save draft' }));
  await screen.findByRole('heading', { name: 'Practice access required' });
  expect(screen.queryByRole('textbox', { name: 'Title · English' })).not.toBeInTheDocument(); expect(screen.queryByText('Unsaved after suspension')).not.toBeInTheDocument();
});
it('denies guests and does not substitute demo data when the platform is unavailable', async () => {
  const view = render(<ProfessionalWorkspace api={bridge('guest')} onSessionExpired={jest.fn()} />);
  await screen.findByRole('heading', { name: 'Practice access required' }); expect(screen.queryByRole('button', { name: 'Create manually' })).not.toBeInTheDocument(); view.unmount();
  render(<ProfessionalWorkspace api={{ request: jest.fn().mockRejectedValue(new PlatformClientError(503, 'unavailable')), dispose: jest.fn() }} onSessionExpired={jest.fn()} />);
  await screen.findByRole('heading', { name: 'Workspace unavailable' }); expect(screen.queryByRole('textbox', { name: 'Organization name' })).not.toBeInTheDocument();
});
it('edits Urdu with RTL and supports all seven question types in the manual editor', async () => {
  await newSavedForm(bridge());
  fireEvent.click(screen.getByRole('checkbox', { name: 'Urdu' }));
  expect(screen.getByRole('textbox', { name: 'Title · Urdu' })).toHaveAttribute('dir', 'rtl');
  text('Title · Urdu', 'نمونہ فارم'); text('Question 1 · Urdu', 'آپ کیا کہنا چاہیں گے؟');
  for (const value of ['single_choice', 'multi_choice', 'yes_no', 'likert', 'short_text', 'image_single_choice', 'image_multi_choice']) {
    fireEvent.change(screen.getByRole('combobox', { name: 'Question 1 type' }), { target: { value } });
    expect(screen.getByRole('combobox', { name: 'Question 1 type' })).toHaveValue(value);
  }
  fireEvent.click(screen.getByRole('button', { name: 'Save draft' })); await screen.findByText('Draft saved. Revision 2.');
});
