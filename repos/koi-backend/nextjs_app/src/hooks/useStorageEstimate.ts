'use client';
import { useEffect, useState } from 'react';

const unavailable = { percent: null as number | null, label: 'Browser storage estimate unavailable.' };
/** Origin-wide browser estimate, never a per-user KOI balance or fixed quota. */
export function useStorageEstimate() {
  const [estimate, setEstimate] = useState(unavailable);
  useEffect(() => {
    let active = true;
    async function read() {
      try {
        if (!navigator.storage?.estimate) return;
        const { usage, quota } = await navigator.storage.estimate();
        if (!active || typeof usage !== 'number' || typeof quota !== 'number'
          || !Number.isFinite(usage) || !Number.isFinite(quota) || usage < 0 || quota <= 0 || usage > quota) return;
        const mb = (bytes: number) => `${(bytes / 1048576).toFixed(2)} MB`;
        setEstimate({ percent: Math.round(usage / quota * 100),
          label: `Approximately ${mb(usage)} of ${mb(quota)} browser quota used across this origin; includes caches and other accounts, not just KOI records.` });
      } catch { /* Unsupported/denied estimates remain unavailable. */ }
    }
    void read();
    return () => { active = false; };
  }, []);
  return estimate;
}
