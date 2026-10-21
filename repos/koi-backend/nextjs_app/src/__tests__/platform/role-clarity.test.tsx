import React from 'react';
import { render, screen, within } from '@testing-library/react';
import type { ProfessionalApi } from '@/lib/platform/client';
import type { CapabilitiesDTO } from '@/lib/platform/types';
import type { Connection } from '@/lib/platform/patient-types';
jest.mock('@/components/messaging/MessagesScreen', () => ({ __esModule: true, default: () => <div>Message fixture</div> }));
import PatientWorkspace from '@/components/patient/PatientWorkspace';
import WorkspaceFrame, { professionalViews } from '@/components/platform/WorkspaceFrame';
import ApplicationTimeline, { timelineStates } from '@/components/patient/ApplicationTimeline';
import { FeedbackProviders } from '@/components/ui/feedback';

const caps = (patient: boolean): CapabilitiesDTO => ({ uid: 'general-fixture', contract_version: '0.5.0', account_state: 'registered', authorization_revision: 1, capabilities: { expert_directory: true, professional_workspace: false, companion_account_sync: true, create_organization: false }, professional_organization_ids: [], active_patient_relationships: patient ? [{ relationship_id: 'rel-1', organization_id: 'org-1', psychologist_uid: 'psy-1' }] : [] });
const application = (state: Connection['state']): Connection => ({ id: 'app-1', organization_id: 'org-1', applicant_uid: 'general-fixture', psychologist_uid: 'psy-1', state, demo_payment_state: 'demo_completed', revision: 1, created_at: '2026-10-21T00:00:00Z', updated_at: '2026-10-21T00:00:00Z' });
const apiFor = (value: CapabilitiesDTO, state: Connection['state'] = 'pending_psychologist_review'): ProfessionalApi => ({ dispose: jest.fn(), request: jest.fn(async (path: string) => {
  if (path.endsWith('/capabilities')) return value;
  if (path.startsWith('/api/v1/connection-requests')) return { items: [application(state)], next_cursor: null };
  return { items: [], next_cursor: null };
}) as any });
beforeEach(() => window.history.replaceState(null, '', '/patient'));

it('maps the application timeline from the server state', () => {
  expect(timelineStates('requested')).toEqual(['done', 'current', 'upcoming', 'upcoming']);
  expect(timelineStates('awaiting_demo_payment')).toEqual(['done', 'current', 'upcoming', 'upcoming']);
  expect(timelineStates('pending_psychologist_review')).toEqual(['done', 'done', 'current', 'upcoming']);
  expect(timelineStates('accepted')).toEqual(['done', 'done', 'done', 'done']);
  expect(timelineStates('rejected')).toBeNull();
  render(<ApplicationTimeline state="pending_psychologist_review" />);
  const steps = within(screen.getByRole('list', { name: 'Application progress' })).getAllByRole('listitem');
  expect(steps.map(s => s.textContent)).toEqual(['✓ Applied (done)', '✓ Payment (done)', 'Pending (in progress)', 'Accepted (upcoming)']);
  expect(steps[2]).toHaveAttribute('aria-current', 'step');
});
it('labels a General User prominently and explains what unlocks after acceptance', async () => {
  render(<PatientWorkspace api={apiFor(caps(false))} onDenied={jest.fn()} />);
  expect(await screen.findByText('General User Dashboard')).toHaveClass('care-role-badge');
  expect(document.querySelector('[data-role="General User"]')).toHaveTextContent('Your role: General User');
  expect(screen.getByText('Questionnaires, Messages and Appointments appear after acceptance.')).toBeVisible();
  expect(await screen.findByRole('list', { name: 'Application progress' })).toBeInTheDocument();
});
it('switches to Patient on the next capabilities refresh and announces it once', async () => {
  const view = render(<PatientWorkspace api={apiFor(caps(false))} onDenied={jest.fn()} />, { wrapper: FeedbackProviders });
  await screen.findByText('General User Dashboard');
  view.rerender(<PatientWorkspace api={apiFor(caps(true), 'accepted')} onDenied={jest.fn()} />);
  expect(await screen.findByText('Patient Dashboard')).toBeInTheDocument();
  expect(document.querySelector('[data-role="Patient"]')).toBeInTheDocument();
  expect(await screen.findByText('You are now a patient of psychologist psy-1')).toBeInTheDocument();
  expect(screen.queryByText(/appear after acceptance/)).not.toBeInTheDocument();
});
it('shows Psychologist in the practice workspace header', () => {
  render(<WorkspaceFrame base="/professional" views={professionalViews} view="dashboard" role="Psychologist" workspaceLabel="Psychologist Dashboard"><p>content</p></WorkspaceFrame>);
  expect(document.querySelector('[data-role="Psychologist"]')).toHaveTextContent('Psychologist');
  expect(within(screen.getByRole('navigation', { name: 'Practice navigation' })).getByText('Psychologist Dashboard')).toBeInTheDocument();
});
