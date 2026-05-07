'use client';
import React from 'react';
import ChangeModeDropdown from './ChangeModeDropdown';

export default function Navigation() {
  return (
    <nav className="flex items-center gap-4 p-4">
      <div className="flex bg-white border-[3px] border-black shadow-[5px_5px_0px_0px_rgba(0,0,0,1)] rounded-full px-6 py-2 gap-2">
        <button className="neo-btn-ghost">Chat</button>
        <button className="neo-btn-ghost">Progress</button>
        <button className="neo-btn-ghost">Settings</button>
      </div>

      <div className="relative">
        <ChangeModeDropdown />
      </div>
    </nav>
  );
}
