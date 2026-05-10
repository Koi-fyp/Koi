'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/contexts/AuthContext';
import { isOnboardingComplete } from '@/lib/onboarding';

const BLOCKS = [
  { bg: '#2D63EB', text: '#fff',    label: 'Think',   w: 'wide' },
  { bg: '#FFD100', text: '#000',    label: 'Feel',    w: 'narrow' },
  { bg: '#FF6B6B', text: '#fff',    label: 'Grow',    w: 'narrow' },
  { bg: '#0A0A0A', text: '#FFD100', label: 'Talk',    w: 'wide' },
  { bg: '#2DD36F', text: '#000',    label: 'Learn',   w: 'wide' },
  { bg: '#FF9F43', text: '#fff',    label: 'Rest',    w: 'narrow' },
  { bg: '#845EC2', text: '#fff',    label: 'Dream',   w: 'narrow' },
  { bg: '#F4F4F4', text: '#000',    label: 'Reflect', w: 'wide' },
  { bg: '#2D63EB', text: '#fff',    label: 'Connect', w: 'narrow' },
  { bg: '#FFD100', text: '#000',    label: 'Explore', w: 'wide' },
];

const FEATURES = [
  { icon: '🧠', title: 'Remembers You',    desc: 'Context-aware conversations that get better over time.' },
  { icon: '⚡', title: 'Instant Response', desc: 'Powered by cutting-edge AI — no waiting, ever.' },
  { icon: '🔒', title: 'Fully Private',    desc: 'Zero accounts, zero data storage. Your thoughts stay yours.' },
  { icon: '🎯', title: 'Always Present',   desc: 'Available 24/7, in your pocket, whenever you need.' },
];

const FAQS = [
  {
    q: 'Is KOI a replacement for therapy?',
    a: 'No. KOI is an AI companion designed for everyday emotional support, reflection, and connection — not clinical treatment. If you are experiencing a mental health crisis, please reach out to a qualified professional or a crisis helpline.',
  },
  {
    q: 'Do I need to create an account?',
    a: 'Not at all. KOI works instantly with an anonymous session. No email, no password, no friction. Your conversations are stored privately on your device.',
  },
  {
    q: 'How is my data kept private?',
    a: 'Your conversations are encrypted on your device using AES-256. We never sell your data, share it with advertisers, or store your real name. Your session ID is anonymous by design.',
  },
  {
    q: 'What languages does KOI support?',
    a: 'KOI currently supports English and Urdu, with more languages planned. You can choose your preferred language during onboarding.',
  },
  {
    q: 'How does KOI detect how I am feeling?',
    a: 'KOI uses a combination of natural language understanding and sentiment analysis to gently detect emotional tone in your messages. This helps KOI respond with more empathy and adjust its presence accordingly.',
  },
  {
    q: 'Can I use KOI during a crisis?',
    a: 'KOI includes crisis detection and will surface emergency helpline numbers if it senses you may be in distress. However, in an emergency always contact emergency services (15 / 1122) or Umang helpline at 0311-7786264 directly.',
  },
  {
    q: 'Is KOI available offline?',
    a: 'KOI stores your conversation history locally so you can read past messages offline. Sending new messages requires a connection, but any messages composed offline will be queued and sent automatically when you reconnect.',
  },
];

export default function RootPage() {
  const { user, loading, error, signInAnonymously } = useAuth();
  const router = useRouter();
  const [starting, setStarting] = useState(false);
  const [openFaq, setOpenFaq] = useState<number | null>(null);
  const [scrolled, setScrolled] = useState(false);
  const revealRefs = useRef<(HTMLElement | null)[]>([]);

  useEffect(() => {
    if (loading || !user) return;
    if (isOnboardingComplete()) {
      router.replace('/chat');
    } else {
      router.replace('/onboarding');
    }
  }, [user, loading, router]);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => entries.forEach((e) => e.isIntersecting && e.target.classList.add('visible')),
      { threshold: 0.12 }
    );
    revealRefs.current.forEach((el) => el && observer.observe(el));
    return () => observer.disconnect();
  }, []);

  const addReveal = (el: HTMLElement | null, i: number) => {
    revealRefs.current[i] = el;
  };

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
    <>
      <div className="grain" aria-hidden="true" />
      <div className="page-bg" aria-hidden="true" />

      <div className="min-h-screen font-inter overflow-x-hidden relative" style={{ background: 'transparent' }}>

        {/* ── NAV ───────────────────────────────────────── */}
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
            <div className="flex items-center gap-2.5">
              <div
                className="w-9 h-9 rounded-xl flex items-center justify-center text-lg font-black text-white border-2 border-black"
                style={{ background: '#2D63EB', boxShadow: '2px 2px 0 #000' }}
              >K</div>
              <span className="text-lg font-black tracking-tight text-black">KOI</span>
            </div>

            <div className="hidden md:flex items-center gap-8 text-sm font-semibold text-black/70">
              <a href="#features" className="hover:text-black transition-colors">Features</a>
              <a href="#faq" className="hover:text-black transition-colors">FAQ</a>
              <Link href="/about" className="hover:text-black transition-colors">About</Link>
              <Link href="/how-it-works" className="hover:text-black transition-colors">How It Works</Link>
            </div>

            <button
              onClick={handleGetStarted}
              disabled={isLoading}
              className="neo-btn-primary"
              style={{ fontSize: '0.875rem', padding: '0.5rem 1.25rem' }}
            >
              {isLoading ? (
                <span className="flex items-center gap-2">
                  <span className="inline-block w-3.5 h-3.5 rounded-full border-2 border-white border-t-transparent" style={{ animation: 'spin 0.7s linear infinite' }} />
                  Starting…
                </span>
              ) : <>Get Started →</>}
            </button>
          </div>
        </nav>

        {/* ── HERO ──────────────────────────────────────── */}
        <section
          className="pt-24 lg:pt-28 pb-16 lg:pb-24 px-6 lg:px-12 max-w-7xl mx-auto"
          style={{ background: 'transparent' }}
        >
          <div className="flex flex-col lg:flex-row items-center gap-12 lg:gap-16">
            <div className="flex-1 flex flex-col gap-6 lg:gap-8">
              <div className="hero-stagger-1">
                <span className="neo-tag">
                  <span className="w-2 h-2 rounded-full" style={{ background: '#2DD36F', display: 'inline-block', animation: 'pulseDot 2s infinite' }} />
                  AI Companion · Free to use
                </span>
              </div>

              <h1 className="neo-hero-text hero-stagger-2">
                Your&nbsp;<span style={{ color: '#2D63EB' }}>mind</span>
                <br />deserves a&nbsp;
                <span style={{ color: '#FFD100', WebkitTextStroke: '2px #000', display: 'inline-block' }}>friend.</span>
              </h1>

              <p className="hero-stagger-3 text-lg lg:text-xl leading-relaxed max-w-md" style={{ color: '#4B5563', fontWeight: 500 }}>
                KOI is a thoughtful AI companion that listens without judgment,
                remembers the details that matter, and grows with you — every single day.
              </p>

              <div className="hero-stagger-4 flex items-center gap-3">
                <div className="flex -space-x-2">
                  {['#FFD100', '#2D63EB', '#FF6B6B', '#2DD36F'].map((c, i) => (
                    <div key={i} className="w-8 h-8 rounded-full border-2 border-white flex items-center justify-center text-xs font-black text-white" style={{ background: c }}>
                      {['A', 'S', 'M', 'L'][i]}
                    </div>
                  ))}
                </div>
                <p className="text-sm font-medium" style={{ color: '#6B7280' }}>
                  <span className="font-black text-black">2,400+</span> people talking right now
                </p>
              </div>

              <div className="hero-stagger-5 flex flex-col sm:flex-row items-start sm:items-center gap-4">
                {error && !user ? (
                  <div className="flex flex-col gap-3">
                    <p className="text-sm font-semibold text-red-500">⚠ Connection failed. Check your network and try again.</p>
                    <button onClick={handleGetStarted} disabled={isLoading} className="neo-btn-primary">
                      {isLoading ? 'Connecting…' : 'Try Again'}
                    </button>
                  </div>
                ) : (
                  <>
                    <button onClick={handleGetStarted} disabled={isLoading} className="neo-btn-primary text-base">
                      {isLoading ? (
                        <span className="flex items-center gap-2">
                          <span className="inline-block w-4 h-4 rounded-full border-2 border-white border-t-transparent" style={{ animation: 'spin 0.7s linear infinite' }} />
                          Getting ready…
                        </span>
                      ) : "Start Talking — It's Free ✦"}
                    </button>
                    <span className="text-sm font-medium" style={{ color: '#9CA3AF' }}>No account · No credit card</span>
                  </>
                )}
              </div>
            </div>

            <div className="flex-1 w-full max-w-sm lg:max-w-md xl:max-w-lg">
              <ColorGrid />
            </div>
          </div>
        </section>

        {/* ── FEATURES ──────────────────────────────────── */}
        <section id="features" className="py-16 lg:py-24 px-6 lg:px-12 bg-black">
          <div className="max-w-7xl mx-auto">
            <p className="text-xs font-black tracking-widest uppercase text-white/40 mb-4">Why KOI</p>
            <h2 className="text-4xl lg:text-5xl font-black text-white leading-tight mb-14" style={{ letterSpacing: '-0.03em' }}>
              Built for real&nbsp;<span style={{ color: '#FFD100' }}>humans.</span>
            </h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
              {FEATURES.map((f, i) => (
                <div
                  key={i}
                  ref={(el) => addReveal(el, i)}
                  className="reveal flex flex-col gap-3 p-6 rounded-2xl border-2 border-white/10 bg-white/5 hover:bg-white/10 transition-colors duration-200"
                  style={{ transitionDelay: `${i * 0.1}s` }}
                >
                  <span className="text-3xl">{f.icon}</span>
                  <h3 className="text-lg font-black text-white leading-tight">{f.title}</h3>
                  <p className="text-sm leading-relaxed" style={{ color: '#9CA3AF' }}>{f.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── FAQ ───────────────────────────────────────── */}
        <section id="faq" className="py-16 lg:py-24 px-6 lg:px-12 max-w-4xl mx-auto" style={{ background: 'transparent' }}>
          <div ref={(el) => addReveal(el, 10)} className="reveal">
            <p className="text-xs font-black tracking-widest uppercase text-black/40 mb-4">Got Questions</p>
            <h2 className="text-4xl lg:text-5xl font-black text-black leading-tight mb-12" style={{ letterSpacing: '-0.03em' }}>
              Everything you&nbsp;<span style={{ color: '#2D63EB' }}>need to know.</span>
            </h2>

            <div className="faq-accordion">
              {FAQS.map((item, i) => (
                <div key={i} className="faq-item">
                  <div
                    className={`faq-question ${openFaq === i ? 'open' : ''}`}
                    onClick={() => setOpenFaq(openFaq === i ? null : i)}
                  >
                    <span>{item.q}</span>
                    <span className={`faq-icon ${openFaq === i ? 'open' : ''}`}>+</span>
                  </div>
                  <div className={`faq-answer ${openFaq === i ? 'open' : ''}`}>
                    {item.a}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── HOW IT WORKS CTA ──────────────────────────── */}
        <section className="py-8 pb-16 px-6 lg:px-12 max-w-7xl mx-auto" style={{ background: 'transparent' }}>
          <div
            ref={(el) => addReveal(el, 11)}
            className="reveal relative overflow-hidden rounded-3xl p-8 lg:p-14 border-2 border-black"
            style={{ background: '#0A0A0A', boxShadow: '8px 8px 0 #2D63EB' }}
          >
            <div className="absolute top-0 right-0 w-96 h-96 rounded-full pointer-events-none opacity-10"
              style={{ background: '#FFD100', transform: 'translate(30%, -30%)', filter: 'blur(60px)' }} />
            <div className="relative z-10 flex flex-col lg:flex-row items-start lg:items-center gap-8 lg:gap-12">
              <div className="flex-1">
                <p className="text-xs font-black tracking-widest uppercase text-white/40 mb-3">Under the hood</p>
                <h2 className="text-3xl lg:text-5xl font-black text-white leading-tight" style={{ letterSpacing: '-0.03em' }}>
                  Curious how KOI&nbsp;<span style={{ color: '#FFD100' }}>actually works?</span>
                </h2>
                <p className="mt-4 text-base lg:text-lg text-white/60 max-w-md leading-relaxed">
                  From emotion detection to on-device encryption — explore the philosophy and technology behind your AI companion.
                </p>
              </div>
              <div className="shrink-0">
                <Link
                  href="/how-it-works"
                  className="neo-btn-secondary"
                  style={{ fontSize: '1rem', padding: '1rem 2rem' }}
                >
                  How We Do It →
                </Link>
              </div>
            </div>
          </div>
        </section>

        {/* ── READY CTA ─────────────────────────────────── */}
        <section className="py-8 pb-16 px-6 lg:px-12 max-w-7xl mx-auto" style={{ background: 'transparent' }}>
          <div
            ref={(el) => addReveal(el, 12)}
            className="reveal relative overflow-hidden rounded-3xl p-8 lg:p-14 border-2 border-black"
            style={{ background: '#2D63EB', boxShadow: '8px 8px 0 #000' }}
          >
            <div className="absolute top-0 right-0 w-64 h-64 rounded-full pointer-events-none opacity-20"
              style={{ background: '#FFD100', transform: 'translate(30%, -30%)' }} />
            <div className="absolute bottom-0 left-0 w-48 h-48 rounded-full pointer-events-none opacity-10"
              style={{ background: '#fff', transform: 'translate(-30%, 30%)' }} />
            <div className="relative z-10 flex flex-col lg:flex-row items-start lg:items-center gap-8 lg:gap-12">
              <div className="flex-1">
                <p className="text-xs font-black tracking-widest uppercase text-white/60 mb-3">Start today</p>
                <h2 className="text-3xl lg:text-5xl font-black text-white leading-tight" style={{ letterSpacing: '-0.03em' }}>
                  Ready to feel&nbsp;<span style={{ color: '#FFD100' }}>heard?</span>
                </h2>
                <p className="mt-4 text-base lg:text-lg text-white/70 max-w-md leading-relaxed">
                  Jump in immediately — no sign-up, no friction. Your first conversation is one tap away.
                </p>
              </div>
              <div className="flex flex-col gap-4 items-start lg:items-end shrink-0">
                <button
                  onClick={handleGetStarted}
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
                      e.currentTarget.style.transform = 'translateY(-3px)';
                      e.currentTarget.style.boxShadow = '6px 7px 0 #000';
                    }
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.transform = 'translateY(0)';
                    e.currentTarget.style.boxShadow = '4px 4px 0 #000';
                  }}
                  onMouseDown={(e) => {
                    e.currentTarget.style.transform = 'translateY(2px)';
                    e.currentTarget.style.boxShadow = '2px 2px 0 #000';
                  }}
                  onMouseUp={(e) => {
                    e.currentTarget.style.transform = 'translateY(-3px)';
                    e.currentTarget.style.boxShadow = '6px 7px 0 #000';
                  }}
                >
                  {isLoading ? (
                    <><span className="inline-block w-4 h-4 rounded-full border-2 border-black border-t-transparent" style={{ animation: 'spin 0.7s linear infinite' }} />Getting ready…</>
                  ) : 'Talk to KOI ✦'}
                </button>
                <p className="text-xs font-semibold text-white/50">Private · No account · Always free</p>
              </div>
            </div>
          </div>
        </section>

        {/* ── FOOTER ────────────────────────────────────── */}
        <footer className="px-6 lg:px-12 pb-10 max-w-7xl mx-auto" style={{ background: 'transparent' }}>
          <div className="koi-footer-wrapper">
            <div className="flex flex-col sm:flex-row items-center justify-between gap-6">
              <div className="flex items-center gap-2">
                <div className="w-7 h-7 rounded-lg flex items-center justify-center text-sm font-black text-white"
                  style={{ background: '#2D63EB', border: '1.5px solid #000' }}>K</div>
                <span className="font-black text-sm text-black">KOI</span>
              </div>
              <div className="flex items-center gap-6 text-sm font-semibold text-black/60">
                <Link href="/about" className="hover:text-black transition-colors">About</Link>
                <Link href="/how-it-works" className="hover:text-black transition-colors">How It Works</Link>
                <a href="#faq" className="hover:text-black transition-colors">FAQ</a>
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
}

function ColorGrid() {
  return (
    <div className="relative w-full" style={{ padding: '1.5rem' }} aria-hidden="true">
      <div className="absolute inset-0 rounded-3xl opacity-10 pointer-events-none"
        style={{ background: '#2D63EB', filter: 'blur(60px)', transform: 'scale(1.1)' }} />
      <div className="relative grid grid-cols-3 gap-3">
        {BLOCKS.map((b, i) => (
          <div
            key={i}
            className={`color-block flex items-end p-3 ${b.w === 'wide' ? 'col-span-2' : 'col-span-1'}`}
            style={{ background: b.bg, color: b.text, height: i % 3 === 0 ? '110px' : i % 3 === 1 ? '90px' : '100px' }}
          >
            <span className="font-black text-xs uppercase tracking-widest opacity-80 select-none">{b.label}</span>
          </div>
        ))}
        <div className="absolute -top-4 -right-4 neo-card--yellow px-4 py-2 text-xs font-black tracking-tight rotate-6 z-10"
          style={{ boxShadow: '3px 3px 0 #000' }}>
          🐟 Meet KOI
        </div>
      </div>
      <div className="absolute -bottom-6 -left-4 neo-card px-4 py-3 z-10" style={{ minWidth: '170px' }}>
        <p className="text-2xl font-black text-black leading-none">∞</p>
        <p className="text-xs font-semibold mt-0.5" style={{ color: '#6B7280' }}>Conversations possible</p>
      </div>
    </div>
  );
}
