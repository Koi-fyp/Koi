'use client';

import React from 'react';

export default function HeroText() {
  return (
    <div className="max-w-3xl text-center sm:text-left">
      <h1 className="text-4xl sm:text-5xl xl:text-6xl font-black tracking-tighter leading-tight text-black">
        I&apos;m <span className="bg-[#3B82F6] text-white px-3 py-1 inline-block">Koi</span>, How can I{' '}
        <span className="bg-[#FF4A60] text-white px-3 py-1 inline-block">Help You</span>?
      </h1>
      <p className="mt-5 max-w-2xl text-base sm:text-lg leading-relaxed text-[#393939]">
        A calm place to think out loud, sort through what&apos;s heavy, and get a reply that actually feels present.
      </p>
    </div>
  );
}
