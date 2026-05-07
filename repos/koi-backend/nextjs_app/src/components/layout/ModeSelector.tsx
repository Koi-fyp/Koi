'use client';
import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';

const modes = [
  { name: 'Text', status: 'Active', enabled: true },
  { name: 'Audio', status: 'BETA', enabled: false },
  { name: 'Video + Text', status: 'BETA', enabled: false },
  { name: 'Video + Audio', status: 'BETA', enabled: false },
];

export default function ModeSelector() {
  const [open, setOpen] = useState(false);
  const [selected, setSelected] = useState('Text');

  return (
    <div className="relative group flex-shrink-0">
      <motion.button
        onMouseEnter={() => setOpen(true)}
        onMouseLeave={() => setOpen(false)}
        whileHover={{ x: 2, y: 2, boxShadow: '2px 2px 0 0 rgba(0,0,0,1)' }}
        whileTap={{ x: 5, y: 5, boxShadow: '0 0 0 0 rgba(0,0,0,0)' }}
        className="flex items-center gap-2 px-3 py-1 border-[2px] border-black rounded-full hover:translate-x-0.5 hover:translate-y-0.5 transition-all font-bold text-sm"
      >
        <span>Mode: {selected}</span>
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
            initial={{ y: -10, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: -8, opacity: 0 }}
            transition={{ duration: 0.2 }}
            onMouseEnter={() => setOpen(true)}
            onMouseLeave={() => setOpen(false)}
            className="absolute top-full right-0 mt-2 w-56 bg-white border-[3px] border-black rounded-2xl shadow-[5px_5px_0px_0px_rgba(0,0,0,1)] overflow-hidden z-50"
          >
            <div className="flex flex-col p-2">
              {modes.map((mode, idx) => (
                <div key={mode.name}>
                  <motion.div
                    onClick={() => {
                      if (mode.enabled) {
                        setSelected(mode.name);
                        setOpen(false);
                      }
                    }}
                    whileHover={mode.enabled ? { backgroundColor: '#06b6d4' } : {}}
                    className={`p-3 rounded-lg flex items-center justify-between font-bold text-sm transition-all ${
                      mode.enabled
                        ? 'cursor-pointer hover:text-black text-black'
                        : 'opacity-50 cursor-not-allowed locked-stripes'
                    } ${
                      mode.name === selected ? 'bg-slate-200' : ''
                    }`}
                  >
                    <span>{mode.name}</span>
                    {!mode.enabled && (
                      <span className="beta-badge">LOCKED</span>
                    )}
                  </motion.div>
                  {idx < modes.length - 1 && (
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
