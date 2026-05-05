'use client';
import { useState } from 'react';

type Language = 'en' | 'ur';

interface Props {
  onNext: (language: Language) => void;
}

const LANGUAGES = [
  { id: 'en' as Language, label: 'English', native: 'English' },
  { id: 'ur' as Language, label: 'Urdu', native: 'اردو' },
];

export default function LanguageStep({ onNext }: Props) {
  const [selected, setSelected] = useState<Language>('en');

  return (
    <div className="flex flex-col flex-1 p-6">
      <div className="flex-1">
        <h2 className="text-2xl font-bold text-gray-900 mb-1">Select Language</h2>
        <p className="text-gray-500 mb-6 text-sm">Choose your preferred language.</p>

        <div className="space-y-3">
          {LANGUAGES.map((lang) => (
            <button
              key={lang.id}
              onClick={() => setSelected(lang.id)}
              className={`w-full flex items-center justify-between p-4 rounded-xl border-2 transition-all ${
                selected === lang.id
                  ? 'border-[#2E75B6] bg-blue-50'
                  : 'border-gray-200 bg-white'
              }`}
            >
              <span className="font-semibold text-gray-900">{lang.label}</span>
              <span className="text-gray-500 text-lg">{lang.native}</span>
            </button>
          ))}
        </div>
      </div>

      <button
        onClick={() => onNext(selected)}
        className="w-full py-3 bg-[#2E75B6] text-white rounded-xl font-semibold text-lg mt-6"
      >
        Continue
      </button>
    </div>
  );
}
