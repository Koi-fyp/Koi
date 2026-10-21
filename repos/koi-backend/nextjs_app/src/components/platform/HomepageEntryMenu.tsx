'use client';

import { useEffect, useId, useRef, useState } from 'react';
import styles from './HomepageEntryMenu.module.css';

const choices = [
  { title: 'Anonymous User', description: 'Chat with your AI companion', action: 'Continue Anonymously', icon: 'chat' },
  { title: 'General User', description: 'Find psychologists and explore care', action: 'Continue as General User', icon: 'search', entry: 'general' },
  { title: 'Patient', description: 'Questionnaires, psychologist and appointments', action: 'Continue as Patient', icon: 'heart', entry: 'patient' },
  { title: 'Psychologist', description: 'Manage practice, patients and questionnaires', action: 'Continue as Psychologist', icon: 'practice', entry: 'psychologist' },
];

function EntryIcon({ kind }: { kind: string }) {
  return <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    {kind === 'chat' ? <path d="M21 11a8 8 0 0 1-8 8H6l-4 3V11a9 9 0 0 1 19 0Z" /> : kind === 'search' ? <><circle cx="10" cy="10" r="7" /><path d="m15 15 6 6" /></> : kind === 'heart' ? <path d="M12 21 3 12C-3 4 7-1 12 6c5-7 15-2 9 6Z" /> : <><rect x="3" y="6" width="18" height="15" rx="3" /><path d="M8 6V3h8v3m-4 5v6m-3-3h6" /></>}
  </svg>;
}

/** Public intent selector. Intents never grant account capabilities. */
export default function HomepageEntryMenu({ onAnonymous, busy = false }: { onAnonymous: () => void; busy?: boolean }) {
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null), panel = useRef<HTMLDivElement>(null);
  const id = useId();
  const close = () => { setOpen(false); trigger.current?.focus({ preventScroll: true }); };
  useEffect(() => {
    if (!open) return;
    panel.current?.querySelector<HTMLElement>('[data-entry]:not(:disabled)')?.focus({ preventScroll: true });
    const outside = (event: PointerEvent) => {
      if (!panel.current?.contains(event.target as Node) && !trigger.current?.contains(event.target as Node)) {
        // Keep the ensuing pointer default from stealing the restored focus.
        event.preventDefault(); close();
      }
    };
    const keyboard = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); close(); }
      if (event.key === 'Tab' && panel.current) {
        const controls = [...panel.current.querySelectorAll<HTMLElement>('a[href],button:not(:disabled)')];
        const first = controls[0], last = controls[controls.length - 1];
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
      }
    };
    document.addEventListener('pointerdown', outside);
    document.addEventListener('keydown', keyboard);
    return () => { document.removeEventListener('pointerdown', outside); document.removeEventListener('keydown', keyboard); };
  }, [open]);
  return <div className={styles.root}>
    <button ref={trigger} type="button" className={`neo-btn-ghost ${styles.trigger}`} aria-expanded={open} aria-controls={id} aria-haspopup="dialog" onClick={() => open ? close() : setOpen(true)}>Explore KOI <span aria-hidden="true">▾</span></button>
    {open && <div ref={panel} id={id} role="dialog" aria-label="Choose your KOI experience" className={styles.panel}>
      <div className={styles.heading}><h2>Choose your experience</h2><button type="button" onClick={close} aria-label="Close entry menu" className={styles.close}>×</button></div>
      <div className={styles.grid}>{choices.map(choice => {
        const contents = <><span className={styles.title}><EntryIcon kind={choice.icon} />{choice.title}</span><span className={styles.description}>{choice.description}</span><span className={styles.action}>{choice.action} <span aria-hidden="true">→</span></span></>;
        const props = { className: styles.card, 'data-entry': true, 'aria-label': choice.action };
        return choice.entry ? <a key={choice.title} {...props} href={`/account?entry=${choice.entry}`} onClick={close}>{contents}</a> : <button key={choice.title} {...props} type="button" disabled={busy} onClick={() => { close(); onAnonymous(); }}>{contents}</button>;
      })}</div>
    </div>}
  </div>;
}
