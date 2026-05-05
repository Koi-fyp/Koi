'use client';
import { useState } from 'react';

type AvatarId = 'female_human' | 'male_human' | 'fox';

interface AvatarOption {
  id: AvatarId;
  label: string;
  emoji: string;
  description: string;
}

const AVATARS: AvatarOption[] = [
  { id: 'female_human', label: 'Aisha', emoji: '👩', description: 'Warm & caring' },
  { id: 'male_human', label: 'Raza', emoji: '👨', description: 'Calm & grounded' },
  { id: 'fox', label: 'Koi', emoji: '🦊', description: 'Playful & curious' },
];

interface Props {
  onNext: (avatar: AvatarId) => void;
}

export default function AvatarStep({ onNext }: Props) {
  const [selected, setSelected] = useState<AvatarId | null>(null);

  return (
    <div className="flex flex-col flex-1 p-6">
      <div className="flex-1">
        <h2 className="text-2xl font-bold text-gray-900 mb-1">Choose Your Companion</h2>
        <p className="text-gray-500 mb-6 text-sm">Who would you like to talk with?</p>

        <div className="grid grid-cols-3 gap-3">
          {AVATARS.map((avatar) => (
            <button
              key={avatar.id}
              data-testid={`avatar-${avatar.id}`}
              onClick={() => setSelected(avatar.id)}
              className={`flex flex-col items-center p-4 rounded-2xl border-2 transition-all ${
                selected === avatar.id
                  ? 'border-[#2E75B6] bg-blue-50 ring-2 ring-[#2E75B6]'
                  : 'border-gray-200 bg-white'
              }`}
            >
              <span className="text-4xl mb-2">{avatar.emoji}</span>
              <span className="font-semibold text-sm text-gray-900">{avatar.label}</span>
              <span className="text-xs text-gray-500 mt-0.5 text-center">{avatar.description}</span>
            </button>
          ))}
        </div>
      </div>

      <button
        onClick={() => selected && onNext(selected)}
        disabled={!selected}
        className="w-full py-3 bg-[#2E75B6] text-white rounded-xl font-semibold text-lg mt-6 disabled:opacity-40 disabled:cursor-not-allowed"
      >
        Continue
      </button>
    </div>
  );
}
