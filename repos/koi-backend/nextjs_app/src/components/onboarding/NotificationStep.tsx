'use client';
import { useState } from 'react';

interface Props {
  onComplete: (notificationTime: string, notificationsEnabled: boolean) => void;
}

export default function NotificationStep({ onComplete }: Props) {
  const [enabled, setEnabled] = useState(true);
  const [time, setTime] = useState('20:00');

  return (
    <div className="flex flex-col flex-1 p-6">
      <div className="flex-1">
        <h2 className="text-2xl font-bold text-gray-900 mb-1">Daily Check-ins</h2>
        <p className="text-gray-500 mb-6 text-sm">
          KOI can gently check in with you each day to see how you&apos;re feeling.
        </p>

        <div className="bg-white rounded-xl border border-gray-200 p-4 mb-3">
          <div className="flex items-center justify-between">
            <span className="font-semibold text-gray-900 text-sm">Enable daily reminders</span>
            <button
              role="switch"
              aria-checked={enabled}
              onClick={() => setEnabled((v) => !v)}
              className={`relative w-12 h-6 rounded-full transition-colors ${
                enabled ? 'bg-[#2E75B6]' : 'bg-gray-300'
              }`}
            >
              <span
                className={`absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform ${
                  enabled ? 'translate-x-6' : 'translate-x-0'
                }`}
              />
            </button>
          </div>
        </div>

        {enabled && (
          <div className="bg-white rounded-xl border border-gray-200 p-4">
            <label htmlFor="notif-time" className="block text-sm font-medium text-gray-700 mb-2">
              Reminder time
            </label>
            <input
              id="notif-time"
              type="time"
              value={time}
              min="06:00"
              max="23:00"
              onChange={(e) => setTime(e.target.value)}
              className="w-full border border-gray-300 rounded-lg px-3 py-2 text-lg font-mono focus:outline-none focus:border-[#2E75B6]"
            />
            <p className="text-xs text-gray-400 mt-1">Available 6:00 AM – 11:00 PM</p>
          </div>
        )}
      </div>

      <button
        onClick={() => onComplete(time, enabled)}
        className="w-full py-3 bg-[#2E75B6] text-white rounded-xl font-semibold text-lg mt-6"
      >
        Get Started
      </button>
    </div>
  );
}
