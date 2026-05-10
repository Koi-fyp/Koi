'use client';
import { useRef, useEffect, useState } from 'react';
import Link from 'next/link';

const VALUES = [
  { icon: '🤝', title: 'Radical Empathy',   desc: 'We build every feature by asking: would this make someone feel more heard or less? Empathy is not a feature — it is the foundation.' },
  { icon: '🔒', title: 'Privacy First',      desc: 'Your thoughts are yours. We designed KOI from day one to work without accounts, without data harvesting, without compromise.' },
  { icon: '🌍', title: 'Built for Pakistan', desc: 'Mental health support in Pakistan is scarce and stigmatised. KOI speaks Urdu, understands local context, and is free — always.' },
  { icon: '🧪', title: 'Honest Technology', desc: 'KOI is transparent about being an AI. We will never pretend otherwise. Trust is built through honesty, not illusion.' },
];

const TIMELINE = [
  { year: '2024',       label: 'The Idea',    desc: 'Born from a personal experience of loneliness — the realisation that sometimes you just need something to listen, at 2am, without judgment.' },
  { year: 'Early 2025', label: 'First Build', desc: 'A small team of two. The first working prototype with emotion detection and on-device encryption. Tested quietly with 50 users in Lahore.' },
  { year: 'Mid 2025',   label: 'Urdu Support',desc: "KOI learns to speak Urdu. The first AI companion that can hold a meaningful conversation in Pakistan's native tongue." },
  { year: 'Now',        label: 'Growing',     desc: 'Thousands of conversations. Constant iteration. A deepening belief that accessible mental health support can change lives.' },
];

export default function AboutPage() {
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
      { threshold: 0.12 }
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
              <Link href="/about" className="text-black border-b-2 border-black">About</Link>
              <Link href="/how-it-works" className="hover:text-black transition-colors">How It Works</Link>
            </div>
            <Link href="/" className="neo-btn-primary" style={{ fontSize: '0.875rem', padding: '0.5rem 1.25rem' }}>
              Start Talking →
            </Link>
          </div>
        </nav>

        {/* HERO */}
        <section className="pt-32 pb-16 px-6 lg:px-12 max-w-7xl mx-auto" style={{ background: 'transparent' }}>
          <div className="max-w-3xl">
            <span className="neo-tag mb-6 inline-flex">Our Story</span>
            <h1 className="neo-hero-text mt-4 mb-6">
              We built KOI<br />
              because we&nbsp;<span style={{ color: '#2D63EB' }}>needed</span><br />
              it ourselves.
            </h1>
            <p className="text-xl leading-relaxed max-w-2xl" style={{ color: '#4B5563', fontWeight: 500 }}>
              Loneliness is an epidemic. In Pakistan alone, millions navigate anxiety,
              grief, and disconnection with nowhere to turn. We decided to build something
              that could sit with you in those moments — quietly, privately, without judgment.
            </p>
          </div>
        </section>

        {/* MISSION BLOCK */}
        <section className="py-8 pb-16 px-6 lg:px-12 max-w-7xl mx-auto" style={{ background: 'transparent' }}>
          <div ref={(el) => r(el, 0)} className="reveal neo-card p-8 lg:p-14">
            <div className="flex flex-col lg:flex-row gap-10 lg:gap-20">
              <div className="flex-1">
                <p className="text-xs font-black tracking-widest uppercase text-black/40 mb-4">Our Mission</p>
                <h2 className="text-3xl lg:text-4xl font-black text-black leading-tight mb-6" style={{ letterSpacing: '-0.03em' }}>
                  Mental health support should be as accessible as a text message.
                </h2>
                <p className="text-base leading-relaxed text-black/60">
                  We are not building a product. We are building infrastructure for emotional wellbeing —
                  one conversation at a time. KOI exists to make that support available to anyone,
                  anywhere, in any language, at any hour.
                </p>
              </div>
              <div className="flex-1 flex flex-col gap-4">
                {[
                  ['🇵🇰', 'Made in Pakistan, for Pakistan'],
                  ['💬', '50,000+ conversations and counting'],
                  ['🔐', 'Zero data ever sold or shared'],
                  ['🌙', 'Available at 2am when you need it most'],
                ].map(([icon, text], i) => (
                  <div key={i} className="flex items-center gap-4 p-4 rounded-xl border-2 border-black/10 bg-black/[0.02]">
                    <span className="text-2xl">{icon}</span>
                    <span className="font-bold text-sm text-black">{text}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </section>

        {/* VALUES */}
        <section className="py-16 px-6 lg:px-12 bg-black">
          <div className="max-w-7xl mx-auto">
            <p className="text-xs font-black tracking-widest uppercase text-white/40 mb-4">What We Stand For</p>
            <h2 className="text-4xl lg:text-5xl font-black text-white leading-tight mb-14" style={{ letterSpacing: '-0.03em' }}>
              Our values aren't a poster.<br />
              <span style={{ color: '#FFD100' }}>They're the code.</span>
            </h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
              {VALUES.map((v, i) => (
                <div key={i} ref={(el) => r(el, i + 1)} className="reveal flex flex-col gap-4 p-8 rounded-2xl border-2 border-white/10 bg-white/5 hover:bg-white/10 transition-colors duration-200"
                  style={{ transitionDelay: `${i * 0.1}s` }}>
                  <span className="text-4xl">{v.icon}</span>
                  <h3 className="text-xl font-black text-white">{v.title}</h3>
                  <p className="text-sm leading-relaxed" style={{ color: '#9CA3AF' }}>{v.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>
        {/* ── TEAM CARDS ────────────────────────────────── */}
        <TeamCards />
        {/* TIMELINE */}
        <section className="py-16 lg:py-24 px-6 lg:px-12 max-w-4xl mx-auto" style={{ background: 'transparent' }}>
          <div ref={(el) => r(el, 6)} className="reveal">
            <p className="text-xs font-black tracking-widest uppercase text-black/40 mb-4">The Journey</p>
            <h2 className="text-4xl lg:text-5xl font-black text-black leading-tight mb-14" style={{ letterSpacing: '-0.03em' }}>
              How we got&nbsp;<span style={{ color: '#2D63EB' }}>here.</span>
            </h2>
          </div>

          <div className="relative">
            {/* Vertical line — checkered pattern style */}
            <div
              className="absolute top-0 bottom-0"
              style={{
                left: '22px',
                width: '6px',
                backgroundImage: `url('https://cdn.prod.website-files.com/6751cb4038c0fe8cf4ffdbce/67535c97de3e7d18ea93a32f_pattern.webp'), linear-gradient(180deg, #FF6B6B, #FF6B6B)`,
                backgroundSize: 'auto, auto',
                backgroundRepeat: 'repeat, repeat',
                borderRadius: '999px',
                border: '1.5px solid #000',
              }}
            />

            <div className="flex flex-col gap-0">
              {TIMELINE.map((item, i) => (
                <div key={i} ref={(el) => r(el, 7 + i)} className="reveal relative flex gap-8 pb-12"
                  style={{ transitionDelay: `${i * 0.15}s` }}>
                  {/* Dot */}
                  <div
                    className="relative z-10 flex-shrink-0 w-11 h-11 rounded-full border-2 border-black flex items-center justify-center font-black text-xs"
                    style={{
                      background: i === TIMELINE.length - 1 ? '#2D63EB' : '#FFD100',
                      color: i === TIMELINE.length - 1 ? '#fff' : '#000',
                      boxShadow: '3px 3px 0 #000',
                    }}
                  >
                    {i + 1}
                  </div>
                  {/* Content */}
                  <div className="flex-1 pt-1.5">
                    <div className="flex items-center gap-3 mb-2">
                      <span className="text-xs font-black tracking-widest uppercase text-black/40">{item.year}</span>
                      <span className="neo-tag" style={{ fontSize: '0.72rem', padding: '0.15rem 0.6rem' }}>{item.label}</span>
                    </div>
                    <p className="text-base leading-relaxed text-black/70 font-medium">{item.desc}</p>
                  </div>
                </div>
              ))}
            </div>
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
                <Link href="/how-it-works" className="hover:text-black transition-colors">How It Works</Link>
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
      function TeamCards() {
  const cardRefs = useRef<(HTMLDivElement | null)[]>([]);
  const [visible, setVisible] = useState<boolean[]>([false, false, false]);

  useEffect(() => {
    const observers: IntersectionObserver[] = [];
    cardRefs.current.forEach((el, i) => {
      if (!el) return;
      const obs = new IntersectionObserver(
        ([entry]) => {
          if (entry.isIntersecting) {
            setVisible((prev) => {
              const next = [...prev];
              next[i] = true;
              return next;
            });
            obs.disconnect();
          }
        },
        { threshold: 0.15 }
      );
      obs.observe(el);
      observers.push(obs);
    });
    return () => observers.forEach((o) => o.disconnect());
  }, []);

  const cardStyle = (i: number): React.CSSProperties => ({
    opacity: visible[i] ? 1 : 0,
    transform: visible[i] ? 'translateY(0)' : 'translateY(28px)',
    transition: `opacity 0.5s ease ${i * 0.12}s, transform 0.5s cubic-bezier(0.34,1.2,0.64,1) ${i * 0.12}s, box-shadow 0.25s cubic-bezier(0.34,1.56,0.64,1), scale 0.25s cubic-bezier(0.34,1.56,0.64,1)`,
  });

  const hoverStart = (e: React.MouseEvent<HTMLDivElement>) => {
    e.currentTarget.style.transform = 'translateY(-6px) scale(1.015)';
    e.currentTarget.style.boxShadow = '10px 12px 0 #000000cc';
  };

  const hoverEnd = (e: React.MouseEvent<HTMLDivElement>) => {
    e.currentTarget.style.transform = 'translateY(0) scale(1)';
    e.currentTarget.style.boxShadow = '6px 6px #000000ba';
  };

  return (
    <section className="team-section">
      <p className="text-xs font-black tracking-widest uppercase text-black/40 mb-4">The People</p>
      <h2
        className="text-4xl lg:text-5xl font-black text-black leading-tight mb-12"
        style={{ letterSpacing: '-0.03em' }}
      >
        Meet the&nbsp;<span style={{ color: '#2D63EB' }}>team.</span>
      </h2>

      <div className="team-grid">

        {/* ── Horizontal Card 1: Fatima ── */}
        <div
          ref={(el) => { cardRefs.current[0] = el; }}
          className="team-card-h"
          style={cardStyle(0)}
          onMouseEnter={hoverStart}
          onMouseLeave={hoverEnd}
        >
          <div className="team-card-img">
            <div style={{ position: 'relative', display: 'flex', gap: '10px', alignItems: 'flex-end' }}>
              <div className="phone-frame" style={{ transform: 'rotate(-6deg)', marginBottom: '10px' }}>
                <div className="phone-inner">
                  <div className="phone-line accent" />
                  <div className="phone-line" />
                  <div className="phone-line" style={{ width: '80%' }} />
                  <div className="phone-line" style={{ width: '50%' }} />
                </div>
              </div>
              <svg width="28" height="28" viewBox="0 0 28 28" fill="none" style={{ marginBottom: '18px', flexShrink: 0 }}>
                <path d="M4 22 C4 10, 16 4, 24 8" stroke="#000" strokeWidth="2.5" strokeLinecap="round" fill="none" />
                <path d="M20 6 L24 8 L21 12" stroke="#000" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
              </svg>
              <div className="phone-frame" style={{ transform: 'rotate(4deg)' }}>
                <div className="phone-inner">
                  <div className="phone-line" style={{ background: '#FFD100', width: '70%' }} />
                  <div className="phone-line accent" />
                  <div className="phone-line" style={{ width: '90%' }} />
                  <div className="phone-line" style={{ width: '40%' }} />
                </div>
              </div>
            </div>
          </div>
          <div className="team-card-text">
            <div className="team-avatar" style={{ background: '#FFD100' }}>FH</div>
            <div>
              <p className="font-black text-base" style={{ color: '#1d1d1d', fontFamily: 'var(--font-display)' }}>
                Fatima Hasan Gilani
              </p>
              <p className="text-xs font-semibold" style={{ color: '#2D63EB' }}>SP23-BSE-047</p>
            </div>
            <p className="text-sm font-semibold" style={{ color: '#626570', lineHeight: 1.5 }}>
              AI Engineer & Research
            </p>
            <p className="text-xs" style={{ color: '#626570', lineHeight: 1.5 }}>
              Leads model fine-tuning, emotion classification, and all things research.
            </p>
            <button className="team-btn">Learn more →</button>
          </div>
        </div>

        {/* ── Horizontal Card 2: Irsa ── */}
        <div
          ref={(el) => { cardRefs.current[1] = el; }}
          className="team-card-h"
          style={cardStyle(1)}
          onMouseEnter={hoverStart}
          onMouseLeave={hoverEnd}
        >
          <div className="team-card-img" style={{
            background: `url('https://static.vecteezy.com/system/resources/previews/045/828/666/non_2x/lotus-flower-in-grunge-style-with-a-grainy-photocopy-effect-an-element-of-halftone-strokes-in-the-gothic-style-illustration-vector.jpg'),
              radial-gradient(circle at 70% 30%, #fb923c55, transparent 55%),
              radial-gradient(circle at 20% 70%, #2DD36F33, transparent 50%),
              radial-gradient(circle at 50% 50%, #FFD10033, transparent 60%),
              #fef9ee`,
            backgroundSize: 'auto, cover, cover, cover, cover',
            backgroundRepeat: 'repeat, no-repeat, no-repeat, no-repeat, no-repeat',
          }}>
            <div style={{ position: 'relative', display: 'flex', gap: '10px', alignItems: 'flex-end' }}>
              <div className="phone-frame" style={{ transform: 'rotate(-4deg)', marginBottom: '8px' }}>
                <div className="phone-inner">
                  <div className="phone-line" style={{ background: '#2DD36F', width: '65%' }} />
                  <div className="phone-line" />
                  <div className="phone-line" style={{ width: '85%' }} />
                  <div className="phone-line" style={{ width: '45%' }} />
                </div>
              </div>
              <svg width="28" height="28" viewBox="0 0 28 28" fill="none" style={{ marginBottom: '16px', flexShrink: 0 }}>
                <path d="M4 22 C4 10, 16 4, 24 8" stroke="#000" strokeWidth="2.5" strokeLinecap="round" fill="none" />
                <path d="M20 6 L24 8 L21 12" stroke="#000" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
              </svg>
              <div className="phone-frame" style={{ transform: 'rotate(3deg)' }}>
                <div className="phone-inner">
                  <div className="phone-line" style={{ background: '#FF9F43', width: '75%' }} />
                  <div className="phone-line" style={{ background: '#2DD36F', width: '55%' }} />
                  <div className="phone-line" />
                  <div className="phone-line" style={{ width: '60%' }} />
                </div>
              </div>
            </div>
          </div>
          <div className="team-card-text">
            <div className="team-avatar" style={{ background: '#2DD36F' }}>IN</div>
            <div>
              <p className="font-black text-base" style={{ color: '#1d1d1d', fontFamily: 'var(--font-display)' }}>
                Irsa Noor
              </p>
              <p className="text-xs font-semibold" style={{ color: '#2D63EB' }}>SP23-BSE-063</p>
            </div>
            <p className="text-sm font-semibold" style={{ color: '#626570', lineHeight: 1.5 }}>
              Architecture & Solutions
            </p>
            <p className="text-xs" style={{ color: '#626570', lineHeight: 1.5 }}>
              Owns system design, data architecture, and solution scalability.
            </p>
            <button className="team-btn">Learn more →</button>
          </div>
        </div>

        {/* ── Vertical Card: Ahmad ── */}
        <div
          ref={(el) => { cardRefs.current[2] = el; }}
          className="team-card-v"
          style={cardStyle(2)}
          onMouseEnter={hoverStart}
          onMouseLeave={hoverEnd}
        >
          <div className="team-card-img" style={{
            background: `url('https://static.vecteezy.com/system/resources/previews/045/710/079/non_2x/roses-photocopy-effect-negative-elements-set-flower-heads-with-grunge-stippling-grain-messy-texture-trendy-y2k-aesthetic-illustration-ideal-for-poster-design-t-shirt-tee-print-sweatshirt-vector.jpg'),
              radial-gradient(circle at 40% 40%, #2D63EB44, transparent 55%),
              radial-gradient(circle at 80% 70%, #c084fc44, transparent 50%),
              radial-gradient(circle at 20% 80%, #fb923c33, transparent 45%),
              #eef2ff`,
            backgroundSize: 'auto, cover, cover, cover, cover',
            backgroundRepeat: 'repeat, no-repeat, no-repeat, no-repeat, no-repeat',
            minHeight: '220px',
          }}>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '12px' }}>
              <div className="team-avatar" style={{ background: '#2D63EB', color: '#fff', width: '88px', height: '88px', fontSize: '1.8rem' }}>AS</div>
              <div style={{ display: 'flex', gap: '8px', alignItems: 'flex-end' }}>
                <div className="phone-frame" style={{ transform: 'rotate(-5deg)', width: '42px', height: '72px' }}>
                  <div className="phone-inner">
                    <div className="phone-line accent" />
                    <div className="phone-line" />
                    <div className="phone-line" style={{ width: '70%' }} />
                  </div>
                </div>
                <svg width="22" height="22" viewBox="0 0 28 28" fill="none" style={{ marginBottom: '14px' }}>
                  <path d="M4 22 C4 10, 16 4, 24 8" stroke="#000" strokeWidth="2.5" strokeLinecap="round" fill="none" />
                  <path d="M20 6 L24 8 L21 12" stroke="#000" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
                </svg>
                <div className="phone-frame" style={{ transform: 'rotate(4deg)', width: '42px', height: '72px' }}>
                  <div className="phone-inner">
                    <div className="phone-line" style={{ background: '#FFD100', width: '80%' }} />
                    <div className="phone-line accent" />
                    <div className="phone-line" style={{ width: '50%' }} />
                  </div>
                </div>
              </div>
            </div>
          </div>
          <div className="team-card-text" style={{ justifyContent: 'flex-start', paddingTop: '2rem' }}>
            <div>
              <p className="font-black text-xl" style={{ color: '#1d1d1d', fontFamily: 'var(--font-display)', lineHeight: 1.2 }}>
                Ahmad Suleman
              </p>
              <p className="text-xs font-semibold mt-1" style={{ color: '#2D63EB' }}>SP23-BSE-002</p>
            </div>
            <p className="text-sm font-semibold mt-2" style={{ color: '#626570', lineHeight: 1.5 }}>
              Web Stack & Cloud
            </p>
            <p className="text-sm mt-1" style={{ color: '#626570', lineHeight: 1.6 }}>
              Builds and maintains the full-stack infrastructure — from Next.js frontend to Firebase cloud functions. Owns deployment, CI/CD, and performance.
            </p>
            <button className="team-btn" style={{ marginTop: '1rem' }}>Learn more →</button>
          </div>
        </div>

      </div>
    </section>
  );
}
}
