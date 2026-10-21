import type { CapabilitiesDTO } from './types';
import type { Connection } from './patient-types';

export function hasPatientAccess(caps: CapabilitiesDTO): boolean {
  return caps.account_state === 'registered' && caps.active_patient_relationships.length > 0;
}
export function applicationLabel(connection: Connection, caps: CapabilitiesDTO): string {
  if (connection.state === 'accepted') return hasPatientAccess(caps) && caps.active_patient_relationships.some(r => r.organization_id === connection.organization_id && r.psychologist_uid === connection.psychologist_uid) ? 'Application accepted · Your care is active' : 'Application accepted previously';
  return {
    requested: 'Application submitted',
    awaiting_demo_payment: 'Demo step required',
    pending_psychologist_review: 'Waiting for practice review',
    rejected: 'Application declined',
    withdrawn: 'Application withdrawn',
  }[connection.state];
}
