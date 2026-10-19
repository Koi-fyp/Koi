import type { Answer } from './patient-types';
import type { Question } from './types';
/** Shared structural validation; only the server decides whether answers can be saved/submitted. */
export function answerIssues(questions: Question[], answers: Answer[], final = false): string[] {
  const issues: string[] = [], seen = new Set<string>();
  for (const answer of answers) {
    const q = questions.find(item => item.id === answer.question_id);
    if (!q || seen.has(answer.question_id) || q.type !== answer.type) { issues.push('Unknown or duplicate answer.'); continue; }
    seen.add(answer.question_id);
    const v = answer.value;
    if (q.type === 'yes_no') { if (typeof v !== 'boolean') issues.push('Choose yes or no.'); }
    else if (q.type === 'short_text') { if (typeof v !== 'string' || v.length > (q.max_length ?? 4000) || (final && q.required && !v.trim())) issues.push('Check your text answer.'); }
    else if (q.type === 'multi_choice' || q.type === 'image_multi_choice') {
      if (!Array.isArray(v) || new Set(v).size !== v.length || v.some(id => !q.options?.some(o => o.id === id)) || v.length > (q.max_selections ?? q.options!.length) || (v.length > 0 && v.length < (q.min_selections ?? 0)) || (final && q.required && v.length < Math.max(1, q.min_selections ?? 0))) issues.push('Check your selected options.');
    } else if (typeof v !== 'string' || !q.options?.some(o => o.id === v)) issues.push('Choose an available option.');
  }
  if (final && questions.some(q => q.required && !seen.has(q.id))) issues.push('Answer every required question.');
  return issues;
}
