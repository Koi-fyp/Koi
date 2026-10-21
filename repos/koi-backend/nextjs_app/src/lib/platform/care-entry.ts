import type { CapabilitiesDTO } from './types';

export type CareEntryIntent = 'general' | 'patient' | 'psychologist';
export function careEntryIntent(value: string | null): CareEntryIntent | null {
  return value === 'general' || value === 'patient' || value === 'psychologist' ? value : null;
}
export const careEntryCopy = {
  general: { heading: 'Welcome to KOI Care', description: 'Find psychologists, explore care and apply to practices with your registered care account.' },
  patient: { heading: 'Patient Access', description: 'Access assigned questionnaires, human messaging and appointments after establishing an active care relationship.' },
  psychologist: { heading: 'Psychologist Access', description: 'Verified psychologists can manage their practice, patients, questionnaires, submissions and appointments.' },
};
/** An entry is a preference, never an authorization source. */
export function careEntryDestination(intent: CareEntryIntent, caps: CapabilitiesDTO): string | null {
  if (caps.account_state !== 'registered') return null;
  if (intent === 'general' && caps.capabilities.expert_directory) return '/patient';
  if (intent === 'patient' && caps.active_patient_relationships.length) return '/patient';
  if (intent === 'psychologist' && caps.capabilities.professional_workspace) return '/professional?view=dashboard#practice-dashboard';
  return null;
}
