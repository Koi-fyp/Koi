'use client';
import type { Answer } from '@/lib/platform/patient-types';
import type { Locale, Question } from '@/lib/platform/types';
import { illustrations } from '@/lib/platform/content';
export default function QuestionFields({ questions, answers, locale, disabled = false, onChange }: { questions: Question[]; answers: Answer[]; locale: Locale; disabled?: boolean; onChange?: (answers: Answer[]) => void }) {
  const update = (q: Question, value: Answer['value']) => onChange?.([...answers.filter(a => a.question_id !== q.id), { question_id: q.id, type: q.type, value }]);
  return <div className="professional-stack" dir={locale === 'ur' ? 'rtl' : 'ltr'} lang={locale}>{questions.map((q, index) => {
    const answer = answers.find(a => a.question_id === q.id);
    return <fieldset key={q.id} className="professional-question" disabled={disabled}><legend>{index + 1}. {q.prompt[locale]} {q.required && <span aria-label="required">*</span>}</legend>
      {q.type === 'short_text' ? <textarea className="neo-input" aria-label={q.prompt[locale]} maxLength={q.max_length ?? 4000} value={typeof answer?.value === 'string' ? answer.value : ''} rows={3} onChange={e => update(q, e.target.value)} />
        : q.type === 'yes_no' ? <div className="professional-row">{[true, false].map(value => <label key={String(value)}><input type="radio" name={q.id} checked={answer?.value === value} onChange={() => update(q, value)} /> {locale === 'ur' ? (value ? 'ہاں' : 'نہیں') : locale === 'ur-Latn' ? (value ? 'Haan' : 'Nahin') : value ? 'Yes' : 'No'}</label>)}</div>
          : <div className={q.type.startsWith('image_') ? 'professional-pictures' : 'professional-stack'}>{q.options?.map(o => {
            const multi = q.type.includes('multi_choice'), selected = multi ? Array.isArray(answer?.value) && answer.value.includes(o.id) : answer?.value === o.id;
            const asset = o.asset && illustrations.find(a => a.reference.asset_id === o.asset!.asset_id && a.reference.version === o.asset!.version && a.reference.sha256 === o.asset!.sha256);
            return <label key={o.id} className={asset ? 'professional-picture' : 'professional-row'}><input type={multi ? 'checkbox' : 'radio'} name={q.id} checked={selected} onChange={() => {
              if (!multi) update(q, o.id);
              else { const values = Array.isArray(answer?.value) ? answer.value : []; update(q, selected ? values.filter(v => v !== o.id) : [...values, o.id]); }
            }} />{asset && <img src={asset.web_path} alt={o.label[locale] ?? ''} />}<span>{o.label[locale]}</span></label>;
          })}</div>}
    </fieldset>;
  })}</div>;
}
