'use client';
import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { INPUT_MODES, modeLabel, useInputMode } from '@/contexts/InputModeContext';

export default function ModeSelector() {
  const [open, setOpen] = useState(false);
  const { mode, setMode } = useInputMode();
  const selected = modeLabel(mode);

  return (
    // Click toggles; leaving the whole control closes. (Hover-to-open fought the click: a mouse click reopened-then-closed it.)
    <div className="relative group flex-shrink-0" onMouseLeave={() => setOpen(false)}>
      <motion.button
        type="button" aria-expanded={open} aria-controls="koi-mode-options"
        onClick={() => setOpen(value => !value)}
        onKeyDown={event => { if (event.key === "Escape") setOpen(false); }}
        aria-label={`Mode: ${selected}`}
        whileHover={{ x: 2, y: 2, boxShadow: '2px 2px 0 0 rgba(0,0,0,1)' }}
        whileTap={{ x: 5, y: 5, boxShadow: '0 0 0 0 rgba(0,0,0,0)' }}
        className="flex items-center gap-1 sm:gap-2 px-1.5 sm:px-3 py-1 min-h-[44px] border-[2px] border-black rounded-full hover:translate-x-0.5 hover:translate-y-0.5 transition-all font-bold text-xs sm:text-sm"
      >
        <span><span className="hidden sm:inline">Mode: </span>{selected}</span>
        <svg
          width="14"
          height="14"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2.5"
          className="transition-transform"
        >
          <polyline points="6 9 12 15 18 9" />
        </svg>
      </motion.button>

      <AnimatePresence>
        {open && (
          <motion.div
            id="koi-mode-options"
            onKeyDown={event => { if (event.key === "Escape") setOpen(false); }}
            initial={{ y: -10, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: -8, opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="absolute top-full right-0 mt-2 w-64 bg-white border-[3px] border-black rounded-2xl shadow-[5px_5px_0px_0px_rgba(0,0,0,1)] overflow-hidden z-50"
          >
            <div className="flex flex-col p-2">
              {INPUT_MODES.map((item, idx) => (
                <div key={item.id}>
                  <motion.button type="button" aria-pressed={item.id === mode}
                    onClick={() => { setMode(item.id); setOpen(false); }}
                    whileHover={{ backgroundColor: '#06b6d4' }}
                    className={`w-full p-3 rounded-lg flex flex-col items-start text-left font-bold text-sm transition-all cursor-pointer hover:text-black text-black ${
                      item.id === mode ? 'bg-slate-200' : ''
                    }`}
                  >
                    <span>{item.label}</span>
                    <span className="text-xs font-normal text-gray-600">{item.hint}</span>
                  </motion.button>
                  {idx < INPUT_MODES.length - 1 && (
                    <div className="h-px bg-gray-300 my-1" />
                  )}
                </div>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
