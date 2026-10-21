import type { Answer } from './patient-types';
import type { Locale, Question } from './types';
import type { Evaluation, Job } from './professional-types';

export const SECTION_TITLES = ['Summary', 'Key observations', 'Themes', 'Points to clarify', 'Missing information', 'Limitations'] as const;
export type SectionTitle = typeof SECTION_TITLES[number];
export interface InterpretationSection { title: SectionTitle; paragraphs: string[]; items: string[] }
export interface ParsedInterpretation { structured: boolean; preface: string[]; sections: InterpretationSection[] }

const titlePattern = SECTION_TITLES.map(t => t.replace(/ /g, '\\s+')).join('|');
// "## Summary", "**Summary**", "Summary:", "SUMMARY" and "Summary: first sentence" are all headings.
// The title must end the line or be followed by a colon, so prose such as "Summary of findings" stays prose.
const heading = new RegExp(`^\\s*(?:#{1,6}\\s*)?(?:\\*\\*|__)?\\s*(${titlePattern})\\s*(?:\\*\\*|__)?\\s*(?::|$)\\s*(?:\\*\\*|__)?\\s*(.*)$`, 'i');
const bullet = /^\s*(?:[-*•]|\d+[.)])\s+(.*)$/;
const canonical = (raw: string) => SECTION_TITLES.find(t => t.toLowerCase() === raw.replace(/\s+/g, ' ').toLowerCase())!;

/**
 * Splits AI interpretation text into the known sections when it carries at least two of their headings.
 * Anything else stays unstructured so the caller shows the raw text unchanged.
 */
export function parseInterpretation(text: string | null | undefined): ParsedInterpretation {
  const lines = (text ?? '').replace(/\r\n?/g, '\n').split('\n');
  const found = lines.filter(line => heading.test(line)).length;
  if (found < 2) return { structured: false, preface: [], sections: [] };
  const preface: string[] = [], sections: InterpretationSection[] = [];
  let current: InterpretationSection | null = null;
  for (const line of lines) {
    const match = line.match(heading);
    if (match) {
      const title = canonical(match[1]);
      current = sections.find(s => s.title === title) ?? null;
      if (!current) { current = { title, paragraphs: [], items: [] }; sections.push(current); }
      if (match[2].trim()) current.paragraphs.push(match[2].trim());
      continue;
    }
    if (!line.trim()) continue;
    const item = line.match(bullet);
    if (!current) preface.push(line.trim());
    else if (item) current.items.push(item[1].trim());
    else current.paragraphs.push(line.trim());
  }
  return { structured: true, preface, sections: SECTION_TITLES.map(t => sections.find(s => s.title === t)).filter((s): s is InterpretationSection => !!s) };
}

const hasValue = (a: Answer) => typeof a.value === 'boolean' || (Array.isArray(a.value) ? a.value.length > 0 : String(a.value).trim().length > 0);
/** Only what the patient actually submitted: option ids become their labels; nothing is paraphrased. */
export function answerText(question: Question | undefined, answer: Answer | undefined, locale: Locale): string | null {
  if (!answer || !hasValue(answer)) return null;
  if (typeof answer.value === 'boolean') return answer.value ? 'Yes' : 'No';
  const label = (id: string) => { const option = question?.options?.find(o => o.id === id); return option ? option.label[locale] ?? Object.values(option.label)[0] ?? id : id; };
  if (Array.isArray(answer.value)) return answer.value.map(label).join(', ');
  return question?.options?.some(o => o.id === answer.value) ? label(answer.value) : answer.value;
}
/** Answers cited by at least one evidence reference, out of the answers actually given. */
export function evidenceCoverage(evaluation: Pick<Evaluation, 'evidence'>, answers: Answer[]) {
  const given = answers.filter(hasValue), ids = new Set(given.map(a => a.question_id));
  const cited = new Set(evaluation.evidence.map(e => e.question_id).filter(id => ids.has(id)));
  return { cited: cited.size, total: given.length };
}
const failureReasons: Record<NonNullable<Job['failure_code']>, string> = { provider_unavailable: 'AI service unavailable', invalid_output: 'unusable AI output', lease_expired: 'processing timed out', retry_exhausted: 'retries exhausted' };
export function evaluationStateText(job: Pick<Job, 'state' | 'failure_code'>): { label: string; detail: string } {
  if (job.state === 'queued') return { label: 'Evaluation queued', detail: 'The submission is waiting for AI processing. Use Refresh to check for an update.' };
  if (job.state === 'claimed') return { label: 'Evaluation in progress', detail: 'Processing has started. An interpretation may not be available yet.' };
  if (job.state === 'failed') return { label: `Evaluation unavailable (${job.failure_code ? failureReasons[job.failure_code] ?? 'processing failed' : 'processing failed'}): you can review the original answers manually`, detail: 'No completed interpretation is implied.' };
  if (job.state === 'completed') return { label: 'Evaluation completed', detail: 'Inspect the interpretation and the cited answers before recording your own review.' };
  return { label: 'Evaluation status unavailable', detail: 'You can review the original answers manually.' };
}
