'use client';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/AuthContext';
import { useRef, useEffect, useState } from 'react';
import Link from 'next/link';

const PILLARS = [
  {
    number: '01',
    title: 'Your Companion',
    subtitle: 'What KOI is',
    color: '#FFD100',
    textColor: '#000',
    desc: 'KOI is an AI companion — not a therapist, not a chatbot, not a search engine. It is a presence. Designed to listen deeply, remember what matters to you, and respond with warmth and without judgment. Think of KOI as a thoughtful friend who is always available, never distracted, and genuinely interested in how you are doing.',
    points: [
      'Remembers context across your conversation',
      'Detects emotional tone and adapts its response',
      'Available in English and Urdu',
      'Designed specifically for Pakistani users',
    ],
  },
  {
    number: '02',
    title: 'The AI Behind It',
    subtitle: 'How it thinks',
    color: '#2D63EB',
    textColor: '#fff',
    desc: "KOI is powered by a large language model fine-tuned for empathetic conversation. Every response is shaped by emotional context — not just the literal words you type, but the sentiment underneath them. A built-in emotion classifier analyses each message for signals of happiness, sadness, anxiety, or calm, and adjusts KOI's tone accordingly.",
    points: [
      'Emotion classification: happy, sad, anxious, calm, neutral',
      'Context window of recent messages for continuity',
      'Crisis detection with automatic helpline surfacing',
      'Fallback responses when connectivity is lost',
    ],
  },
  {
    number: '03',
    title: 'Your Privacy',
    subtitle: 'How we protect you',
    color: '#0A0A0A',
    textColor: '#fff',
    desc: 'Every conversation you have with KOI is encrypted on your device using AES-256-GCM before it ever touches any server. Your encryption key lives only on your device. We cannot read your conversations. No one can. Your session is anonymous by default — no name, no email, no phone number required.',
    points: [
      'AES-256-GCM encryption, on-device key storage',
      'Anonymous sessions — no account required',
      'Offline-first: conversations stored in local IndexedDB',
      'Firestore sync is encrypted and opt-in',
    ],
  },
  {
    number: '04',
    title: 'The Experience',
    subtitle: 'What it feels like',
    color: '#2DD36F',
    textColor: '#000',
    desc: 'We obsessed over every detail of the KOI experience — the soft bounce of the avatar, the warm colour shifts when your mood changes, the gentle typing indicator. Every visual and interaction choice was made to create a sense of calm presence. KOI should feel less like an app and more like opening a door to a quiet room where you can think out loud.',
    points: [
      'Emotion-driven avatar with breathing + blinking animations',
      'Colour-tinted background that shifts with your mood',
      'Offline-aware UI with queued message delivery',
      'Smooth animations designed to reduce anxiety, not add to it',
    ],
  },
];

export default function HowItWorksPage() {
  const [scrolled, setScrolled] = useState(false);
  const revealRefs = useRef<(HTMLElement | null)[]>([]);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => entries.forEach((e) => e.isIntersecting && e.target.classList.add('visible')),
      { threshold: 0.1 }
    );
    revealRefs.current.forEach((el) => el && observer.observe(el));
    return () => observer.disconnect();
  }, []);

  const r = (el: HTMLElement | null, i: number) => { revealRefs.current[i] = el; };

  return (
    <>
      <div className="grain" aria-hidden="true" />
      <div className="page-bg" aria-hidden="true" />

      <div className="min-h-screen font-inter overflow-x-hidden relative" style={{ background: 'transparent' }}>

        {/* NAV */}
        <nav
          className="fixed top-0 left-0 right-0 z-50 backdrop-blur-md border-b-2 border-black transition-all duration-300"
          style={{
            background: scrolled ? 'rgba(255,255,255,0.97)' : 'rgba(255,255,255,0.75)',
            height: scrolled ? '52px' : '64px',
            boxShadow: scrolled ? '0 4px 0 0 #000' : 'none',
          }}
        >
          <div
            className="max-w-7xl mx-auto px-6 lg:px-12 flex items-center justify-between transition-all duration-300"
            style={{ height: scrolled ? '52px' : '64px' }}
          >
            <Link href="/" className="flex items-center gap-2.5">
              <div className="w-9 h-9 rounded-xl flex items-center justify-center text-lg font-black text-white border-2 border-black"
                style={{ background: '#2D63EB', boxShadow: '2px 2px 0 #000' }}>K</div>
              <span className="text-lg font-black tracking-tight text-black">KOI</span>
            </Link>
            <div className="hidden md:flex items-center gap-8 text-sm font-semibold text-black/70">
              <Link href="/#features" className="hover:text-black transition-colors">Features</Link>
              <Link href="/#faq" className="hover:text-black transition-colors">FAQ</Link>
              <Link href="/about" className="hover:text-black transition-colors">About</Link>
              <Link href="/how-it-works" className="text-black border-b-2 border-black">How It Works</Link>
            </div>
            <Link href="/" className="neo-btn-primary" style={{ fontSize: '0.875rem', padding: '0.5rem 1.25rem' }}>
              Start Talking →
            </Link>
          </div>
        </nav>

        {/* HERO */}
        <section className="pt-32 pb-16 px-6 lg:px-12 max-w-7xl mx-auto" style={{ background: 'transparent' }}>
          <div className="max-w-3xl">
            <span className="neo-tag mb-6 inline-flex">Under the Hood</span>
            <h1 className="neo-hero-text mt-4 mb-6">
              How KOI<br />
              <span style={{ color: '#2D63EB' }}>actually</span><br />
              works.
            </h1>
            <p className="text-xl leading-relaxed max-w-2xl" style={{ color: '#4B5563', fontWeight: 500 }}>
              No magic. No mystery. Here is exactly what KOI is, how it thinks, how it protects you,
              and what we obsessed over to make it feel the way it does.
            </p>
          </div>
        </section>

        {/* PILLARS */}
        <section className="pb-16 px-6 lg:px-12 max-w-7xl mx-auto" style={{ background: 'transparent' }}>
          <div className="flex flex-col gap-8">
            {PILLARS.map((pillar, i) => (
              <div
                key={i}
                ref={(el) => r(el, i)}
                className="reveal relative overflow-hidden rounded-3xl border-2 border-black p-8 lg:p-14"
                style={{ background: pillar.color, boxShadow: '6px 6px 0 #000', transitionDelay: `${i * 0.1}s` }}
              >
                {/* Big number watermark */}
                <div
                  className="absolute top-4 right-8 font-black select-none pointer-events-none"
                  style={{
                    fontSize: 'clamp(5rem, 15vw, 12rem)',
                    lineHeight: 1,
                    color: pillar.textColor === '#fff' ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.06)',
                    fontFamily: 'var(--font-display)',
                  }}
                >
                  {pillar.number}
                </div>

                <div className="relative z-10 flex flex-col lg:flex-row gap-10 lg:gap-20">
                  <div className="lg:w-80 shrink-0">
                    <p className="text-xs font-black tracking-widest uppercase mb-3"
                      style={{ color: pillar.textColor === '#fff' ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.4)' }}>
                      {pillar.subtitle}
                    </p>
                    <h2 className="text-3xl lg:text-4xl font-black leading-tight"
                      style={{ color: pillar.textColor, letterSpacing: '-0.03em' }}>
                      {pillar.title}
                    </h2>
                  </div>

                  <div className="flex-1 flex flex-col gap-6">
                    <p className="text-base leading-relaxed"
                      style={{ color: pillar.textColor === '#fff' ? 'rgba(255,255,255,0.7)' : 'rgba(0,0,0,0.65)', fontWeight: 500 }}>
                      {pillar.desc}
                    </p>
                    <ul className="flex flex-col gap-2.5">
                      {pillar.points.map((point, j) => (
                        <li key={j} className="flex items-start gap-3 text-sm font-semibold" style={{ color: pillar.textColor }}>
                          <span
                            className="mt-0.5 w-5 h-5 rounded-full border-2 flex items-center justify-center text-xs flex-shrink-0 font-black"
                            style={{
                              borderColor: pillar.textColor === '#fff' ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.3)',
                              color: pillar.textColor,
                            }}
                          >✓</span>
                          {point}
                        </li>
                      ))}
                    </ul>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* CLOSING CTA */}
        <section className="py-8 pb-16 px-6 lg:px-12 max-w-7xl mx-auto" style={{ background: 'transparent' }}>
          <div ref={(el) => r(el, 10)} className="reveal neo-card p-8 lg:p-14 text-center">
            <p className="text-xs font-black tracking-widest uppercase text-black/40 mb-4">Ready?</p>
            <h2 className="text-3xl lg:text-5xl font-black text-black leading-tight mb-6" style={{ letterSpacing: '-0.03em' }}>
              Now you know how it works.<br />
              <span style={{ color: '#2D63EB' }}>Come say hello.</span>
            </h2>
            <p className="text-base text-black/50 max-w-lg mx-auto mb-8">
              No account, no credit card. Just you and KOI.
            </p>
            <StartButton/>
          </div>
        </section>

        {/* FOOTER */}
        <footer className="px-6 lg:px-12 pb-10 max-w-7xl mx-auto" style={{ background: 'transparent' }}>
          <div className="koi-footer-wrapper">
            <div className="flex flex-col sm:flex-row items-center justify-between gap-6">
              <Link href="/" className="flex items-center gap-2">
                <div className="w-7 h-7 rounded-lg flex items-center justify-center text-sm font-black text-white"
                  style={{ background: '#2D63EB', border: '1.5px solid #000' }}>K</div>
                <span className="font-black text-sm text-black">KOI</span>
              </Link>
              <div className="flex items-center gap-6 text-sm font-semibold text-black/60">
                <Link href="/" className="hover:text-black transition-colors">Home</Link>
                <Link href="/about" className="hover:text-black transition-colors">About</Link>
                <Link href="/#faq" className="hover:text-black transition-colors">FAQ</Link>
              </div>
              <p className="text-xs font-medium" style={{ color: '#9CA3AF' }}>Private · No account needed · Always here for you</p>
            </div>
            <div className="mt-6 pt-6 border-t-2 border-black/10 flex flex-col sm:flex-row items-center justify-between gap-2">
              <p className="text-xs font-semibold text-black/40">© 2025 KOI · All rights reserved</p>
              <p className="text-xs text-black/30">Built with care in Pakistan 🇵🇰</p>
            </div>
          </div>
        </footer>

      </div>
    </>
  );
  function StartButton() {
  const router = useRouter();
  const { signInAnonymously } = useAuth();
  const [loading, setLoading] = useState(false);

  const handle = async () => {
    setLoading(true);
    try {
      await signInAnonymously();
      router.replace('/onboarding');
    } catch {
      setLoading(false);
    }
  };

  return (
    <button
      onClick={handle}
      disabled={loading}
      className="neo-btn-primary"
      style={{ fontSize: '1rem', padding: '1rem 2.5rem' }}
    >
      {loading ? (
        <span className="flex items-center gap-2">
          <span className="inline-block w-4 h-4 rounded-full border-2 border-white border-t-transparent" style={{ animation: 'spin 0.7s linear infinite' }} />
          Getting ready…
        </span>
      ) : "Start Talking — It's Free ✦"}
    </button>
  );
}
}
