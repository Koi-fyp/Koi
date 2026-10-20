import React from 'react';
import { render, screen, waitFor, act } from '@testing-library/react';
import { platformLinks } from '@/lib/platform/navigation';
import type { CapabilitiesDTO } from '@/lib/platform/types';
const mockRequest = jest.fn(), mockDispose = jest.fn();
let mockUser: { uid: string } | null = { uid: 'patient' };
jest.mock('@/lib/platform/professional-auth', () => ({ useProfessionalAuth: () => ({ loading: false, user: mockUser, currentUser: () => mockUser }) }));
jest.mock('@/lib/platform/client', () => ({ professionalApi: () => ({ request: mockRequest, dispose: mockDispose }) }));
import PlatformNavigation from '@/components/platform/PlatformNavigation';
const caps = (general: boolean, professional: boolean, patient: boolean): CapabilitiesDTO => ({ uid: 'patient', contract_version: '0.5.0', account_state: 'registered', authorization_revision: 1, capabilities: { expert_directory: general, professional_workspace: professional, companion_account_sync: general, create_organization: false }, professional_organization_ids: professional ? ['org'] : [], active_patient_relationships: patient ? [{ relationship_id: 'rel', organization_id: 'org', psychologist_uid: 'pro' }] : [] });
beforeEach(() => { mockUser = { uid: 'patient' }; mockRequest.mockReset(); });
it('composes navigation only from server account capabilities and relationships', () => {
  expect(platformLinks(null).map(l => l.label)).toEqual(['KOI home', 'KOI companion', 'Account sign-in']);
  expect(platformLinks(caps(true, false, false)).map(l => l.label)).not.toContain('Questionnaires');
  expect(platformLinks(caps(true, false, true)).map(l => l.label)).toEqual(expect.arrayContaining(['Messages', 'Appointments', 'Questionnaires']));
  expect(platformLinks(caps(false, true, false)).map(l => l.label)).not.toContain('My Psychologist');
  expect(platformLinks({ ...caps(true, true, true), account_state: 'suspended' }).map(l => l.label)).not.toContain('Professional Dashboard');
});
it('locks navigation after an authority fetch fails and never caches capabilities across UIDs', async () => {
  mockRequest.mockResolvedValue(caps(true, false, true)); const view = render(<PlatformNavigation expanded />);
  await screen.findByRole('link', { name: 'Messages' });
  mockRequest.mockRejectedValue(new Error('revoked')); await act(async () => window.dispatchEvent(new Event('focus')));
  await waitFor(() => expect(screen.queryByRole('link', { name: 'Messages' })).not.toBeInTheDocument());
  mockUser = { uid: 'different' }; view.rerender(<PlatformNavigation expanded />);
  expect(screen.queryByRole('link', { name: 'Messages' })).not.toBeInTheDocument();
  expect(mockDispose).toHaveBeenCalled();
});
it('does not fetch capabilities for a signed-out visitor', () => { mockUser = null; render(<PlatformNavigation expanded />); expect(mockRequest).not.toHaveBeenCalled(); expect(screen.getByRole('link', { name: 'Account sign-in' })).toHaveAttribute('href', '/account'); });
