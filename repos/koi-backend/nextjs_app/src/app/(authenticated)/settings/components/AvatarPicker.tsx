'use client';

import { useState } from 'react';

const companions = [
  { id: 'aisha', name: 'Aisha', trait: 'Warm & caring', color: '#FF4A60', icon: '👩' },
  { id: 'raza', name: 'Raza', trait: 'Calm & grounded', color: '#FFC224', icon: '👨' },
  { id: 'koi', name: 'Koi', trait: 'Playful & curious', color: '#06b6d4', icon: '🦊' },
] as const;

interface AvatarPickerProps {
  isOpen: boolean;
  onClose: () => void;
  currentAvatar?: string;
  currentName?: string;
  onSave: (avatar: string, name: string) => void;
}

interface CompanionCardProps {
  companion: typeof companions[number];
  isSelected: boolean;
  onSelect: () => void;
}

function CompanionCard({ companion, isSelected, onSelect }: CompanionCardProps) {
  return (
    <button
      type="button"
      onClick={onSelect}
      className="group cursor-pointer flex flex-col text-left bg-white border-[3px] border-black rounded-[32px] overflow-hidden transition-all duration-300"
      style={{
        boxShadow: isSelected 
          ? '6px 6px 0px 0px #06b6d4' 
          : '4px 4px 0px 0px rgba(0,0,0,1)',
        transform: isSelected ? 'translateY(-2px)' : 'translateY(0)',
      }}
      onMouseEnter={(e) => {
        if (!isSelected) {
          e.currentTarget.style.transform = 'translateY(-4px)';
          e.currentTarget.style.boxShadow = '8px 8px 0px 0px rgba(0,0,0,1)';
        }
      }}
      onMouseLeave={(e) => {
        if (!isSelected) {
          e.currentTarget.style.transform = 'translateY(0)';
          e.currentTarget.style.boxShadow = '4px 4px 0px 0px rgba(0,0,0,1)';
        }
      }}
    >
      <div
        className="p-8 flex justify-center items-center border-b-[3px] border-black transition-colors duration-300"
        style={{ backgroundColor: isSelected ? '#06b6d4' : '#F0F0F0' }}
      >
        <div className="text-6xl transition-transform duration-300 group-hover:scale-110">
          {companion.icon}
        </div>
      </div>

      <div className="bg-white p-6 text-center flex-1">
        <h3 className="text-2xl font-black uppercase italic text-black">{companion.name}</h3>
        <p className="text-gray-500 font-medium mt-2">{companion.trait}</p>
      </div>
    </button>
  );
}

export default function AvatarPicker({ 
  isOpen, 
  onClose, 
  currentAvatar = 'koi', 
  currentName = '',
  onSave 
}: AvatarPickerProps) {
  const [selected, setSelected] = useState(currentAvatar);
  const [name, setName] = useState(currentName);

  if (!isOpen) return null;

  const handleSave = () => {
    onSave(selected, name);
    onClose();
  };

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0, 0, 0, 0.6)',
        backdropFilter: 'blur(8px)',
        zIndex: 9999,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '1rem',
        animation: 'fadeIn 0.2s ease',
      }}
      onClick={onClose}
    >
      <div
        style={{
          background: '#fff',
          border: '3px solid #000',
          borderRadius: '2rem',
          boxShadow: '12px 12px 0 #000',
          maxWidth: '900px',
          width: '100%',
          maxHeight: '90vh',
          overflow: 'auto',
          padding: '2rem',
          animation: 'slideUpModal 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div style={{ marginBottom: '2rem' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '0.5rem' }}>
            <h2 style={{ fontSize: '2rem', fontWeight: 900, letterSpacing: '-0.02em' }}>
              Choose Your Companion
            </h2>
            <button
              onClick={onClose}
              style={{
                width: '36px',
                height: '36px',
                borderRadius: '50%',
                border: '2px solid #000',
                background: '#F0F0F0',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                cursor: 'pointer',
                fontSize: '1.25rem',
                fontWeight: 700,
                transition: 'all 0.2s ease',
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.background = '#FFD100';
                e.currentTarget.style.transform = 'rotate(90deg)';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.background = '#F0F0F0';
                e.currentTarget.style.transform = 'rotate(0deg)';
              }}
            >
              ✕
            </button>
          </div>
          <p style={{ color: '#666', fontSize: '0.95rem' }}>
            Pick the personality that resonates with you
          </p>
        </div>

        {/* Companion Cards */}
        <div style={{ 
          display: 'grid', 
          gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', 
          gap: '1.5rem',
          marginBottom: '2rem'
        }}>
          {companions.map((comp) => (
            <CompanionCard
              key={comp.id}
              companion={comp}
              isSelected={selected === comp.id}
              onSelect={() => setSelected(comp.id)}
            />
          ))}
        </div>

        {/* Name Input */}
        <div style={{ marginBottom: '2rem' }}>
          <label 
            htmlFor="companion-name"
            style={{ 
              display: 'block',
              fontSize: '0.9rem',
              fontWeight: 700,
              marginBottom: '0.5rem',
              color: '#000'
            }}
          >
            Your Name (Optional)
          </label>
          <input
            id="companion-name"
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="What should I call you?"
            style={{
              width: '100%',
              padding: '0.875rem 1.25rem',
              fontSize: '1rem',
              fontWeight: 500,
              border: '2.5px solid #000',
              borderRadius: '12px',
              background: '#F9F9F9',
              outline: 'none',
              transition: 'all 0.2s ease',
            }}
            onFocus={(e) => {
              e.currentTarget.style.background = '#fff';
              e.currentTarget.style.boxShadow = '0 0 0 4px rgba(45, 99, 235, 0.1)';
            }}
            onBlur={(e) => {
              e.currentTarget.style.background = '#F9F9F9';
              e.currentTarget.style.boxShadow = 'none';
            }}
          />
        </div>

        {/* Actions */}
        <div style={{ display: 'flex', gap: '1rem' }}>
          <button
            onClick={onClose}
            className="neo-btn-ghost"
            style={{ flex: 1 }}
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            className="neo-btn-primary"
            style={{ flex: 1 }}
          >
            Save Changes ✓
          </button>
        </div>
      </div>

      <style jsx>{`
        @keyframes fadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        @keyframes slideUpModal {
          from {
            opacity: 0;
            transform: translateY(40px) scale(0.95);
          }
          to {
            opacity: 1;
            transform: translateY(0) scale(1);
          }
        }
      `}</style>
    </div>
  );
}
