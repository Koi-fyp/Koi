'use client';
import { useEffect } from 'react';

/** Reveal results after React has committed them, without animated scrolling. */
export function revealCareElement(target: HTMLElement | null) {
  if (!target || !target.isConnected || target.closest('[hidden]')) return;
  target.focus({ preventScroll: true });
  target.scrollIntoView?.({ behavior: 'auto', block: 'start', inline: 'nearest' });
}

export function useCareReveal(id: string, selection: unknown, active = true) {
  useEffect(() => {
    if (!active || selection === null || selection === undefined || selection === false) return;
    const frame = requestAnimationFrame(() => {
      const target = document.getElementById(id), focused = document.activeElement as HTMLElement | null;
      if (focused !== target && target?.contains(focused) && focused?.hasAttribute('data-care-result-focus') && !focused.closest('[hidden]')) return;
      // A newly opened result takes precedence over its containing view heading.
      if (id === 'workspace-heading' && focused?.hasAttribute('data-care-result-focus') && !focused.closest('[hidden]')) return;
      if (id !== 'workspace-heading') target?.setAttribute('data-care-result-focus', '');
      revealCareElement(target);
    });
    return () => cancelAnimationFrame(frame);
  }, [id, selection, active]);
}
