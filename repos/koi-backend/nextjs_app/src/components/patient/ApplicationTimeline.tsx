import type { Connection } from '@/lib/platform/patient-types';

export const applicationSteps = ['Applied', 'Payment', 'Pending', 'Accepted'] as const;
/** Index of the step in progress; every earlier step is done. Accepted completes all steps. */
const progress: Partial<Record<Connection['state'], number>> = { requested: 1, awaiting_demo_payment: 1, pending_psychologist_review: 2, accepted: applicationSteps.length };
export function timelineStates(state: Connection['state']): ('done' | 'current' | 'upcoming')[] | null {
  const at = progress[state];
  if (at === undefined) return null;
  return applicationSteps.map((_, i) => i < at ? 'done' : i === at ? 'current' : 'upcoming');
}
export default function ApplicationTimeline({ state }: { state: Connection['state'] }) {
  const states = timelineStates(state);
  if (!states) return null;
  return <ol className="care-timeline" aria-label="Application progress">{applicationSteps.map((step, i) => <li key={step} data-state={states[i]} aria-current={states[i] === 'current' ? 'step' : undefined}>{states[i] === 'done' && <span aria-hidden="true">✓ </span>}{step}<span className="sr-only">{states[i] === 'done' ? ' (done)' : states[i] === 'current' ? ' (in progress)' : ' (upcoming)'}</span></li>)}</ol>;
}
