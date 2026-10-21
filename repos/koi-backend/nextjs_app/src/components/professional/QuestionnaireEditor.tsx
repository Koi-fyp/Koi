'use client';
import NeoButton from '@/components/ui/NeoButton';
import NeoInput from '@/components/ui/NeoInput';
import { useConfirm } from '@/components/ui/feedback';
import { illustrations, locales, localeNames, newQuestion, questionNames } from '@/lib/platform/content';
import type { Locale, LocalizedText, ManualContent, Question, QuestionType } from '@/lib/platform/types';

function TranslationFields({ label, value, active, onChange }: { label: string; value: LocalizedText; active: Locale[]; onChange: (value: LocalizedText) => void }) {
  return <div className="professional-grid">{active.map(locale => <NeoInput key={locale} label={`${label} · ${localeNames[locale]}`} aria-label={`${label} · ${localeNames[locale]}`} value={value[locale] ?? ''} maxLength={4000} lang={locale === 'ur-Latn' ? 'ur-Latn' : locale} dir={locale === 'ur' ? 'rtl' : 'ltr'} onChange={event => onChange({ ...value, [locale]: event.target.value })} />)}</div>;
}
export default function QuestionnaireEditor({ content, onChange, disabled }: { content: ManualContent; onChange: (content: ManualContent) => void; disabled: boolean }) {
  const confirm = useConfirm();
  const update = (index: number, q: Question) => onChange({ ...content, questions: content.questions.map((old, i) => i === index ? q : old) });
  const languages = async (locale: Locale, enabled: boolean) => {
    const active = enabled ? locales.filter(l => content.locales.includes(l) || l === locale) : content.locales.filter(l => l !== locale);
    if (!active.length || (!enabled && !(await confirm({ title: `Remove ${localeNames[locale]} text?`, description: `All ${localeNames[locale]} title, question and option text is removed from this unsaved draft.`, confirmLabel: 'Remove language', tone: 'danger' })))) return;
    const localized = (value: LocalizedText) => Object.fromEntries(active.map(l => [l, value[l] ?? '']));
    onChange({ ...content, locales: active, title: localized(content.title), questions: content.questions.map(q => ({ ...q, prompt: localized(q.prompt), ...(q.options ? { options: q.options.map(o => ({ ...o, label: localized(o.label) })) } : {}) })) });
  };
  return <fieldset disabled={disabled} className="professional-stack" aria-label="Manual questionnaire editor">
    <legend className="sr-only">Questionnaire content</legend>
    <h3>Languages and questionnaire title</h3><div role="group" className="professional-row" aria-label="Questionnaire languages">{locales.map(locale => <label key={locale} className="professional-row"><input type="checkbox" checked={content.locales.includes(locale)} onChange={event => void languages(locale, event.target.checked)} />{localeNames[locale]}</label>)}</div>
    <TranslationFields label="Title" value={content.title} active={content.locales} onChange={title => onChange({ ...content, title })} />
    {content.questions.map((q, index) => <section className="professional-question" key={q.id} aria-label={`Question ${index + 1}`}>
      <div className="professional-row professional-between"><h3>Question {index + 1}</h3><div className="professional-row">
        <NeoButton type="button" variant="ghost" className="neo-btn-sm" aria-label={`Move question ${index + 1} up`} disabled={index === 0} onClick={() => { const questions = [...content.questions]; [questions[index - 1], questions[index]] = [questions[index], questions[index - 1]]; onChange({ ...content, questions }); }}>↑</NeoButton>
        <NeoButton type="button" variant="ghost" className="neo-btn-sm" aria-label={`Move question ${index + 1} down`} disabled={index === content.questions.length - 1} onClick={() => { const questions = [...content.questions]; [questions[index + 1], questions[index]] = [questions[index], questions[index + 1]]; onChange({ ...content, questions }); }}>↓</NeoButton>
        <NeoButton type="button" variant="ghost" className="neo-btn-sm" disabled={content.questions.length === 1} onClick={async () => { if (await confirm({ title: `Remove question ${index + 1}?`, description: 'The question and its options are removed from this draft. Unsaved until you save the draft.', confirmLabel: 'Remove question', tone: 'danger' })) onChange({ ...content, questions: content.questions.filter(item => item.id !== q.id) }); }}>Remove question {index + 1}</NeoButton>
      </div></div>
      <div className="professional-row"><label className="professional-label">Question {index + 1} type<select className="neo-input" value={q.type} onChange={event => update(index, { ...newQuestion(event.target.value as QuestionType, content.locales), id: q.id, prompt: q.prompt, required: q.required })}>{Object.entries(questionNames).map(([type, name]) => <option value={type} key={type}>{name}</option>)}</select></label>
        <label className="professional-row"><input type="checkbox" checked={q.required} onChange={event => update(index, { ...q, required: event.target.checked })} />Required question {index + 1}</label>
      </div>
      <TranslationFields label={`Question ${index + 1}`} value={q.prompt} active={content.locales} onChange={prompt => update(index, { ...q, prompt })} />
      {q.type === 'short_text' && <NeoInput type="number" label={`Question ${index + 1} character limit`} aria-label={`Question ${index + 1} character limit`} min={1} max={4000} value={q.max_length} onChange={event => update(index, { ...q, max_length: Number(event.target.value) })} />}
      {q.type === 'yes_no' && <p className="professional-muted">Answers: Yes / No. Labels follow the questionnaire language.</p>}
      {q.options?.map((option, optionIndex) => <div className="professional-stack" key={option.id}>
        <TranslationFields label={`Question ${index + 1} option ${optionIndex + 1}`} value={option.label} active={content.locales} onChange={label => update(index, { ...q, options: q.options!.map((o, i) => i === optionIndex ? { ...o, label } : o) })} />
        {q.type.startsWith('image_') && <div className="professional-pictures" role="group" aria-label={`Question ${index + 1} option ${optionIndex + 1} picture`}>{illustrations.map(asset => <button type="button" key={asset.reference.asset_id} className="professional-picture" aria-pressed={option.asset?.asset_id === asset.reference.asset_id} onClick={() => update(index, { ...q, options: q.options!.map((o, i) => i === optionIndex ? { ...o, asset: { ...asset.reference }, label: Object.fromEntries(content.locales.map(locale => [locale, asset.accessibility_label[locale]])) } : o) })}>
          <img src={asset.web_path} alt={asset.accessibility_label.en} />{asset.accessibility_label.en}
        </button>)}</div>}
        <NeoButton type="button" variant="ghost" className="neo-btn-sm" disabled={q.options!.length <= 2} onClick={() => { const options = q.options!.filter((_, i) => i !== optionIndex); update(index, { ...q, options, ...(q.type.includes('multi') ? { min_selections: Math.min(q.min_selections!, options.length), max_selections: Math.min(q.max_selections!, options.length) } : {}) }); }}>Remove option {optionIndex + 1}</NeoButton>
      </div>)}
      {q.options && <NeoButton type="button" variant="ghost" className="neo-btn-sm" disabled={q.options.length >= (q.type.startsWith('image_') ? illustrations.length : q.type === 'likert' ? 11 : 20)} onClick={() => {
        const asset = illustrations.find(a => !q.options!.some(o => o.asset?.asset_id === a.reference.asset_id));
        update(index, { ...q, options: [...q.options!, { id: crypto.randomUUID(), label: Object.fromEntries(content.locales.map(locale => [locale, q.type.startsWith('image_') ? asset!.accessibility_label[locale] : ''])), ...(q.type.startsWith('image_') ? { asset: { ...asset!.reference } } : {}) }] });
      }}>Add option to question {index + 1}</NeoButton>}
      {q.type.includes('multi') && <div className="professional-grid">
        <NeoInput type="number" label={`Question ${index + 1} minimum selections`} aria-label={`Question ${index + 1} minimum selections`} value={q.min_selections} min={0} max={q.options!.length} onChange={event => update(index, { ...q, min_selections: Number(event.target.value) })} />
        <NeoInput type="number" label={`Question ${index + 1} maximum selections`} aria-label={`Question ${index + 1} maximum selections`} value={q.max_selections} min={1} max={q.options!.length} onChange={event => update(index, { ...q, max_selections: Number(event.target.value) })} />
      </div>}
    </section>)}
    <NeoButton type="button" variant="secondary" disabled={content.questions.length >= 200} onClick={() => onChange({ ...content, questions: [...content.questions, newQuestion('short_text', content.locales)] })}>Add question</NeoButton>
  </fieldset>;
}
