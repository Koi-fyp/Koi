'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import ModeSelector from './ModeSelector';

interface IconProps { active: boolean }

function ChatIcon({ active }: IconProps) {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none">
      <path
        d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"
        stroke="currentColor"
        strokeWidth={active ? 2.5 : 2}
        strokeLinecap="round"
        strokeLinejoin="round"
        fill={active ? 'currentColor' : 'none'}
        fillOpacity={active ? 0.25 : 0}
      />
    </svg>
  );
}

function ProgressIcon({ active }: IconProps) {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none">
      <polyline
        points="22 12 18 12 15 21 9 3 6 12 2 12"
        stroke="currentColor"
        strokeWidth={active ? 2.5 : 2}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function SettingsIcon({ active }: IconProps) {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none">
      <circle cx="12" cy="12" r="3" stroke="currentColor" strokeWidth={active ? 2.5 : 2} />
      <path
        d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"
        stroke="currentColor"
        strokeWidth={active ? 2.5 : 2}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

const TABS = [
  { href: '/chat',     label: 'Chat',     Icon: ChatIcon     },
  { href: '/progress', label: 'Progress', Icon: ProgressIcon },
  { href: '/settings', label: 'Settings', Icon: SettingsIcon },
];

export default function BottomNav() {
  const pathname = usePathname();

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 px-4 py-2 bg-[#ffe5d9]">
      <div className="max-w-6xl mx-auto flex items-center bg-white border-[3px] border-black rounded-full shadow-[5px_5px_0px_0px_#06b6d4] px-6 py-2 gap-4">
        {/* Logo - Left */}
        <div className="flex items-center gap-2 flex-shrink-0">
          <div className="w-8 h-8 rounded-md bg-[var(--neo-blue)] border-[2px] border-black flex items-center justify-center font-bold text-white text-sm">
            K
          </div>
          <span className="font-bold text-black text-lg">KOI</span>
        </div>

        {/* Center Tabs */}
        <div className="flex-1 flex items-center justify-center gap-3">
          {TABS.map(({ href, label, Icon }) => {
            const active = pathname === href || pathname.startsWith(`${href}/`);
            return (
              <Link
                key={href}
                href={href}
                className={`flex items-center gap-2 px-4 py-2 rounded-full font-bold text-sm transition-all ${
                  active
                    ? 'bg-black text-white border-2 border-black'
                    : 'text-gray-600 hover:text-black'
                }`}
              >
                <Icon active={active} />
                {label}
              </Link>
            );
          })}
        </div>

        {/* Mode Selector - Right */}
        <ModeSelector />
      </div>
    </nav>
  );
}
