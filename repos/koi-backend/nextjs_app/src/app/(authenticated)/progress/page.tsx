'use client';
import { useState } from 'react';

const STATS = [
  { label: 'Days Streak', value: '12', unit: 'days', color: '#FFD100', icon: 'flame' },
  { label: 'Total Sessions', value: '47', unit: 'sessions', color: '#2DD36F', icon: 'chat' },
  { label: 'Avg Mood', value: '7.2', unit: '/ 10', color: '#2D63EB', icon: 'smile' },
];

const MILESTONES = [
  { id: 1, title: 'First Conversation', desc: 'You opened up for the first time.', done: true, color: '#2DD36F', reward: '+5 pieces' },
  { id: 2, title: '7-Day Streak', desc: 'A week of showing up for yourself.', done: true, color: '#2D63EB', reward: '+10 pieces' },
  { id: 3, title: '50 Pieces', desc: 'Halfway to your first milestone.', done: false, color: '#FFD100', reward: '+15 pieces' },
  { id: 4, title: 'Deep Diver', desc: 'Explored something truly personal.', done: false, color: '#845EC2', reward: '+20 pieces' },
];

const EMOTION_COLORS = {
  calm: '#A5D6A7',
  happy: '#FFD100',
  anxious: '#FF8A65',
  sad: '#90CAF9',
  growth: '#845EC2',
};

// Jigsaw piece data with achievements
const JIGSAW_ACHIEVEMENTS = [
  { id: 0, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 1, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 2, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 3, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 4, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 5, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 6, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 7, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 8, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 9, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 10, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 11, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 12, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 13, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 14, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 15, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 16, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 17, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 18, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 19, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 20, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 21, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 22, filled: false, color: '#f0f0f0', achievement: 'Locked', description: 'Complete more activities to unlock', emotion: 'locked' },
  { id: 23, filled: true, color: '#2DD36F', achievement: 'First Task Done', description: 'Looking in the mirror and calling yourself beautiful', emotion: 'calm' },
  { id: 24, filled: true, color: '#FFD100', achievement: 'Daily Check-in', description: 'Shared how you felt today with courage', emotion: 'happy' },
];

// Simple SVG Icons
const Icon = ({ type, color = '#000', size = 16 }: { type: string; color?: string; size?: number }) => {
  const icons: Record<string, JSX.Element> = {
    flame: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
      </svg>
    ),
    chat: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
      </svg>
    ),
    smile: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="12" r="10" />
        <path d="M8 14s1.5 2 4 2 4-2 4-2" />
        <line x1="9" y1="9" x2="9.01" y2="9" />
        <line x1="15" y1="9" x2="15.01" y2="9" />
      </svg>
    ),
    lock: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
        <path d="M7 11V7a5 5 0 0 1 10 0v4" />
      </svg>
    ),
    check: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="20 6 9 17 4 12" />
      </svg>
    ),
    arrow: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <line x1="12" y1="5" x2="12" y2="19" />
        <polyline points="19 12 12 19 5 12" />
      </svg>
    ),
    sparkles: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z" />
        <path d="M5 3v4" />
        <path d="M19 17v4" />
        <path d="M3 5h4" />
        <path d="M17 19h4" />
      </svg>
    ),
    puzzle: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M19.439 7.85c-.049.322.059.648.289.878l1.568 1.568c.47.47.706 1.087.706 1.704s-.235 1.233-.706 1.704l-1.611 1.611a.98.98 0 0 1-.837.276c-.47-.07-.802-.48-.968-.925a2.501 2.501 0 1 0-3.214 3.214c.446.166.855.497.925.968a.979.979 0 0 1-.276.837l-1.61 1.61a2.404 2.404 0 0 1-1.705.707 2.402 2.402 0 0 1-1.704-.706l-1.568-1.568a1.026 1.026 0 0 0-.877-.29c-.493.074-.84.504-1.02.968a2.5 2.5 0 1 1-3.237-3.237c.464-.18.894-.527.967-1.02a1.026 1.026 0 0 0-.289-.877l-1.568-1.568A2.402 2.402 0 0 1 1.998 12c0-.617.236-1.234.706-1.704L4.23 8.77c.24-.24.581-.353.917-.303.515.077.877.528 1.073 1.01a2.5 2.5 0 1 0 3.259-3.259c-.482-.196-.933-.558-1.01-1.073-.05-.336.062-.676.303-.917l1.525-1.525A2.402 2.402 0 0 1 12 1.998c.617 0 1.234.236 1.704.706l1.568 1.568c.23.23.556.338.877.29.493-.074.84-.504 1.02-.968a2.5 2.5 0 1 1 3.237 3.237c-.464.18-.894.527-.967 1.02Z" />
      </svg>
    ),
    star: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
      </svg>
    ),
    heart: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
      </svg>
    ),
    download: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
        <polyline points="7 10 12 15 17 10" />
        <line x1="12" y1="15" x2="12" y2="3" />
      </svg>
    ),
    share: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="18" cy="5" r="3" />
        <circle cx="6" cy="12" r="3" />
        <circle cx="18" cy="19" r="3" />
        <line x1="8.59" y1="13.51" x2="15.42" y2="17.49" />
        <line x1="15.41" y1="6.51" x2="8.59" y2="10.49" />
      </svg>
    ),
    calendar: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
        <line x1="16" y1="2" x2="16" y2="6" />
        <line x1="8" y1="2" x2="8" y2="6" />
        <line x1="3" y1="10" x2="21" y2="10" />
      </svg>
    ),
    trendingUp: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="23 6 13.5 15.5 8.5 10.5 1 18" />
        <polyline points="17 6 23 6 23 12" />
      </svg>
    ),
    brain: (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M9.5 2A2.5 2.5 0 0 1 12 4.5v15a2.5 2.5 0 0 1-4.96.44 2.5 2.5 0 0 1-2.96-3.08 3 3 0 0 1-.34-5.58 2.5 2.5 0 0 1 1.32-4.24 2.5 2.5 0 0 1 1.98-3A2.5 2.5 0 0 1 9.5 2Z" />
        <path d="M14.5 2A2.5 2.5 0 0 0 12 4.5v15a2.5 2.5 0 0 0 4.96.44 2.5 2.5 0 0 0 2.96-3.08 3 3 0 0 0 .34-5.58 2.5 2.5 0 0 0-1.32-4.24 2.5 2.5 0 0 0-1.98-3A2.5 2.5 0 0 0 14.5 2Z" />
      </svg>
    ),
  };

  return icons[type] || null;
};

export default function ProgressPage() {
  const [selectedMilestone, setSelectedMilestone] = useState<number | null>(null);
  const [jigsawExpanded, setJigsawExpanded] = useState(false);
  const [hoveredStat, setHoveredStat] = useState<string | null>(null);
  const [hoveredPiece, setHoveredPiece] = useState<number | null>(null);
  const [selectedMoodDay, setSelectedMoodDay] = useState<number | null>(null);

  const totalPieces = 247;
  const filledCount = JIGSAW_ACHIEVEMENTS.filter((p) => p.filled).length;
  const filledPercentage = (filledCount / 25) * 100;

  // Mock mood data for the chart (last 7 days)
  const moodData = [
    { day: 'Mon', mood: 6.5, color: '#90CAF9' },
    { day: 'Tue', mood: 7.2, color: '#A5D6A7' },
    { day: 'Wed', mood: 5.8, color: '#FF8A65' },
    { day: 'Thu', mood: 7.8, color: '#FFD100' },
    { day: 'Fri', mood: 8.2, color: '#2DD36F' },
    { day: 'Sat', mood: 7.5, color: '#A5D6A7' },
    { day: 'Sun', mood: 7.9, color: '#FFD100' },
  ];

  const maxMood = 10;

  // Activity heatmap data (last 8 weeks)
  const generateHeatmapData = () => {
    const weeks = 8;
    const days = 7;
    const data = [];
    for (let w = 0; w < weeks; w++) {
      for (let d = 0; d < days; d++) {
        const intensity = Math.floor(Math.random() * 5); // 0-4
        data.push({ week: w, day: d, intensity });
      }
    }
    return data;
  };

  const heatmapData = generateHeatmapData();

  return (
    <div
      style={{
        padding: '1.5rem 1.5rem 0',
        maxWidth: '480px',
        margin: '0 auto',
        paddingBottom: '2rem',
        position: 'relative',
      }}
    >
      {/* Animated header with celebration particles */}
      <div style={{ position: 'relative', marginBottom: '1.5rem' }}>
        <h1
          style={{
            fontFamily: 'var(--font-body)',
            fontWeight: 800,
            fontSize: '2rem',
            letterSpacing: '-0.03em',
            color: '#000',
            marginBottom: '0.25rem',
            position: 'relative',
            display: 'inline-block',
          }}
        >
          Your Progress
          <div
            style={{
              position: 'absolute',
              top: '-8px',
              right: '-32px',
              animation: 'floatY 2s ease-in-out infinite',
            }}
          >
            <Icon type="sparkles" color="#FFD100" size={20} />
          </div>
        </h1>
        <p
          style={{
            fontFamily: 'var(--font-body)',
            fontSize: '0.875rem',
            color: '#666',
            fontWeight: 500,
          }}
        >
          Every step matters. Keep growing.
        </p>
      </div>

      {/* Jigsaw Hero Card - Expandable */}
      <div
        style={{
          background: jigsawExpanded ? '#1a54b8' : '#2D63EB',
          border: '2.5px solid #000',
          borderRadius: '1.25rem',
          boxShadow: jigsawExpanded ? '10px 10px 0 0 #000' : '6px 6px 0 0 #000',
          padding: jigsawExpanded ? '2rem' : '1.5rem',
          marginBottom: '1.25rem',
          position: 'relative',
          overflow: 'hidden',
          cursor: 'pointer',
          transition: 'all 0.4s cubic-bezier(0.34, 1.56, 0.64, 1)',
          transform: jigsawExpanded ? 'scale(1.02)' : 'scale(1)',
          minHeight: jigsawExpanded ? '480px' : 'auto',
        }}
        onClick={() => setJigsawExpanded(!jigsawExpanded)}
      >
        {/* Background decorations */}
        <div
          style={{
            position: 'absolute',
            right: '-1.5rem',
            top: '-1.5rem',
            width: '8rem',
            height: '8rem',
            borderRadius: '50%',
            background: 'rgba(255,255,255,0.07)',
            border: '2px solid rgba(255,255,255,0.1)',
            transition: 'all 0.4s ease',
            transform: jigsawExpanded ? 'scale(1.5) translate(-20%, 20%)' : 'scale(1)',
          }}
        />

        {!jigsawExpanded ? (
          // Collapsed view
          <>
            <p
              style={{
                fontFamily: 'var(--font-body)',
                fontSize: '0.75rem',
                color: 'rgba(255,255,255,0.65)',
                fontWeight: 500,
                marginBottom: '0.375rem',
                letterSpacing: '0.08em',
                textTransform: 'uppercase',
              }}
            >
              Total Pieces Collected
            </p>
            <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', marginBottom: '0.5rem' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <Icon type="puzzle" color="#fff" size={48} />
                <p
                  style={{
                    fontFamily: 'var(--font-body)',
                    fontWeight: 800,
                    fontSize: '3.5rem',
                    color: '#fff',
                    lineHeight: 1,
                    letterSpacing: '-0.03em',
                  }}
                >
                  {totalPieces}
                </p>
              </div>
              <div
                style={{
                  background: 'rgba(255,255,255,0.2)',
                  border: '2px solid rgba(255,255,255,0.3)',
                  borderRadius: '50%',
                  width: '36px',
                  height: '36px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  transition: 'transform 0.3s ease',
                }}
              >
                <Icon type="arrow" color="#fff" size={20} />
              </div>
            </div>
            <p
              style={{
                fontFamily: 'var(--font-body)',
                fontSize: '0.875rem',
                color: 'rgba(255,255,255,0.6)',
              }}
            >
              pieces of your story, preserved
            </p>
          </>
        ) : (
          // Expanded view - Jigsaw puzzle
          <div
            style={{
              animation: 'fadeUp 0.5s ease both',
              position: 'relative',
              zIndex: 1,
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1.25rem' }}>
              <div>
                <p
                  style={{
                    fontFamily: 'var(--font-body)',
                    fontSize: '0.75rem',
                    color: 'rgba(255,255,255,0.65)',
                    fontWeight: 500,
                    marginBottom: '0.25rem',
                    letterSpacing: '0.08em',
                    textTransform: 'uppercase',
                  }}
                >
                  How Far You've Come
                </p>
                <p
                  style={{
                    fontFamily: 'var(--font-body)',
                    fontWeight: 700,
                    fontSize: '1.5rem',
                    color: '#fff',
                    lineHeight: 1,
                  }}
                >
                  Your Wellness Journey
                </p>
              </div>
              <div
                style={{
                  background: 'rgba(255,255,255,0.2)',
                  border: '2px solid rgba(255,255,255,0.3)',
                  borderRadius: '50%',
                  width: '32px',
                  height: '32px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  transform: 'rotate(180deg)',
                  cursor: 'pointer',
                }}
                onClick={(e) => {
                  e.stopPropagation();
                  setJigsawExpanded(false);
                }}
              >
                <Icon type="arrow" color="#fff" size={18} />
              </div>
            </div>

            {/* 5x5 Jigsaw Grid */}
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(5, 1fr)',
                gap: '6px',
                marginBottom: '1rem',
                background: 'rgba(0,0,0,0.15)',
                padding: '1rem',
                borderRadius: '12px',
                border: '2px solid rgba(255,255,255,0.1)',
                position: 'relative',
              }}
            >
              {JIGSAW_ACHIEVEMENTS.map((piece, i) => (
                <div
                  key={i}
                  style={{
                    aspectRatio: '1',
                    background: piece.filled
                      ? `linear-gradient(135deg, ${piece.color} 0%, ${piece.color}dd 100%)`
                      : '#f0f0f0',
                    border: piece.filled ? '2px solid rgba(0,0,0,0.2)' : '2px solid rgba(0,0,0,0.08)',
                    borderRadius: '6px',
                    position: 'relative',
                    overflow: 'visible',
                    transition: 'all 0.3s ease',
                    animation: `fadeUp 0.4s ease ${i * 0.02}s both`,
                    cursor: piece.filled ? 'pointer' : 'default',
                    transform: hoveredPiece === i && piece.filled ? 'scale(1.08)' : 'scale(1)',
                    zIndex: hoveredPiece === i ? 10 : 1,
                  }}
                  onMouseEnter={() => piece.filled && setHoveredPiece(i)}
                  onMouseLeave={() => setHoveredPiece(null)}
                >
                  {piece.filled ? (
                    <div
                      style={{
                        position: 'absolute',
                        inset: 0,
                        background: 'rgba(255,255,255,0.15)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        borderRadius: '4px',
                      }}
                    >
                      <img
                        src="https://api.dicebear.com/7.x/notionists/svg?seed=Felix&backgroundColor=transparent"
                        alt="avatar piece"
                        style={{
                          width: '100%',
                          height: '100%',
                          objectFit: 'cover',
                          opacity: 0.9,
                          filter: `hue-rotate(${i * 15}deg)`,
                        }}
                      />
                    </div>
                  ) : (
                    <div
                      style={{
                        position: 'absolute',
                        inset: 0,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                      }}
                    >
                      <Icon type="lock" color="#ccc" size={18} />
                    </div>
                  )}

                  {/* Tooltip on hover */}
                  {hoveredPiece === i && piece.filled && (
                    <div
                      style={{
                        position: 'absolute',
                        bottom: '110%',
                        left: '50%',
                        transform: 'translateX(-50%)',
                        background: '#fff',
                        border: '2.5px solid #000',
                        borderRadius: '8px',
                        padding: '0.5rem 0.75rem',
                        boxShadow: '4px 4px 0 #000',
                        whiteSpace: 'nowrap',
                        zIndex: 100,
                        animation: 'fadeUp 0.2s ease both',
                        minWidth: '180px',
                        width: 'max-content',
                        maxWidth: '220px',
                      }}
                      onClick={(e) => e.stopPropagation()}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', marginBottom: '0.25rem' }}>
                        <div
                          style={{
                            width: '8px',
                            height: '8px',
                            borderRadius: '50%',
                            background: piece.color,
                            border: '1.5px solid #000',
                          }}
                        />
                        <p
                          style={{
                            fontFamily: 'var(--font-body)',
                            fontSize: '0.7rem',
                            fontWeight: 700,
                            color: '#000',
                            textTransform: 'uppercase',
                            letterSpacing: '0.05em',
                          }}
                        >
                          {piece.emotion}
                        </p>
                      </div>
                      <p
                        style={{
                          fontFamily: 'var(--font-body)',
                          fontSize: '0.75rem',
                          fontWeight: 600,
                          color: '#000',
                          marginBottom: '0.125rem',
                        }}
                      >
                        {piece.achievement}
                      </p>
                      <p
                        style={{
                          fontFamily: 'var(--font-body)',
                          fontSize: '0.65rem',
                          color: '#666',
                          lineHeight: 1.4,
                          whiteSpace: 'normal',
                        }}
                      >
                        {piece.description}
                      </p>
                      {/* Arrow pointer */}
                      <div
                        style={{
                          position: 'absolute',
                          bottom: '-8px',
                          left: '50%',
                          transform: 'translateX(-50%)',
                          width: 0,
                          height: 0,
                          borderLeft: '8px solid transparent',
                          borderRight: '8px solid transparent',
                          borderTop: '8px solid #000',
                        }}
                      />
                      <div
                        style={{
                          position: 'absolute',
                          bottom: '-5px',
                          left: '50%',
                          transform: 'translateX(-50%)',
                          width: 0,
                          height: 0,
                          borderLeft: '6px solid transparent',
                          borderRight: '6px solid transparent',
                          borderTop: '6px solid #fff',
                        }}
                      />
                    </div>
                  )}
                </div>
              ))}
            </div>

            {/* Progress indicator */}
            <div
              style={{
                background: 'rgba(255,255,255,0.15)',
                borderRadius: '8px',
                padding: '0.75rem 1rem',
                border: '2px solid rgba(255,255,255,0.2)',
              }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem' }}>
                <span
                  style={{
                    fontFamily: 'var(--font-body)',
                    fontSize: '0.75rem',
                    color: 'rgba(255,255,255,0.8)',
                    fontWeight: 600,
                  }}
                >
                  Completion Progress
                </span>
                <span
                  style={{
                    fontFamily: 'var(--font-body)',
                    fontSize: '0.75rem',
                    color: '#fff',
                    fontWeight: 700,
                  }}
                >
                  {Math.round(filledPercentage)}%
                </span>
              </div>
              <div
                style={{
                  width: '100%',
                  height: '8px',
                  background: 'rgba(0,0,0,0.2)',
                  borderRadius: '4px',
                  overflow: 'hidden',
                  border: '1px solid rgba(255,255,255,0.15)',
                }}
              >
                <div
                  style={{
                    width: `${filledPercentage}%`,
                    height: '100%',
                    background: 'linear-gradient(90deg, #FFD100 0%, #2DD36F 100%)',
                    borderRadius: '4px',
                    transition: 'width 0.6s ease',
                  }}
                />
              </div>
              <p
                style={{
                  fontFamily: 'var(--font-body)',
                  fontSize: '0.7rem',
                  color: 'rgba(255,255,255,0.6)',
                  marginTop: '0.5rem',
                  textAlign: 'center',
                }}
              >
                {filledCount} of 25 pieces unlocked · Keep growing to reveal more
              </p>
            </div>
          </div>
        )}
      </div>

      {/* Enhanced Stats grid with hover effects */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '10px', marginBottom: '1.25rem' }}>
        {STATS.map((stat) => (
          <div
            key={stat.label}
            style={{
              background: hoveredStat === stat.label ? '#f8f8f8' : '#fff',
              border: '2.5px solid #000',
              borderRadius: '1rem',
              boxShadow: hoveredStat === stat.label ? '6px 6px 0 0 #000' : '4px 4px 0 0 #000',
              padding: '0.875rem 0.75rem',
              textAlign: 'center',
              cursor: 'pointer',
              transition: 'all 0.2s cubic-bezier(0.34, 1.56, 0.64, 1)',
              transform: hoveredStat === stat.label ? 'translateY(-2px) scale(1.02)' : 'translateY(0) scale(1)',
              position: 'relative',
              overflow: 'hidden',
            }}
            onMouseEnter={() => setHoveredStat(stat.label)}
            onMouseLeave={() => setHoveredStat(null)}
          >
            {hoveredStat === stat.label && (
              <div
                style={{
                  position: 'absolute',
                  top: 0,
                  left: 0,
                  right: 0,
                  height: '3px',
                  background: `linear-gradient(90deg, ${stat.color} 0%, transparent 100%)`,
                  animation: 'shimmer 1.5s ease-in-out infinite',
                }}
              />
            )}
            <div
              style={{
                marginBottom: '0.5rem',
                display: 'flex',
                justifyContent: 'center',
                animation: hoveredStat === stat.label ? 'floatY 1s ease-in-out infinite' : 'none',
              }}
            >
              <Icon type={stat.icon} color={stat.color} size={24} />
            </div>
            <p style={{ fontFamily: 'var(--font-body)', fontWeight: 800, fontSize: '1.3rem', color: '#000', lineHeight: 1 }}>
              {stat.value}
            </p>
            <p
              style={{
                fontFamily: 'var(--font-body)',
                fontSize: '0.62rem',
                color: '#aaa',
                marginTop: '2px',
                fontWeight: 500,
                textTransform: 'uppercase',
                letterSpacing: '0.06em',
              }}
            >
              {stat.unit}
            </p>
            <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.68rem', color: '#666', marginTop: '2px', fontWeight: 500 }}>
              {stat.label}
            </p>
          </div>
        ))}
      </div>

      {/* Mood Trend Chart */}
      <div
        style={{
          background: '#fff',
          border: '2.5px solid #000',
          borderRadius: '1.25rem',
          boxShadow: '6px 6px 0 0 #000',
          padding: '1.25rem',
          marginBottom: '1.25rem',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1rem' }}>
          <h3 style={{ fontFamily: 'var(--font-body)', fontWeight: 800, fontSize: '1.1rem', color: '#000', letterSpacing: '-0.02em' }}>
            Mood Trends
          </h3>
          <Icon type="trendingUp" color="#2DD36F" size={20} />
        </div>

        {/* Simple bar chart */}
        <div style={{ display: 'flex', alignItems: 'flex-end', gap: '0.5rem', height: '120px', marginBottom: '0.75rem' }}>
          {moodData.map((data, i) => (
            <div
              key={i}
              style={{
                flex: 1,
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: '0.375rem',
                cursor: 'pointer',
              }}
              onMouseEnter={() => setSelectedMoodDay(i)}
              onMouseLeave={() => setSelectedMoodDay(null)}
            >
              <div
                style={{
                  width: '100%',
                  height: `${(data.mood / maxMood) * 100}%`,
                  background: `linear-gradient(180deg, ${data.color} 0%, ${data.color}aa 100%)`,
                  border: '2px solid #000',
                  borderRadius: '6px 6px 0 0',
                  transition: 'all 0.3s ease',
                  transform: selectedMoodDay === i ? 'scale(1.05)' : 'scale(1)',
                  boxShadow: selectedMoodDay === i ? '0 4px 0 #000' : 'none',
                  position: 'relative',
                }}
              >
                {selectedMoodDay === i && (
                  <div
                    style={{
                      position: 'absolute',
                      bottom: '100%',
                      left: '50%',
                      transform: 'translateX(-50%)',
                      background: '#000',
                      color: '#fff',
                      padding: '0.25rem 0.5rem',
                      borderRadius: '6px',
                      fontSize: '0.7rem',
                      fontWeight: 600,
                      whiteSpace: 'nowrap',
                      marginBottom: '4px',
                    }}
                  >
                    {data.mood.toFixed(1)}
                  </div>
                )}
              </div>
              <span
                style={{
                  fontFamily: 'var(--font-body)',
                  fontSize: '0.7rem',
                  color: selectedMoodDay === i ? '#000' : '#999',
                  fontWeight: selectedMoodDay === i ? 700 : 500,
                }}
              >
                {data.day}
              </span>
            </div>
          ))}
        </div>

        <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.75rem', color: '#666', textAlign: 'center', lineHeight: 1.5 }}>
          Your emotional journey over the past week shows growth and resilience
        </p>
      </div>

      {/* Enhanced Milestone timeline with rewards */}
      <div
        style={{
          background: '#fff',
          border: '2.5px solid #000',
          borderRadius: '1.25rem',
          boxShadow: '6px 6px 0 0 #000',
          padding: '1.25rem',
          marginBottom: '1.5rem',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1.1rem' }}>
          <h2
            style={{
              fontFamily: 'var(--font-body)',
              fontWeight: 800,
              fontSize: '1.1rem',
              color: '#000',
              letterSpacing: '-0.02em',
            }}
          >
            Milestones
          </h2>
          <div
            style={{
              background: '#FFD100',
              border: '2px solid #000',
              borderRadius: '12px',
              padding: '0.25rem 0.625rem',
              fontSize: '0.7rem',
              fontWeight: 700,
              boxShadow: '2px 2px 0 #000',
            }}
          >
            2/4 Complete
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.875rem' }}>
          {MILESTONES.map((m, i) => (
            <div
              key={m.id}
              style={{
                display: 'flex',
                gap: '0.875rem',
                alignItems: 'flex-start',
                opacity: m.done ? 1 : 0.6,
                cursor: 'pointer',
                padding: '0.625rem',
                margin: '-0.625rem',
                borderRadius: '0.75rem',
                transition: 'all 0.2s ease',
                background: selectedMilestone === m.id ? 'rgba(0,0,0,0.04)' : 'transparent',
                border: selectedMilestone === m.id ? '2px solid rgba(0,0,0,0.06)' : '2px solid transparent',
              }}
              onClick={() => setSelectedMilestone(selectedMilestone === m.id ? null : m.id)}
              onMouseEnter={(e) => {
                if (selectedMilestone !== m.id) {
                  e.currentTarget.style.background = 'rgba(0,0,0,0.02)';
                }
              }}
              onMouseLeave={(e) => {
                if (selectedMilestone !== m.id) {
                  e.currentTarget.style.background = 'transparent';
                }
              }}
            >
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', flexShrink: 0, paddingTop: '2px' }}>
                <div
                  style={{
                    width: '24px',
                    height: '24px',
                    borderRadius: '6px',
                    background: m.done ? m.color : '#eee',
                    border: '2px solid #000',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0,
                    transition: 'all 0.2s ease',
                    transform: selectedMilestone === m.id ? 'scale(1.15)' : 'scale(1)',
                    boxShadow: m.done ? '2px 2px 0 #000' : 'none',
                  }}
                >
                  {m.done ? (
                    <Icon type="check" color="#000" size={14} />
                  ) : (
                    <div style={{ width: '8px', height: '8px', borderRadius: '50%', background: '#bbb' }} />
                  )}
                </div>
                {i < MILESTONES.length - 1 && (
                  <div
                    style={{
                      width: '2px',
                      flex: '1 0 20px',
                      background: m.done ? 'rgba(0,0,0,0.15)' : '#eee',
                      marginTop: '4px',
                    }}
                  />
                )}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '3px' }}>
                  <p style={{ fontFamily: 'var(--font-body)', fontWeight: 700, fontSize: '0.875rem', color: '#000' }}>
                    {m.title}
                  </p>
                  {m.done && (
                    <span
                      style={{
                        background: m.color,
                        border: '1.5px solid #000',
                        borderRadius: '6px',
                        padding: '0.125rem 0.375rem',
                        fontSize: '0.625rem',
                        fontWeight: 700,
                        color: '#000',
                      }}
                    >
                      {m.reward}
                    </span>
                  )}
                </div>
                <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.78rem', color: '#777', lineHeight: 1.5 }}>
                  {m.desc}
                </p>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Activity Heatmap */}
      <div
        style={{
          background: '#fff',
          border: '2.5px solid #000',
          borderRadius: '1.25rem',
          boxShadow: '6px 6px 0 0 #000',
          padding: '1.25rem',
          marginBottom: '1.5rem',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1rem' }}>
          <h3 style={{ fontFamily: 'var(--font-body)', fontWeight: 800, fontSize: '1.1rem', color: '#000', letterSpacing: '-0.02em' }}>
            Activity Heatmap
          </h3>
          <Icon type="calendar" color="#2D63EB" size={20} />
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '3px' }}>
          {[0, 1, 2, 3, 4, 5, 6].map((day) => (
            <div key={day} style={{ display: 'flex', gap: '3px' }}>
              {heatmapData
                .filter((d) => d.day === day)
                .map((d, i) => {
                  const intensityColors = ['#f0f0f0', '#c8e6c9', '#81c784', '#4caf50', '#2e7d32'];
                  return (
                    <div
                      key={i}
                      style={{
                        width: '100%',
                        aspectRatio: '1',
                        background: intensityColors[d.intensity],
                        border: '1px solid rgba(0,0,0,0.1)',
                        borderRadius: '3px',
                        cursor: 'pointer',
                        transition: 'all 0.2s ease',
                      }}
                      onMouseEnter={(e) => {
                        e.currentTarget.style.transform = 'scale(1.2)';
                        e.currentTarget.style.zIndex = '10';
                        e.currentTarget.style.boxShadow = '0 2px 4px rgba(0,0,0,0.2)';
                      }}
                      onMouseLeave={(e) => {
                        e.currentTarget.style.transform = 'scale(1)';
                        e.currentTarget.style.zIndex = '1';
                        e.currentTarget.style.boxShadow = 'none';
                      }}
                      title={`${d.intensity} activities`}
                    />
                  );
                })}
            </div>
          ))}
        </div>

        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '0.75rem' }}>
          <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.7rem', color: '#999' }}>Less</p>
          <div style={{ display: 'flex', gap: '3px' }}>
            {[0, 1, 2, 3, 4].map((i) => {
              const colors = ['#f0f0f0', '#c8e6c9', '#81c784', '#4caf50', '#2e7d32'];
              return (
                <div
                  key={i}
                  style={{
                    width: '12px',
                    height: '12px',
                    background: colors[i],
                    border: '1px solid rgba(0,0,0,0.1)',
                    borderRadius: '2px',
                  }}
                />
              );
            })}
          </div>
          <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.7rem', color: '#999' }}>More</p>
        </div>
      </div>

      {/* Emotional Growth Card */}
      <div
        style={{
          background: 'linear-gradient(135deg, #A5D6A7 0%, #81C784 100%)',
          border: '2.5px solid #000',
          borderRadius: '1.25rem',
          boxShadow: '6px 6px 0 0 #000',
          padding: '1.25rem',
          marginBottom: '1.5rem',
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            position: 'absolute',
            top: '-40px',
            right: '-40px',
            width: '120px',
            height: '120px',
            borderRadius: '50%',
            background: 'rgba(255,255,255,0.15)',
            border: '2px solid rgba(255,255,255,0.2)',
          }}
        />
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.75rem' }}>
          <Icon type="brain" color="#1B5E20" size={24} />
          <h3 style={{ fontFamily: 'var(--font-body)', fontWeight: 800, fontSize: '1rem', color: '#1B5E20' }}>
            Emotional Growth
          </h3>
        </div>
        <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', marginBottom: '0.75rem' }}>
          {Object.entries(EMOTION_COLORS).map(([emotion, color]) => (
            <div
              key={emotion}
              style={{
                background: color,
                border: '2px solid rgba(0,0,0,0.15)',
                borderRadius: '8px',
                padding: '0.375rem 0.625rem',
                fontSize: '0.7rem',
                fontWeight: 600,
                color: '#000',
                textTransform: 'capitalize',
                cursor: 'pointer',
                transition: 'transform 0.2s ease',
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.transform = 'scale(1.05)';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.transform = 'scale(1)';
              }}
            >
              {emotion}
            </div>
          ))}
        </div>
        <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.75rem', color: '#2E7D32', lineHeight: 1.5 }}>
          Your puzzle reflects your emotional journey — each color represents a different feeling you've explored.
        </p>
      </div>

      {/* Shareable Progress Card */}
      <div
        style={{
          background: '#000',
          border: '2.5px solid #000',
          borderRadius: '1.25rem',
          boxShadow: '6px 6px 0 0 #FFD100',
          padding: '1.5rem',
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            position: 'absolute',
            top: '-60px',
            right: '-60px',
            width: '180px',
            height: '180px',
            borderRadius: '50%',
            background: 'rgba(255,209,0,0.1)',
            border: '2px solid rgba(255,209,0,0.2)',
          }}
        />

        <div style={{ position: 'relative', zIndex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '1rem' }}>
            <Icon type="sparkles" color="#FFD100" size={24} />
            <h3 style={{ fontFamily: 'var(--font-body)', fontWeight: 800, fontSize: '1.1rem', color: '#fff' }}>
              Share Your Progress
            </h3>
          </div>

          <div
            style={{
              background: 'rgba(255,255,255,0.08)',
              border: '2px solid rgba(255,255,255,0.15)',
              borderRadius: '12px',
              padding: '1rem',
              marginBottom: '1rem',
            }}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.75rem' }}>
              <div>
                <p style={{ fontFamily: 'var(--font-body)', fontSize: '2rem', fontWeight: 800, color: '#FFD100', lineHeight: 1 }}>
                  {totalPieces}
                </p>
                <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.7rem', color: 'rgba(255,255,255,0.6)' }}>pieces collected</p>
              </div>
              <div>
                <p style={{ fontFamily: 'var(--font-body)', fontSize: '2rem', fontWeight: 800, color: '#2DD36F', lineHeight: 1 }}>47</p>
                <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.7rem', color: 'rgba(255,255,255,0.6)' }}>days active</p>
              </div>
              <div>
                <p style={{ fontFamily: 'var(--font-body)', fontSize: '2rem', fontWeight: 800, color: '#2D63EB', lineHeight: 1 }}>12</p>
                <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.7rem', color: 'rgba(255,255,255,0.6)' }}>day streak</p>
              </div>
            </div>
            <p
              style={{
                fontFamily: 'var(--font-body)',
                fontSize: '0.75rem',
                color: 'rgba(255,255,255,0.7)',
                textAlign: 'center',
                fontStyle: 'italic',
              }}
            >
              "Every conversation is a step toward understanding myself better"
            </p>
          </div>

          <div style={{ display: 'flex', gap: '0.75rem' }}>
            <button
              style={{
                flex: 1,
                background: '#FFD100',
                border: '2px solid #000',
                borderRadius: '12px',
                padding: '0.75rem',
                fontFamily: 'var(--font-body)',
                fontSize: '0.875rem',
                fontWeight: 700,
                color: '#000',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '0.5rem',
                boxShadow: '3px 3px 0 #000',
                transition: 'all 0.2s ease',
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.transform = 'translateY(-2px)';
                e.currentTarget.style.boxShadow = '4px 4px 0 #000';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.transform = 'translateY(0)';
                e.currentTarget.style.boxShadow = '3px 3px 0 #000';
              }}
            >
              <Icon type="download" color="#000" size={18} />
              Download
            </button>
            <button
              style={{
                flex: 1,
                background: 'transparent',
                border: '2px solid #fff',
                borderRadius: '12px',
                padding: '0.75rem',
                fontFamily: 'var(--font-body)',
                fontSize: '0.875rem',
                fontWeight: 700,
                color: '#fff',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '0.5rem',
                transition: 'all 0.2s ease',
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.background = 'rgba(255,255,255,0.1)';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.background = 'transparent';
              }}
            >
              <Icon type="share" color="#fff" size={18} />
              Share
            </button>
          </div>

          <p
            style={{
              fontFamily: 'var(--font-body)',
              fontSize: '0.65rem',
              color: 'rgba(255,255,255,0.5)',
              textAlign: 'center',
              marginTop: '0.75rem',
            }}
          >
            Privacy-first · No personal details shared
          </p>
        </div>
      </div>
    </div>
  );
}
