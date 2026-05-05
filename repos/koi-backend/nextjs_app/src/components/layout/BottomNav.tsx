'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

const TABS = [
  { href: '/chat', label: 'Chat', icon: '💬' },
  { href: '/progress', label: 'Progress', icon: '🧩' },
  { href: '/settings', label: 'Settings', icon: '⚙️' },
];

export default function BottomNav() {
  const pathname = usePathname();

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-200 z-10">
      <div className="mx-auto w-full max-w-[480px] flex">
        {TABS.map((tab) => {
          const active = pathname === tab.href || pathname.startsWith(`${tab.href}/`);
          return (
            <Link
              key={tab.href}
              href={tab.href}
              className={`flex-1 flex flex-col items-center py-3 text-xs transition-colors ${
                active ? 'text-[#2E75B6]' : 'text-gray-400'
              }`}
            >
              <span className="text-xl mb-0.5">{tab.icon}</span>
              <span className={active ? 'font-semibold' : ''}>{tab.label}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
