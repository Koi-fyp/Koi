'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/AuthContext';
import { isOnboardingComplete } from '@/lib/onboarding';

/* ── Colour Grid Data ──────────────────────────────────── */
const BLOCKS = [
  // Row 1
  { bg: '#2D63EB', text: '#fff',     label: 'Think',    w: 'wide' },
  { bg: '#FFD100', text: '#000',     label: 'Feel',     w: 'narrow' },
  // Row 2
  { bg: '#FF6B6B', text: '#fff',     label: 'Grow',     w: 'narrow' },
  { bg: '#0A0A0A', text: '#FFD100',  label: 'Talk',     w: 'wide' },
  // Row 3
  { bg: '#2DD36F', text: '#000',     label: 'Learn',    w: 'wide' },
  { bg: '#FF9F43', text: '#fff',     label: 'Rest',     w: 'narrow' },
  // Row 4
  { bg: '#845EC2', text: '#fff',     label: 'Dream',    w: 'narrow' },
  { bg: '#F4F4F4', text: '#000',     label: 'Reflect',  w: 'wide' },
  // Row 5
  { bg: '#2D63EB', text: '#fff',     label: 'Connect',  w: 'narrow' },
  { bg: '#FFD100', text: '#000',     label: 'Explore',  w: 'wide' },
];

const FEATURES = [
  { icon: '🧠', title: 'Remembers You', desc: 'Context-aware conversations that get better over time.' },
  { icon: '⚡', title: 'Instant Response', desc: 'Powered by cutting-edge AI — no waiting, ever.' },
  { icon: '🔒', title: 'Fully Private', desc: 'Zero accounts, zero data storage. Your thoughts stay yours.' },
  { icon: '🎯', title: 'Always Present', desc: 'Available 24/7, in your pocket, whenever you need.' },
];

/* ── Component ─────────────────────────────────────────── */
export default function RootPage() {
  const { user, loading, error, signInAnonymously } = useAuth();
  const router = useRouter();
  const [starting, setStarting] = useState(false);

  useEffect(() => {
    if (loading || !user) return;
    if (isOnboardingComplete()) {
      router.replace('/chat');
    } else {
      router.replace('/onboarding');
    }
  }, [user, loading, router]);

  const handleGetStarted = useCallback(async () => {
    setStarting(true);
    try {
      await signInAnonymously();
    } catch {
      setStarting(false);
    }
  }, [signInAnonymously]);

  const isLoading = starting || loading;

  return (
    <div className="min-h-screen bg-white font-inter overflow-x-hidden">

      {/* ── NAV ─────────────────────────────────────────── */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-white/90 backdrop-blur-md border-b-2 border-black">
        <div className="max-w-7xl mx-auto px-6 lg:px-12 flex items-center justify-between h-16">
          {/* Logo */}
          <div className="flex items-center gap-2.5">
            <div
              className="w-9 h-9 rounded-xl flex items-center justify-center text-lg font-black text-white border-2 border-black"
              style={{ background: '#2D63EB', boxShadow: '2px 2px 0 #000' }}
            >
              K
            </div>
            <span className="text-lg font-black tracking-tight text-black">KOI</span>
          </div>

          {/* Nav Links — desktop */}
          <div className="hidden md:flex items-center gap-8 text-sm font-semibold text-black/70">
            <a href="#features" className="hover:text-black transition-colors">Features</a>
            <a href="#about" className="hover:text-black transition-colors">About</a>
            <a href="#privacy" className="hover:text-black transition-colors">Privacy</a>
          </div>

          {/* CTA */}
          <button
            id="nav-get-started"
            onClick={handleGetStarted}
            disabled={isLoading}
            className="neo-btn-primary text-sm px-5 py-2.5"
            style={{ fontSize: '0.875rem', padding: '0.5rem 1.25rem' }}
          >
            {isLoading ? (
              <span className="flex items-center gap-2">
                <span
                  className="inline-block w-3.5 h-3.5 rounded-full border-2 border-white border-t-transparent"
                  style={{ animation: 'spin 0.7s linear infinite' }}
                />
                Starting…
              </span>
            ) : (
              <>Get Started →</>
            )}
          </button>
        </div>
      </nav>

      {/* ── HERO ────────────────────────────────────────── */}
      <section className="pt-24 lg:pt-28 pb-16 lg:pb-24 px-6 lg:px-12 max-w-7xl mx-auto">
        <div className="flex flex-col lg:flex-row items-center gap-12 lg:gap-16">

          {/* Left — Heavy Typography */}
          <div className="flex-1 flex flex-col gap-6 lg:gap-8">

            {/* Badge */}
            <div className="hero-stagger-1">
              <span className="neo-tag">
                <span
                  className="w-2 h-2 rounded-full animate-pulse-dot"
                  style={{ background: '#2DD36F', display: 'inline-block' }}
                />
                AI Companion · Free to use
              </span>
            </div>

            {/* Hero Headline */}
            <h1 className="neo-hero-text hero-stagger-2">
              Your&nbsp;
              <span style={{ color: '#2D63EB' }}>mind</span>
              <br />
              deserves a&nbsp;
              <span
                style={{
                  color: '#FFD100',
                  WebkitTextStroke: '2px #000',
                  display: 'inline-block',
                }}
              >
                friend.
              </span>
            </h1>

            {/* Sub-headline */}
            <p
              className="hero-stagger-3 text-lg lg:text-xl leading-relaxed max-w-md"
              style={{ color: '#4B5563', fontWeight: 500 }}
            >
              KOI is a thoughtful AI companion that listens without judgment,
              remembers the details that matter, and grows with you — every single day.
            </p>

            {/* Social proof */}
            <div className="hero-stagger-4 flex items-center gap-3">
              <div className="flex -space-x-2">
                {['#FFD100', '#2D63EB', '#FF6B6B', '#2DD36F'].map((c, i) => (
                  <div
                    key={i}
                    className="w-8 h-8 rounded-full border-2 border-white flex items-center justify-center text-xs font-black text-white"
                    style={{ background: c }}
                  >
                    {['A', 'S', 'M', 'L'][i]}
                  </div>
                ))}
              </div>
              <p className="text-sm font-medium" style={{ color: '#6B7280' }}>
                <span className="font-black text-black">2,400+</span> people talking right now
              </p>
            </div>

            {/* CTAs */}
            <div className="hero-stagger-5 flex flex-col sm:flex-row items-start sm:items-center gap-4">
              {error && !user ? (
                <div className="flex flex-col gap-3">
                  <p className="text-sm font-semibold text-red-500">
                    ⚠ Connection failed. Check your network and try again.
                  </p>
                  <button
                    id="hero-try-again"
                    onClick={handleGetStarted}
                    disabled={isLoading}
                    className="neo-btn-primary"
                  >
                    {isLoading ? 'Connecting…' : 'Try Again'}
                  </button>
                </div>
              ) : (
                <>
                  <button
                    id="hero-get-started"
                    onClick={handleGetStarted}
                    disabled={isLoading}
                    className="neo-btn-primary text-base"
                  >
                    {isLoading ? (
                      <span className="flex items-center gap-2">
                        <span
                          className="inline-block w-4 h-4 rounded-full border-2 border-white border-t-transparent"
                          style={{ animation: 'spin 0.7s linear infinite' }}
                        />
                        Getting ready…
                      </span>
                    ) : (
                      'Start Talking — It\'s Free ✦'
                    )}
                  </button>
                  <span className="text-sm font-medium" style={{ color: '#9CA3AF' }}>
                    No account · No credit card
                  </span>
                </>
              )}
            </div>
          </div>

          {/* Right — Colour Block Grid */}
          <div className="flex-1 w-full max-w-sm lg:max-w-md xl:max-w-lg">
            <ColorGrid />
          </div>
        </div>
      </section>

      {/* ── FEATURES ────────────────────────────────────── */}
      <section id="features" className="py-16 lg:py-24 px-6 lg:px-12 bg-black">
        <div className="max-w-7xl mx-auto">
          <p className="text-xs font-black tracking-widest uppercase text-white/40 mb-4">
            Why KOI
          </p>
          <h2
            className="text-4xl lg:text-5xl font-black text-white leading-tight mb-14"
            style={{ letterSpacing: '-0.03em' }}
          >
            Built for real&nbsp;
            <span style={{ color: '#FFD100' }}>humans.</span>
          </h2>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
            {FEATURES.map((f, i) => (
              <FeatureCard key={i} feature={f} delay={i * 0.1} />
            ))}
          </div>
        </div>
      </section>

      {/* ── CTA CARD ────────────────────────────────────── */}
      <section id="about" className="py-16 lg:py-24 px-6 lg:px-12 max-w-7xl mx-auto">
        <CTACard onStart={handleGetStarted} isLoading={isLoading} />
      </section>

      {/* ── FOOTER ──────────────────────────────────────── */}
      <footer
        id="privacy"
        className="border-t-2 border-black py-8 px-6 lg:px-12"
      >
        <div className="max-w-7xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <div
              className="w-7 h-7 rounded-lg flex items-center justify-center text-sm font-black text-white"
              style={{ background: '#2D63EB', border: '1.5px solid #000' }}
            >
              K
            </div>
            <span className="font-black text-sm text-black">KOI</span>
          </div>
          <p className="text-xs font-medium" style={{ color: '#9CA3AF' }}>
            Private · No account needed · Always here for you
          </p>
          <p className="text-xs font-semibold text-black/40">
            © 2025 KOI · All rights reserved
          </p>
        </div>
      </footer>
    </div>
  );
}

/* ── Sub-Components ──────────────────────────────────────── */

function ColorGrid() {
  return (
    <div
      className="relative w-full"
      style={{ padding: '1.5rem' }}
      aria-hidden="true"
    >
      {/* Decorative background blob */}
      <div
        className="absolute inset-0 rounded-3xl opacity-10 pointer-events-none"
        style={{ background: '#2D63EB', filter: 'blur(60px)', transform: 'scale(1.1)' }}
      />

      {/* Grid of blocks */}
      <div className="relative grid grid-cols-3 gap-3">
        {BLOCKS.map((b, i) => (
          <div
            key={i}
            className={`color-block flex items-end p-3 ${b.w === 'wide' ? 'col-span-2' : 'col-span-1'}`}
            style={{
              background: b.bg,
              color: b.text,
              height: i % 3 === 0 ? '110px' : i % 3 === 1 ? '90px' : '100px',
            }}
          >
            <span
              className="font-black text-xs uppercase tracking-widest opacity-80 select-none"
            >
              {b.label}
            </span>
          </div>
        ))}

        {/* Floating badge on top of grid */}
        <div
          className="absolute -top-4 -right-4 neo-card-yellow px-4 py-2 text-xs font-black tracking-tight rotate-6 z-10"
          style={{ boxShadow: '3px 3px 0 #000' }}
        >
          🐟 Meet KOI
        </div>
      </div>

      {/* Floating stats card */}
      <div
        className="absolute -bottom-6 -left-4 neo-card px-4 py-3 z-10"
        style={{ minWidth: '170px' }}
      >
        <p className="text-2xl font-black text-black leading-none">∞</p>
        <p className="text-xs font-semibold mt-0.5" style={{ color: '#6B7280' }}>
          Conversations possible
        </p>
      </div>
    </div>
  );
}

function FeatureCard({
  feature,
  delay,
}: {
  feature: { icon: string; title: string; desc: string };
  delay: number;
}) {
  return (
    <div
      className="flex flex-col gap-3 p-6 rounded-2xl border-2 border-white/10 bg-white/5 hover:bg-white/10 transition-colors duration-200"
      style={{ animationDelay: `${delay}s` }}
    >
      <span className="text-3xl">{feature.icon}</span>
      <h3 className="text-lg font-black text-white leading-tight">{feature.title}</h3>
      <p className="text-sm leading-relaxed" style={{ color: '#9CA3AF' }}>
        {feature.desc}
      </p>
    </div>
  );
}

function CTACard({
  onStart,
  isLoading,
}: {
  onStart: () => void;
  isLoading: boolean;
}) {
  return (
    <div
      className="relative overflow-hidden rounded-3xl p-8 lg:p-14 border-2 border-black"
      style={{
        background: '#2D63EB',
        boxShadow: '8px 8px 0 #000',
      }}
    >
      {/* Background decoration */}
      <div
        className="absolute top-0 right-0 w-64 h-64 rounded-full pointer-events-none opacity-20"
        style={{ background: '#FFD100', transform: 'translate(30%, -30%)' }}
      />
      <div
        className="absolute bottom-0 left-0 w-48 h-48 rounded-full pointer-events-none opacity-10"
        style={{ background: '#fff', transform: 'translate(-30%, 30%)' }}
      />

      <div className="relative z-10 flex flex-col lg:flex-row items-start lg:items-center gap-8 lg:gap-12">
        <div className="flex-1">
          <p className="text-xs font-black tracking-widest uppercase text-white/60 mb-3">
            Start today
          </p>
          <h2
            className="text-3xl lg:text-5xl font-black text-white leading-tight"
            style={{ letterSpacing: '-0.03em' }}
          >
            Ready to feel{' '}
            <span style={{ color: '#FFD100' }}>heard?</span>
          </h2>
          <p className="mt-4 text-base lg:text-lg text-white/70 max-w-md leading-relaxed">
            Jump in immediately — no sign-up, no friction.
            Your first conversation is one tap away.
          </p>
        </div>

        <div className="flex flex-col gap-4 items-start lg:items-end shrink-0">
          <button
            id="cta-get-started"
            onClick={onStart}
            disabled={isLoading}
            style={{
              background: '#FFD100',
              color: '#000',
              fontWeight: 800,
              fontSize: '1rem',
              borderRadius: '9999px',
              padding: '1rem 2rem',
              border: '2.5px solid #000',
              boxShadow: '4px 4px 0 #000',
              cursor: isLoading ? 'not-allowed' : 'pointer',
              opacity: isLoading ? 0.7 : 1,
              transition: 'transform 0.12s ease, box-shadow 0.12s ease',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.5rem',
              whiteSpace: 'nowrap',
            }}
            onMouseEnter={(e) => {
              if (!isLoading) {
                (e.currentTarget as HTMLButtonElement).style.transform = 'translateY(-2px)';
                (e.currentTarget as HTMLButtonElement).style.boxShadow = '4px 6px 0 #000';
              }
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLButtonElement).style.transform = '';
              (e.currentTarget as HTMLButtonElement).style.boxShadow = '4px 4px 0 #000';
            }}
          >
            {isLoading ? (
              <>
                <span
                  className="inline-block w-4 h-4 rounded-full border-2 border-black border-t-transparent"
                  style={{ animation: 'spin 0.7s linear infinite' }}
                />
                Getting ready…
              </>
            ) : (
              'Talk to KOI ✦'
            )}
          </button>
          <p className="text-xs font-semibold text-white/50">
            Private · No account · Always free
          </p>
        </div>
      </div>
    </div>
  );
}
