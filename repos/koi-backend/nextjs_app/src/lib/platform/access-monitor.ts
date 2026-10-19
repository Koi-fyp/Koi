'use client';
import { useEffect, useRef, useState } from 'react';
import type { User } from 'firebase/auth';
/** No content is cached. Disconnect/heartbeat expiry unmounts protected patient state. */
export function useAccessMonitor(uid: string, currentUser: () => User | null) {
  const user = useRef(currentUser); user.current = currentUser;
  const [state, setState] = useState({ ready: false, generation: 0 });
  useEffect(() => {
    let alive = true, attempt: AbortController | null = null, reconnect: ReturnType<typeof setTimeout> | undefined;
    const lock = () => { if (alive) setState(old => ({ ready: false, generation: old.generation + 1 })); };
    const connect = async () => {
      if (!alive) return;
      if (document.hidden || !navigator.onLine) { reconnect = setTimeout(connect, 1500); return; }
      attempt = new AbortController(); let last = Date.now();
      const watch = setInterval(() => { if (Date.now() - last > 7000) { lock(); attempt?.abort(); } }, 1000);
      try {
        if (user.current()?.uid !== uid) throw new Error('Session changed');
        const token = await user.current()!.getIdToken();
        if (!alive || user.current()?.uid !== uid) return;
        const response = await fetch('/api/v1/me/access-events', { headers: { Authorization: `Bearer ${token}` }, cache: 'no-store', credentials: 'omit', signal: attempt.signal });
        if (!response.ok || !response.body) throw new Error('Access unavailable');
        const reader = response.body.getReader(), decoder = new TextDecoder(); let pending = '';
        while (alive) {
          const { value, done } = await reader.read(); if (done) break;
          if (user.current()?.uid !== uid) throw new Error('Session changed');
          pending += decoder.decode(value, { stream: true });
          let end: number;
          while ((end = pending.indexOf('\n\n')) >= 0) {
            const event = pending.slice(0, end); pending = pending.slice(end + 2); last = Date.now();
            if (event.startsWith('event: authorization_changed')) setState(old => ({ ready: true, generation: old.generation + 1 }));
          }
        }
      } catch { /* A disconnected screen stays locked until a new authenticated event. */ }
      finally { clearInterval(watch); lock(); if (alive) reconnect = setTimeout(connect, 1500); }
    };
    const hide = () => { if (document.hidden || !navigator.onLine) { lock(); attempt?.abort(); } };
    window.addEventListener('offline', hide); document.addEventListener('visibilitychange', hide);
    void connect();
    return () => { alive = false; attempt?.abort(); clearTimeout(reconnect); window.removeEventListener('offline', hide); document.removeEventListener('visibilitychange', hide); };
  }, [uid]);
  return state;
}
