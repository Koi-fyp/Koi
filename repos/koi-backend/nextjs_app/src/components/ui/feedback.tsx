'use client';
import { createContext, useCallback, useContext, useEffect, useId, useMemo, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import NeoButton from './NeoButton';

export interface ConfirmOptions { title: string; description?: string; confirmLabel?: string; cancelLabel?: string; tone?: 'default' | 'danger' }
type ConfirmFn = (options: ConfirmOptions) => Promise<boolean>;
const ConfirmContext = createContext<ConfirmFn | null>(null);
// Without a mounted provider nobody can be asked, so nothing consequential may proceed.
const refuse: ConfirmFn = async () => false;
export const useConfirm = (): ConfirmFn => useContext(ConfirmContext) ?? refuse;

const focusable = 'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
function ConfirmDialog({ options, onClose }: { options: ConfirmOptions; onClose: (result: boolean) => void }) {
  const id = useId(), box = useRef<HTMLDivElement>(null), cancel = useRef<HTMLButtonElement>(null);
  useEffect(() => { cancel.current?.focus(); }, []);
  const keys = (event: KeyboardEvent) => {
    if (event.key === 'Escape') { event.preventDefault(); onClose(false); return; }
    if (event.key !== 'Tab' || !box.current) return;
    const items = Array.from(box.current.querySelectorAll<HTMLElement>(focusable));
    if (!items.length) return;
    const first = items[0], last = items[items.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  };
  return <div className="koi-dialog-backdrop" onMouseDown={event => { if (event.target === event.currentTarget) onClose(false); }}>
    <div ref={box} role="alertdialog" aria-modal="true" aria-labelledby={`${id}-title`} aria-describedby={options.description ? `${id}-description` : undefined} className="koi-dialog" onKeyDown={keys}>
      <h2 id={`${id}-title`}>{options.title}</h2>
      {options.description && <p id={`${id}-description`}>{options.description}</p>}
      <div className="koi-dialog-actions">
        <button ref={cancel} type="button" className="neo-btn-ghost" onClick={() => onClose(false)}>{options.cancelLabel ?? 'Cancel'}</button>
        <NeoButton type="button" variant={options.tone === 'danger' ? 'danger' : 'primary'} onClick={() => onClose(true)}>{options.confirmLabel ?? 'Confirm'}</NeoButton>
      </div>
    </div>
  </div>;
}

/** Themed replacement for window.confirm: one dialog at a time, resolves false on Esc, Cancel or backdrop. */
export function ConfirmProvider({ children }: { children: ReactNode }) {
  const [current, setCurrent] = useState<{ options: ConfirmOptions; resolve: (value: boolean) => void; opener: HTMLElement | null } | null>(null);
  const open = useRef(current); open.current = current;
  const confirm = useCallback<ConfirmFn>(options => new Promise<boolean>(resolve => {
    open.current?.resolve(false);
    setCurrent({ options, resolve, opener: document.activeElement as HTMLElement | null });
  }), []);
  useEffect(() => () => { open.current?.resolve(false); }, []);
  const close = (result: boolean) => {
    if (!current) return;
    current.resolve(result); setCurrent(null);
    const opener = current.opener;
    requestAnimationFrame(() => { if (opener?.isConnected) opener.focus(); });
  };
  return <ConfirmContext.Provider value={confirm}>{children}{current && <ConfirmDialog key={current.options.title} options={current.options} onClose={close} />}</ConfirmContext.Provider>;
}

export type SnackbarVariant = 'success' | 'error';
export interface Snackbar { success(text: string): void; error(text: string): void }
const silent: Snackbar = { success() {}, error() {} };
const SnackbarContext = createContext<Snackbar | null>(null);
export const useSnackbar = (): Snackbar => useContext(SnackbarContext) ?? silent;
export const SNACKBAR_MS = 4000;

/** Short, generic outcome messages; callers must never pass message or answer text. */
export function SnackbarProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<{ id: number; text: string; variant: SnackbarVariant }[]>([]);
  const next = useRef(0), timers = useRef(new Map<number, ReturnType<typeof setTimeout>>());
  const dismiss = useCallback((id: number) => {
    const timer = timers.current.get(id); if (timer) clearTimeout(timer); timers.current.delete(id);
    setItems(old => old.filter(item => item.id !== id));
  }, []);
  const push = useCallback((text: string, variant: SnackbarVariant) => {
    const id = ++next.current;
    setItems(old => [...old.slice(-2), { id, text, variant }]);
    timers.current.set(id, setTimeout(() => dismiss(id), SNACKBAR_MS));
  }, [dismiss]);
  useEffect(() => () => { timers.current.forEach(clearTimeout); timers.current.clear(); }, []);
  const api = useMemo<Snackbar>(() => ({ success: text => push(text, 'success'), error: text => push(text, 'error') }), [push]);
  return <SnackbarContext.Provider value={api}>{children}
    <div className="koi-snackbar-region" aria-live="polite">{items.map(item => <div key={item.id} className={`koi-snackbar koi-snackbar--${item.variant}`} data-variant={item.variant}>
      <span>{item.text}</span><button type="button" className="koi-snackbar-dismiss" aria-label="Dismiss notification" onClick={() => dismiss(item.id)}>×</button>
    </div>)}</div>
  </SnackbarContext.Provider>;
}

export function FeedbackProviders({ children }: { children: ReactNode }) {
  return <SnackbarProvider><ConfirmProvider>{children}</ConfirmProvider></SnackbarProvider>;
}

export const ACTION_FAILED = 'Action not completed. Check the message on this page.';
/**
 * Asks first, runs the action through the caller's busy/error wrapper, then reports the outcome.
 * The caller's wrapper keeps its own inline error handling.
 */
export function useConfirmedAction() {
  const confirm = useConfirm(), snackbar = useSnackbar();
  return useCallback(async (options: ConfirmOptions & { success: string }, run: (fn: () => Promise<void>) => Promise<unknown> | void, action: () => Promise<void>) => {
    if (!(await confirm(options))) return false;
    let started = false, done = false;
    await run(async () => { started = true; await action(); done = true; });
    if (done) snackbar.success(options.success); else if (started) snackbar.error(ACTION_FAILED);
    return done;
  }, [confirm, snackbar]);
}
