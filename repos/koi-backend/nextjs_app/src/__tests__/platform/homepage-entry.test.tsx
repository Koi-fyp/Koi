import React from 'react';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import type { CapabilitiesDTO } from '@/lib/platform/types';
import { careEntryDestination, type CareEntryIntent } from '@/lib/platform/care-entry';
const mockReplace = jest.fn(), mockRequest = jest.fn(), mockDispose = jest.fn(), mockSignIn = jest.fn(), mockSignOut = jest.fn();
const mockRouter = { replace: mockReplace };
let mockUser: { uid: string; email?: string } | null = null;
jest.mock('next/navigation', () => ({ useRouter: () => mockRouter }));
jest.mock('@/lib/platform/professional-auth', () => ({ useProfessionalAuth: () => ({ loading: false, error: false, user: mockUser, currentUser: () => mockUser, signIn: mockSignIn, signOut: mockSignOut }) }));
jest.mock('@/lib/platform/client', () => ({ professionalApi: () => ({ request: mockRequest, dispose: mockDispose }) }));
jest.mock('@/components/platform/PlatformNavigation', () => ({ __esModule: true, default: () => <nav>Existing account overview</nav> }));
import HomepageEntryMenu from '@/components/platform/HomepageEntryMenu';
import AccountApp from '@/components/platform/AccountApp';

function caps(general = false, patient = false, professional = false): CapabilitiesDTO {
  return { uid: 'fixture', contract_version: '0.5.0', account_state: 'registered', authorization_revision: 1, capabilities: { expert_directory: general, professional_workspace: professional, create_organization: false, companion_account_sync: false }, professional_organization_ids: professional ? ['org'] : [], active_patient_relationships: patient ? [{ relationship_id: 'rel', organization_id: 'org', psychologist_uid: 'pro' }] : [] };
}
beforeEach(() => { jest.clearAllMocks(); mockUser = null; window.history.replaceState(null, '', '/account'); });

it('always presents exactly four ordered entry choices with semantic care links', () => {
  render(<HomepageEntryMenu onAnonymous={jest.fn()} />);
  fireEvent.click(screen.getByRole('button', { name: /Explore KOI/ }));
  const menu = screen.getByRole('dialog');
  expect([...menu.querySelectorAll('[data-entry]')].map(el => el.getAttribute('aria-label'))).toEqual(['Continue Anonymously', 'Continue as General User', 'Continue as Patient', 'Continue as Psychologist']);
  for (const intent of ['general', 'patient', 'psychologist']) expect(menu.querySelector(`a[href="/account?entry=${intent}"]`)).toBeInTheDocument();
  expect(within(menu).queryByText('Professional Dashboard')).not.toBeInTheDocument();
});
it('focuses an entry, closes on Escape/outside/close and restores focus to its trigger', () => {
  render(<HomepageEntryMenu onAnonymous={jest.fn()} />);
  const trigger = screen.getByRole('button', { name: /Explore KOI/ });
  for (const method of ['escape', 'outside', 'close']) {
    fireEvent.click(trigger);
    expect(screen.getByRole('button', { name: 'Continue Anonymously' })).toHaveFocus();
    if (method === 'escape') fireEvent.keyDown(document, { key: 'Escape' });
    if (method === 'outside') fireEvent.pointerDown(document.body);
    if (method === 'close') fireEvent.click(screen.getByRole('button', { name: 'Close entry menu' }));
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument(); expect(trigger).toHaveFocus(); expect(trigger).toHaveAttribute('aria-expanded', 'false');
  }
});
it('keeps keyboard traversal inside the open selector and calls only the existing anonymous entry callback', () => {
  const anonymous = jest.fn(); render(<HomepageEntryMenu onAnonymous={anonymous} />);
  fireEvent.click(screen.getByRole('button', { name: /Explore KOI/ }));
  screen.getByRole('link', { name: 'Continue as Psychologist' }).focus();
  fireEvent.keyDown(document, { key: 'Tab' });
  expect(screen.getByRole('button', { name: 'Close entry menu' })).toHaveFocus();
  fireEvent.keyDown(document, { key: 'Tab', shiftKey: true });
  expect(screen.getByRole('link', { name: 'Continue as Psychologist' })).toHaveFocus();
  fireEvent.click(screen.getByRole('button', { name: 'Continue Anonymously' }));
  expect(anonymous).toHaveBeenCalledTimes(1); expect(screen.queryByRole('dialog')).not.toBeInTheDocument(); expect(mockRequest).not.toHaveBeenCalled();
});
it.each(['general', 'patient', 'psychologist'] as const)('preserves %s entry on refresh and reuses registered care sign-in', async intent => {
  window.history.replaceState(null, '', `/account?entry=${intent}`);
  render(<AccountApp />);
  expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(intent === 'general' ? 'Welcome to KOI Care' : intent === 'patient' ? 'Patient Access' : 'Psychologist Access');
  expect(screen.getByText(/Public registration is not available/)).toBeVisible();
  fireEvent.change(screen.getByRole('textbox', { name: 'Email' }), { target: { value: 'fixture@example.invalid' } });
  fireEvent.change(screen.getByLabelText('Password'), { target: { value: 'fixture-only-password' } });
  fireEvent.click(screen.getByRole('button', { name: 'Sign in' }));
  await waitFor(() => expect(mockSignIn).toHaveBeenCalledWith('fixture@example.invalid', 'fixture-only-password'));
  expect(mockRequest).not.toHaveBeenCalled(); expect(mockReplace).not.toHaveBeenCalled();
});
const accounts = [
  ['general', caps(true), [true, false, false]],
  ['patient', caps(true, true), [true, true, false]],
  ['professional', caps(false, false, true), [false, false, true]],
  ['multi-capability', caps(true, true, true), [true, true, true]],
  ['unauthorized', caps(), [false, false, false]],
  ['suspended', { ...caps(true, true, true), account_state: 'suspended' }, [false, false, false]],
] as const;
describe.each(accounts)('%s account', (_label, capability, allowed) => {
  it.each(['general', 'patient', 'psychologist'] as const)('checks server authority before opening the %s workspace', async intent => {
    mockUser = { uid: 'fixture' }; mockRequest.mockResolvedValue(capability);
    window.history.replaceState(null, '', `/account?entry=${intent}`);
    render(<AccountApp />);
    expect(screen.getByRole('status')).toHaveTextContent('Checking your care access');
    expect(mockReplace).not.toHaveBeenCalled();
    await waitFor(() => expect(screen.queryByText('Checking your care access...')).not.toBeInTheDocument());
    const index = ['general', 'patient', 'psychologist'].indexOf(intent);
    if (allowed[index]) expect(mockReplace).toHaveBeenCalledWith(careEntryDestination(intent, capability as CapabilitiesDTO));
    else { expect(mockReplace).not.toHaveBeenCalled(); expect(screen.getByRole('region', { name: 'Care access information' })).toBeVisible(); }
    expect(mockRequest).toHaveBeenCalledWith('/api/v1/me/capabilities');
  });
});
it('rejects a mismatched UID, offers retry and does not redirect', async () => {
  mockUser = { uid: 'other' }; mockRequest.mockResolvedValue(caps(true, true, true));
  window.history.replaceState(null, '', '/account?entry=psychologist'); render(<AccountApp />);
  expect(await screen.findByRole('alert')).toHaveTextContent('could not be verified'); expect(mockReplace).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Retry access check' }));
  await waitFor(() => expect(mockRequest).toHaveBeenCalledTimes(2));
});
it('disposes pending access checks on sign-out and ignores a late authorized response', async () => {
  let resolve!: (value: CapabilitiesDTO) => void;
  mockRequest.mockReturnValue(new Promise<CapabilitiesDTO>(done => { resolve = done; })); mockUser = { uid: 'fixture' };
  window.history.replaceState(null, '', '/account?entry=psychologist'); const view = render(<AccountApp />);
  fireEvent.click(screen.getByRole('button', { name: 'Sign out of account' }));
  await waitFor(() => expect(mockSignOut).toHaveBeenCalled());
  mockUser = null; view.rerender(<AccountApp />);
  await act(async () => resolve(caps(true, true, true)));
  expect(mockDispose).toHaveBeenCalled(); expect(mockReplace).not.toHaveBeenCalled(); expect(screen.getByRole('button', { name: 'Sign in' })).toBeVisible();
});
it('updates entry guidance on Back/Forward without clearing the sign-in form', () => {
  window.history.replaceState(null, '', '/account?entry=patient'); render(<AccountApp />);
  fireEvent.change(screen.getByRole('textbox', { name: 'Email' }), { target: { value: 'fixture@example.invalid' } });
  for (const intent of ['psychologist', 'patient', 'general']) {
    act(() => { window.history.pushState(null, '', `/account?entry=${intent}`); window.dispatchEvent(new PopStateEvent('popstate')); });
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(intent === 'general' ? 'Welcome to KOI Care' : intent === 'patient' ? 'Patient Access' : 'Psychologist Access');
    expect(screen.getByRole('textbox', { name: 'Email' })).toHaveValue('fixture@example.invalid');
  }
});
it('ignores unrecognized role parameters and preserves the ordinary account overview', () => {
  window.history.replaceState(null, '', '/account?entry=admin'); render(<AccountApp />);
  expect(screen.getByRole('heading', { name: 'KOI Care account' })).toBeVisible(); expect(mockReplace).not.toHaveBeenCalled();
});
