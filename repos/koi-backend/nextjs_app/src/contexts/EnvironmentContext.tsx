'use client';
import { createContext, useContext, useEffect, useState, useSyncExternalStore, type ReactNode } from 'react';
import type { ConversationSession } from '@/lib/conversation/ConversationSession';
import { EnvironmentState } from '@/lib/environment/environmentState';
import { environmentPalette } from '@/lib/environment/palette';

const Context = createContext<EnvironmentState | null>(null);
type Observers = Pick<ReturnType<EnvironmentState['bind']>, 'breathing' | 'dialog'>;
const ObservationContext = createContext<Observers | null>(null);
const neutral = new EnvironmentState();
export function EnvironmentProvider({ children }: { children: ReactNode }) {
  const [state] = useState(() => new EnvironmentState());
  return <Context.Provider value={state}>{children}</Context.Provider>;
}
export function EnvironmentSession({ session, children }: { session: ConversationSession; children: ReactNode }) {
  const state = useContext(Context);
  const [observers, setObservers] = useState<Observers | null>(null);
  useEffect(() => {
    if (!state) return;
    const binding = state.bind(session); setObservers(binding);
    return binding.dispose;
  }, [state, session]);
  return <ObservationContext.Provider value={observers}>{children}</ObservationContext.Provider>;
}
export const useEnvironmentObservers = () => useContext(ObservationContext);
export function useEnvironment(surface: 'call' | 'chat') {
  const state = useContext(Context) ?? neutral;
  const mood = useSyncExternalStore(state.subscribe, state.getSnapshot, () => 'neutral' as const);
  return { mood, backgroundColor: environmentPalette[surface][mood] };
}
