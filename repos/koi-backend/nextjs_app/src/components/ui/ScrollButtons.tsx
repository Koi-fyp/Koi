'use client';
import { useEffect, useState } from 'react';

export const TOP_AFTER = 300, BOTTOM_REMAINING = 400;
/** Each button only appears when it would move the reader somewhere useful. */
export function scrollButtonState(scrollY: number, viewport: number, scrollHeight: number) {
  return { top: scrollY > TOP_AFTER, bottom: scrollHeight - (scrollY + viewport) > BOTTOM_REMAINING };
}
const behavior = (): ScrollBehavior => typeof window.matchMedia === 'function' && window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth';

export default function ScrollButtons() {
  const [state, setState] = useState({ top: false, bottom: false });
  useEffect(() => {
    let frame = 0;
    const measure = () => {
      frame = 0;
      const next = scrollButtonState(window.scrollY, window.innerHeight, document.documentElement.scrollHeight);
      setState(old => old.top === next.top && old.bottom === next.bottom ? old : next);
    };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(measure); };
    measure();
    window.addEventListener('scroll', schedule, { passive: true }); window.addEventListener('resize', schedule);
    const observer = typeof ResizeObserver === 'function' ? new ResizeObserver(schedule) : null; observer?.observe(document.body);
    return () => { if (frame) cancelAnimationFrame(frame); window.removeEventListener('scroll', schedule); window.removeEventListener('resize', schedule); observer?.disconnect(); };
  }, []);
  if (!state.top && !state.bottom) return null;
  return <div className="koi-scroll-buttons">
    {state.top && <button type="button" className="koi-scroll-button" aria-label="Back to top" title="Back to top" onClick={() => window.scrollTo({ top: 0, behavior: behavior() })}><span aria-hidden="true">↑</span></button>}
    {state.bottom && <button type="button" className="koi-scroll-button" aria-label="Scroll to bottom" title="Scroll to bottom" onClick={() => window.scrollTo({ top: document.documentElement.scrollHeight, behavior: behavior() })}><span aria-hidden="true">↓</span></button>}
  </div>;
}
