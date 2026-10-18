'use client';
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';

export type InputMode = 'text' | 'audio' | 'video-text' | 'video-audio';
export const INPUT_MODES: ReadonlyArray<{ id: InputMode; label: string; hint: string }> = [
  { id: 'text', label: 'Text', hint: 'Type your messages' },
  { id: 'audio', label: 'Audio', hint: 'Talk with your microphone' },
  { id: 'video-text', label: 'Video + Text', hint: 'Camera self-view, type messages' },
  { id: 'video-audio', label: 'Video + Audio', hint: 'Camera self-view, talk with your microphone' },
];
/** The mic records voice turns; the camera is a local self-view only and never leaves the device. */
export const modeUsesMic = (mode: InputMode) => mode === 'audio' || mode === 'video-audio';
export const modeUsesCamera = (mode: InputMode) => mode === 'video-text' || mode === 'video-audio';
export const modeLabel = (mode: InputMode) => INPUT_MODES.find((item) => item.id === mode)?.label ?? 'Text';

const STORAGE_KEY = 'koi_input_mode';
const isMode = (value: unknown): value is InputMode => INPUT_MODES.some((item) => item.id === value);
function readStoredMode(): InputMode {
  try { const value = globalThis.localStorage?.getItem(STORAGE_KEY); return isMode(value) ? value : 'text'; } catch { return 'text'; }
}

type InputModeValue = { mode: InputMode; setMode: (mode: InputMode) => void };
const Context = createContext<InputModeValue | null>(null);

/** Device-level choice (a UI preference, not account data); defaults to Text and survives reloads. */
export function InputModeProvider({ children }: { children: ReactNode }) {
  const [mode, setModeState] = useState<InputMode>('text');
  useEffect(() => { setModeState(readStoredMode()); }, []);
  const setMode = useCallback((next: InputMode) => {
    if (!isMode(next)) return;
    setModeState(next);
    try { globalThis.localStorage?.setItem(STORAGE_KEY, next); } catch { /* The choice still applies to this page. */ }
  }, []);
  return <Context.Provider value={{ mode, setMode }}>{children}</Context.Provider>;
}

/** Outside a provider (isolated tests, previews) the mode is local state that starts at Text. */
export function useInputMode(): InputModeValue {
  const shared = useContext(Context);
  const [mode, setMode] = useState<InputMode>('text');
  return shared ?? { mode, setMode };
}
