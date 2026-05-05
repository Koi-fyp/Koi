'use client';
import { useState } from 'react';

interface Props {
  onNext: () => void;
}

export default function AIDisclosureStep({ onNext }: Props) {
  const [checkedAI, setCheckedAI] = useState(false);
  const [checkedPrivacy, setCheckedPrivacy] = useState(false);

  return (
    <div className="flex flex-col flex-1 p-6">
      <div className="flex-1 overflow-y-auto">
        <h2 className="text-2xl font-bold text-gray-900 mb-4">Important Notice</h2>

        <div className="bg-amber-50 border border-amber-200 rounded-xl p-4 mb-4">
          <div className="flex items-start gap-2">
            <span className="text-amber-500 text-xl shrink-0">⚠</span>
            <div>
              <p className="font-semibold text-amber-800 text-sm">KOI is an AI, not a therapist</p>
              <p className="text-sm text-amber-700 mt-1">
                KOI cannot diagnose mental health conditions and is not a substitute for
                professional care. In an emergency, contact emergency services immediately.
              </p>
            </div>
          </div>
        </div>

        <div className="bg-red-50 border border-red-200 rounded-xl p-4 mb-6">
          <p className="font-semibold text-red-700 mb-3 text-sm">Crisis Helplines (Pakistan)</p>
          <div className="space-y-2">
            <div className="flex justify-between items-center">
              <span className="text-sm text-gray-700">Umang (Mental Health)</span>
              <a href="tel:03117786264" className="font-mono font-semibold text-red-600 text-sm">
                0311-7786264
              </a>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm text-gray-700">Rozan Counselling</span>
              <a href="tel:080022444" className="font-mono font-semibold text-red-600 text-sm">
                0800-22444
              </a>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm text-gray-700">Emergency Services</span>
              <a href="tel:15" className="font-mono font-semibold text-red-600 text-sm">
                15 / 1122
              </a>
            </div>
          </div>
        </div>

        <div className="space-y-4">
          <label className="flex items-start gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={checkedAI}
              onChange={(e) => setCheckedAI(e.target.checked)}
              className="mt-0.5 w-5 h-5 accent-[#2E75B6] shrink-0"
            />
            I understand KOI is an AI, not a therapist
          </label>

          <label className="flex items-start gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={checkedPrivacy}
              onChange={(e) => setCheckedPrivacy(e.target.checked)}
              className="mt-0.5 w-5 h-5 accent-[#2E75B6] shrink-0"
            />
            I agree to Privacy Policy and Terms of Service
          </label>
        </div>
      </div>

      <button
        onClick={onNext}
        disabled={!checkedAI || !checkedPrivacy}
        className="w-full py-3 bg-[#2E75B6] text-white rounded-xl font-semibold text-lg mt-6 disabled:opacity-40 disabled:cursor-not-allowed"
      >
        I Agree
      </button>
    </div>
  );
}
