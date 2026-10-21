import type { Appointment, CareNotification } from './community-types';

export const MIN_MINUTES = 10, MAX_MINUTES = 240;
/** Client-side checks mirroring the server rule (start in the future, end after start) plus a sane duration. */
export function proposalIssues(start: string, end: string, now = Date.now()): { start?: string; end?: string } {
  const issues: { start?: string; end?: string } = {};
  const from = Date.parse(start), to = Date.parse(end);
  if (!start) issues.start = 'Enter a start time.';
  else if (Number.isNaN(from)) issues.start = 'Enter a valid start time.';
  else if (from <= now) issues.start = 'The start time must be in the future.';
  if (!end) issues.end = 'Enter an end time.';
  else if (Number.isNaN(to)) issues.end = 'Enter a valid end time.';
  else if (!Number.isNaN(from)) {
    const minutes = (to - from) / 60000;
    if (to <= from) issues.end = 'The end time must be after the start time.';
    else if (minutes < MIN_MINUTES) issues.end = `The appointment must last at least ${MIN_MINUTES} minutes.`;
    else if (minutes > MAX_MINUTES) issues.end = `The appointment can last at most ${MAX_MINUTES} minutes.`;
  }
  return issues;
}
/** Latest change first; ties keep a stable id order. */
export const sortAppointments = <T extends Appointment>(items: T[]) => [...items].sort((a, b) => b.updated_at.localeCompare(a.updated_at) || b.id.localeCompare(a.id));
/** The server only notifies the other party, so an unread appointment notice means the other side changed it. */
export const changedByOtherParty = (notices: CareNotification[]) => new Set(notices.filter(n => n.kind === 'appointment_change' && !n.read_at && 'appointment_id' in n.reference).map(n => (n.reference as { appointment_id: string }).appointment_id));
export const appointmentStateLabels: Record<Appointment['state'], string> = { requested: 'Requested', proposed: 'Time proposed', confirmed: 'Confirmed', completed: 'Completed', rejected: 'Rejected', cancelled: 'Cancelled' };
