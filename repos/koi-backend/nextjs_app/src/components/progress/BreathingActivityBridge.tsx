'use client';
import { createContext, useCallback, useContext, useState, type ReactNode } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { auth } from '@/lib/firebase';
import { saveBreathingResult, type BreathingResult } from '@/lib/activities/breathingActivity';
const Context = createContext<((result: BreathingResult) => void) | undefined>(undefined);
export const useBreathingResultCallback = () => useContext(Context);
export default function BreathingActivityBridge({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const [notice, setNotice] = useState<{ owner: string; text: string } | null>(null);
  const receive = useCallback((result: BreathingResult) => {
    const owner = user?.uid; if (!owner || auth?.currentUser?.uid !== owner) return;
    void saveBreathingResult(owner, result).then(receipt => {
      if (auth?.currentUser?.uid !== owner) return;
      setNotice({ owner, text: receipt.outcome === 'awarded' ? 'Client-measured breathing activity saved. One puzzle piece earned.' : receipt.outcome === 'ineligible' ? 'Breathing was not eligible for a reward: completion, active duration and interruption requirements apply.' : 'Client-measured breathing activity saved; no additional daily piece issued.' });
    }).catch(() => { if (auth?.currentUser?.uid === owner) setNotice({ owner, text: 'Breathing completion could not be saved. No reward was confirmed.' }); });
  }, [user?.uid]);
  return <Context.Provider value={receive}>{notice?.owner === user?.uid && <p role="status" className="text-sm p-2">{notice?.text}</p>}{children}</Context.Provider>;
}
