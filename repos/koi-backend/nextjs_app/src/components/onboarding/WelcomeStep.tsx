'use client';
import { useEffect, useCallback } from 'react';

interface Props {
  onNext: () => void;
}

export default function WelcomeStep({ onNext }: Props) {
  const stableOnNext = useCallback(onNext, []);

  useEffect(() => {
    const timer = setTimeout(stableOnNext, 2000);
    return () => clearTimeout(timer);
  }, [stableOnNext]);

  return (
    <div
      className="flex flex-col items-center justify-center flex-1 p-8 cursor-pointer select-none"
      onClick={onNext}
      role="button"
      aria-label="Continue to next screen"
    >
      <div className="mb-8 text-center">
        <div className="w-24 h-24 rounded-full bg-[#2E75B6] flex items-center justify-center mx-auto mb-4 shadow-lg">
          <span className="text-white text-5xl font-bold">K</span>
        </div>
        <h1 className="text-4xl font-bold text-[#2E75B6]">KOI</h1>
      </div>
      <p className="text-lg text-gray-600 text-center leading-relaxed max-w-xs">
        Your companion in moments of loneliness
      </p>
      <p className="text-sm text-gray-400 mt-10">Tap to continue</p>
    </div>
  );
}
