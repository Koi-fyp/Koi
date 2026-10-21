import type { CapabilitiesDTO } from './types';
export interface PlatformLink { label: string; href: string }
/** Capabilities must come from the authenticated server response, never a Firebase role claim. */
export function platformLinks(caps: CapabilitiesDTO | null): PlatformLink[] {
  const links = [{ label: 'KOI home', href: '/?home=1' }, { label: 'KOI companion', href: '/chat' }];
  if (!caps || caps.account_state !== 'registered') return [...links, { label: 'Account sign-in', href: '/account' }];
  if (caps.capabilities.expert_directory) links.push({ label: 'Find an Expert', href: '/patient?view=experts#experts' });
  if (caps.active_patient_relationships.length) links.push(
    { label: 'My Psychologist', href: '/patient?view=care#care' }, { label: 'Questionnaires', href: '/patient?view=questionnaires#questionnaires' },
    { label: 'Messages', href: '/patient?view=messages#messages' }, { label: 'Appointments', href: '/patient?view=appointments#care' }, { label: 'Notifications', href: '/patient?view=notifications#notifications' },
  );
  if (caps.capabilities.professional_workspace) links.push(
    { label: 'Professional Dashboard', href: '/professional?view=dashboard#practice-dashboard' }, { label: 'Professional Questionnaires', href: '/professional?view=questionnaires#professional-questionnaires' },
    { label: 'Patients', href: '/professional?view=patients#patients' }, { label: 'Messages', href: '/professional?view=messages#messages' }, { label: 'Submissions', href: '/professional?view=submissions#submissions' }, { label: 'Analytics', href: '/professional?view=analytics#practice-analytics' },
  );
  return [...links, { label: 'Account', href: '/account' }];
}
