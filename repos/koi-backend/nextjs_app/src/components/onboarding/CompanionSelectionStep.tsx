'use client';
import React, { useState } from 'react';
import { motion } from 'framer-motion';
import Image from 'next/image';
import type { CompanionId } from '@/lib/avatar/avatarPreference';

const companions = [
  { id: 'aisha', name: 'Aisha', trait: 'Warm & caring · Female avatar', color: '#FF4A60', image: '/Female.png' },
  { id: 'raza', name: 'Raza', trait: 'Calm & grounded · Male avatar', color: '#FFC224', image: '/Male.png' },
  { id: 'koi', name: 'Koi', trait: 'Playful & curious · Fox choice', color: '#06b6d4', image: null },
] as const;

interface CompanionSelectionStepProps {
  readonly onNext: (id: CompanionId) => void;
  readonly initialSelection?: CompanionId;
}

interface CompanionCardProps {
  readonly companion: (typeof companions)[number];
  readonly isSelected: boolean;
  readonly onSelect: () => void;
}

function CompanionCard({ companion, isSelected, onSelect }: CompanionCardProps) {
  const [imageFailed, setImageFailed] = useState(false);
  return (
    <motion.button
      type="button"
      aria-pressed={isSelected}
      onClick={onSelect}
      whileHover={{ y: -4 }}
      whileTap={{ y: 2 }}
      className={`
        group cursor-pointer flex flex-col text-left
        bg-white border-[3px] border-black rounded-[32px] overflow-hidden
        transition-all duration-300 hover:translate-y-[-4px]
        ${isSelected ? 'shadow-[6px_6px_0px_0px_#06b6d4] hover:shadow-[8px_8px_0px_0px_#06b6d4]' : 'shadow-[4px_4px_0px_0px_rgba(0,0,0,1)] hover:shadow-[8px_8px_0px_0px_rgba(0,0,0,1)]'}
      `}
      style={{ transform: isSelected ? 'translateY(-2px)' : undefined }}
    >
      <div
        className="p-8 flex justify-center items-center border-b-[3px] border-black transition-colors duration-300"
        style={{ backgroundColor: isSelected ? '#06b6d4' : '#F0F0F0' }}
      >
        {companion.image && !imageFailed ? <Image src={companion.image} onError={() => setImageFailed(true)} alt={`${companion.name} avatar preview`} width={110} height={118} className="h-[118px] w-auto object-contain transition-transform duration-300 group-hover:scale-105" /> : companion.image ? <p role="status">{companion.name} preview unavailable. You can still select this companion.</p> :
          <div className="flex h-[118px] flex-col items-center justify-center gap-2 text-5xl" aria-label="Fox avatar preview unavailable">
            <span aria-hidden="true">🦊</span><span className="text-sm font-semibold">Fox preview unavailable</span>
          </div>}
      </div>

      <div className="bg-white p-6 text-center flex-1">
        <h3 className="text-2xl font-black uppercase italic text-black">{companion.name}</h3>
        <p className="text-gray-500 font-medium mt-2">{companion.trait}</p>
      </div>
    </motion.button>
  );
}

export default function CompanionSelectionStep({ onNext, initialSelection = 'raza' }: CompanionSelectionStepProps) {
  const [selected, setSelected] = useState<CompanionId>(initialSelection);

  const selectedCompanion = companions.find((c) => c.id === selected);
  const buttonColor = selectedCompanion?.color || '#06b6d4';

  return (
    <div className="flex flex-col items-center gap-8 p-8">
      <div className="w-full max-w-4xl">
        <h2 className="text-3xl font-bold text-black mb-2">Choose Your Companion</h2>
        <p className="text-gray-600 mb-8">Choose your companion and matching avatar. Aisha uses the female model, Raza the male model, and Koi keeps the fox choice.</p>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {companions.map((comp) => (
            <CompanionCard
              key={comp.id}
              companion={comp}
              isSelected={selected === comp.id}
              onSelect={() => setSelected(comp.id)}
            />
          ))}
        </div>
      </div>

      <motion.button
        type="button"
        onClick={() => onNext(selected)}
        whileHover={{ x: 2, y: 2, boxShadow: '2px 2px 0 0 rgba(0,0,0,1)' }}
        whileTap={{ x: 5, y: 5, boxShadow: '0 0 0 0 rgba(0,0,0,0)' }}
        style={{ backgroundColor: buttonColor, color: '#ffffff', borderColor: '#000' }}
        className="mt-8 px-8 py-3 border-[3px] border-black rounded-full font-bold text-lg shadow-[5px_5px_0px_0px_rgba(0,0,0,1)] transition-all"
      >
        Continue with {selectedCompanion?.name}
      </motion.button>
    </div>
  );
}
