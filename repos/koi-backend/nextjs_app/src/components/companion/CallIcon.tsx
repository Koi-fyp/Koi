import type { ReactNode } from 'react';
type IconName = 'back' | 'settings' | 'microphone' | 'camera' | 'text' | 'end' | 'close';
const paths: Record<IconName, ReactNode> = {
  back: <path d="m14 5-7 7 7 7M7 12h13" />,
  settings: <><path d="M4 7h16M4 17h16" /><circle cx="9" cy="7" r="3" /><circle cx="15" cy="17" r="3" /></>,
  microphone: <><path d="M9 9V5a3 3 0 0 1 6 0v8M5 10v2a7 7 0 0 0 12 5M12 19v3M8 22h8M3 3l18 18" /></>,
  camera: <><path d="M9 5h6a2 2 0 0 1 2 2v2l4-2v10l-4-2v2M15 19H5a2 2 0 0 1-2-2V7M3 3l18 18" /></>,
  text: <path d="M5 4h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H8l-5 3V6a2 2 0 0 1 2-2ZM7 9h10M7 13h7" />,
  end: <path d="M3 11c5-5 13-5 18 0v5l-5-1v-4M3 11v5l5-1v-4" />,
  close: <path d="m6 6 12 12M18 6 6 18" />,
};
export default function CallIcon({ name }: { name: IconName }) {
  return <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}
