'use client';
import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';

const OPTIONS = [
  { key: 'text', label: 'Text', disabled: false },
  { key: 'audio', label: 'Audio', disabled: true },
  { key: 'video_text', label: 'Video + Text', disabled: true },
  { key: 'video_audio', label: 'Video + Audio', disabled: true },
];

export default function ChangeModeDropdown() {
  const [open, setOpen] = useState(false);
  const [selected, setSelected] = useState('text');

  return (
    <div className="relative inline-block">
      <motion.button
        onMouseEnter={() => setOpen(true)}
        onMouseLeave={() => setOpen(false)}
        onClick={() => setOpen((s) => !s)}
        whileHover={{ translateX: 2, translateY: 2, boxShadow: '2px 2px 0px 0px rgba(0,0,0,1)' }}
        whileTap={{ translateX: 5, translateY: 5, boxShadow: '0px 0px 0px 0px rgba(0,0,0,0)' }}
        className="bg-white neo-brutalist border-[3px] border-black px-4 py-2 font-bold"
      >
        Change Mode ▼
      </motion.button>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: -8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.18 }}
            onMouseEnter={() => setOpen(true)}
            onMouseLeave={() => setOpen(false)}
            className="absolute left-0 mt-2 w-56 bg-white neo-brutalist border-[3px] border-black"
          >
            <div className="flex flex-col p-2">
              {OPTIONS.map((opt) => (
                <div
                  key={opt.key}
                  onClick={() => { if (!opt.disabled) setSelected(opt.key); }}
                  className={`p-2 rounded-md mb-1 flex items-center justify-between ${opt.disabled ? 'opacity-60 cursor-not-allowed locked-stripes' : 'cursor-pointer hover:bg-slate-900 hover:text-white'}`}
                >
                  <div className="flex items-center gap-2">
                    <div className={`w-3 h-3 rounded-sm ${selected === opt.key ? 'bg-[#3B82F6]' : 'bg-gray-300'}`} />
                    <div className="text-sm">{opt.label}{opt.disabled ? '' : ' (Active)'}</div>
                  </div>
                  {opt.disabled && <div className="beta-badge">BETA</div>}
                </div>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
