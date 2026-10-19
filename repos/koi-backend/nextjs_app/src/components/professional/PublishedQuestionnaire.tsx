'use client';
import { useState } from 'react';
import NeoCard from '@/components/ui/NeoCard';
import { illustrations, localeNames, questionNames } from '@/lib/platform/content';
import type { Locale, VersionDTO } from '@/lib/platform/types';

export default function PublishedQuestionnaire({ version }: { version: VersionDTO }) {
  const [selected, setSelected] = useState<Locale>(version.content.locales[0]);
  const locale = version.content.locales.includes(selected) ? selected : version.content.locales[0];
  return <NeoCard className="professional-card" role="region" aria-label="Published questionnaire">
    <div className="professional-row professional-between"><h2>Published version</h2><span className="professional-badge">Immutable · Revision {version.source_revision}</span></div>
    <p className="professional-muted">This snapshot stays unchanged when you edit the draft. Custom questionnaire · Not validated.</p>
    <label className="professional-label">Preview language<select className="neo-input" value={locale} onChange={event => setSelected(event.target.value as Locale)}>{version.content.locales.map(l => <option value={l} key={l}>{localeNames[l]}</option>)}</select></label>
    <div dir={locale === 'ur' ? 'rtl' : 'ltr'} lang={locale} className="professional-stack"><h3>{version.content.title[locale]}</h3>
      {version.content.questions.map((question, index) => <section className="professional-question" key={question.id}>
        <p><strong>{index + 1}. {question.prompt[locale]}</strong>{question.required ? ' *' : ''}</p><span className="professional-muted">{questionNames[question.type]}</span>
        {question.type === 'yes_no' && <p>{locale === 'ur' ? 'ہاں / نہیں' : locale === 'ur-Latn' ? 'Haan / Nahin' : 'Yes / No'}</p>}
        {question.type === 'short_text' && <p className="professional-muted">Text response · maximum {question.max_length} characters</p>}
        {question.options && <ul className="professional-stack">{question.options.map(option => {
          const asset = illustrations.find(item => item.reference.asset_id === option.asset?.asset_id && item.reference.version === option.asset.version && item.reference.sha256 === option.asset.sha256);
          return <li key={option.id} className="professional-row">{asset && <img className="professional-preview-image" src={asset.web_path} alt={asset.accessibility_label[locale]} />}<span>{option.label[locale]}</span></li>;
        })}</ul>}
      </section>)}
    </div>
    <details><summary>Version details</summary><p className="professional-muted">Published {new Date(version.published_at).toLocaleString()}</p><p className="professional-muted">Version: {version.id}</p><p className="professional-muted">Content SHA-256: {version.content_sha256}</p></details>
    <a className="professional-link" href={`/professional?version=${encodeURIComponent(version.id)}`}>Open this published version later</a>
  </NeoCard>;
}
