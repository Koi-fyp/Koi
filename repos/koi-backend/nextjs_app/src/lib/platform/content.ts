import manifest from './illustrations.json';
import type { Locale, ManualContent, Question, QuestionType } from './types';

export const illustrations = manifest.assets;
export const locales: Locale[] = ['en', 'ur', 'ur-Latn'];
export const localeNames = { en: 'English', ur: 'Urdu', 'ur-Latn': 'Roman Urdu' };
export const questionNames: Record<QuestionType, string> = {
  single_choice: 'Single choice', multi_choice: 'Multiple choice', yes_no: 'Yes / No',
  likert: 'Likert scale', short_text: 'Short text', image_single_choice: 'Picture: single choice', image_multi_choice: 'Picture: multiple choice',
};
const id = () => crypto.randomUUID();
export function newQuestion(type: QuestionType = 'short_text', active: Locale[] = ['en']): Question {
  const labels = () => Object.fromEntries(active.map(locale => [locale, '']));
  const q: Question = { id: id(), type, required: true, prompt: labels() };
  if (type === 'short_text') q.max_length = 1000;
  else if (type !== 'yes_no') {
    q.options = [0, 1].map(index => ({ id: id(), label: type.startsWith('image_')
      ? Object.fromEntries(active.map(locale => [locale, illustrations[index].accessibility_label[locale]])) : labels(),
      ...(type.startsWith('image_') ? { asset: { ...illustrations[index].reference } } : {}) }));
    if (type.includes('multi')) { q.min_selections = 1; q.max_selections = 2; }
  }
  return q;
}
export function emptyContent(): ManualContent {
  return { kind: 'custom_questionnaire', validation_status: 'not_validated', origin: 'manual', title: { en: '' }, locales: ['en'], questions: [newQuestion()] };
}
/** Semantic rules shared for helpful editor errors and rechecked after strict server schema validation. */
export function contentIssues(content: ManualContent): string[] {
  const issues: string[] = [];
  const checkText = (value: Partial<Record<Locale, string>>, where: string) => {
    if (content.locales.some(locale => !value[locale]?.trim())) issues.push(`${where}: add text in every selected language.`);
    if (Object.keys(value).some(locale => !content.locales.includes(locale as Locale))) issues.push(`${where}: remove text in unselected languages.`);
  };
  checkText(content.title, 'Title');
  const questionIds = new Set<string>();
  content.questions.forEach((q, i) => {
    const where = `Question ${i + 1}`;
    if (questionIds.has(q.id)) issues.push(`${where}: question IDs must be unique.`);
    questionIds.add(q.id); checkText(q.prompt, where);
    const optionIds = new Set<string>(), assetIds = new Set<string>();
    q.options?.forEach(option => {
      if (optionIds.has(option.id)) issues.push(`${where}: option IDs must be unique.`);
      optionIds.add(option.id); checkText(option.label, `${where} option`);
      if (q.type.startsWith('image_')) {
        const a = option.asset;
        if (!a || !illustrations.some(asset => asset.reference.asset_id === a.asset_id && asset.reference.version === a.version && asset.reference.sha256 === a.sha256)) issues.push(`${where}: select a bundled picture.`);
        if (a && assetIds.has(a.asset_id)) issues.push(`${where}: use different pictures for each option.`);
        if (a) assetIds.add(a.asset_id);
      }
    });
    if (q.type.includes('multi') && (q.min_selections! > q.max_selections! || q.max_selections! > (q.options?.length ?? 0))) issues.push(`${where}: selection bounds must fit the options.`);
  });
  return issues;
}
