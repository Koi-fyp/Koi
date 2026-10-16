'use client';

import { useEffect, useRef } from 'react';
import type { CrisisPath } from '@/lib/conversation/chatContract';
import { parseCrisisInterventionDisplay, type CrisisInterventionDisplay } from '@/lib/conversation/crisisContract';
import styles from './CompanionScene.module.css';

const paths: Array<{ value: CrisisPath; label: string }> = [
  { value: 'reached_out', label: 'I reached out for support' },
  { value: 'said_but_did_not', label: 'I said that, but did not reach out' },
  { value: 'misunderstanding', label: 'There was a misunderstanding' },
];

export default function CrisisHandoffDialog({ open, content, onChoose }: {
  open: boolean;
  content?: CrisisInterventionDisplay;
  onChoose: (path: CrisisPath) => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const previousFocus = useRef<HTMLElement | null>(null);
  const choiceMade = useRef(false);

  useEffect(() => {
    if (!open) { choiceMade.current = false; return; }
    previousFocus.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const dialog = dialogRef.current;
    const first = dialog?.querySelector<HTMLElement>('button');
    first?.focus();
    const trap = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); return; }
      if (event.key !== 'Tab' || !dialog) return;
      const controls = Array.from(dialog.querySelectorAll<HTMLElement>('button:not(:disabled)'));
      if (!controls.length) { event.preventDefault(); return; }
      const firstControl = controls[0], lastControl = controls[controls.length - 1];
      if (event.shiftKey && document.activeElement === firstControl) { event.preventDefault(); lastControl.focus(); }
      else if (!event.shiftKey && document.activeElement === lastControl) { event.preventDefault(); firstControl.focus(); }
    };
    document.addEventListener('keydown', trap, true);
    return () => { document.removeEventListener('keydown', trap, true); previousFocus.current?.focus(); };
  }, [open]);

  if (!open) return null;
  const safeContent = content ? parseCrisisInterventionDisplay(content) : null;
  const choose = (path: CrisisPath) => {
    if (choiceMade.current) return;
    choiceMade.current = true;
    onChoose(path);
  };
  return <div className={styles.crisisBackdrop}>
    <section ref={dialogRef} className={styles.crisisDialog} role="alertdialog" aria-modal="true" aria-labelledby="flow4-title" aria-describedby="flow4-description">
      <h2 id="flow4-title">Let’s check what support you need</h2>
      <p id="flow4-description">KOI has paused this conversation to check in with you. Choose the response that best fits.</p>
      {safeContent ? <div className={styles.crisisContent}>
        {safeContent.confidence === 'reduced' && <p role="status">Limited information</p>}
        {safeContent.items.map((item) => <article key={item.id}><h3>{item.title}</h3><p>{item.body}</p></article>)}
        {safeContent.helpline && <p>{safeContent.helpline.label}: {safeContent.helpline.number} <small>({safeContent.helpline.source})</small></p>}
        {safeContent.source === 'verified_fallback' && <p className={styles.crisisSource}>Verified support information</p>}
      </div> : <p className={styles.crisisUnavailable}>Support details are unavailable in this chat response.</p>}
      <div className={styles.crisisChoices} aria-label="Choose what happened">
        {paths.map(({ value, label }) => <button key={value} type="button" onClick={() => choose(value)}>{label}</button>)}
      </div>
    </section>
  </div>;
}
