'use client';
import React from 'react';
import { motion } from 'framer-motion';

export default function SidebarProfileCard() {
  return (
    <div className="neo-brutalist p-4 w-64 glass-white">
      <div className="neo-brutalist hard-shadow-cyan p-3 rounded-lg flex flex-col items-center gap-4">
        <div className="w-36 h-36 rounded-md bg-[#FFCC00] neo-brutalist flex items-center justify-center">
          {/* Placeholder avatar area */}
          <div className="text-3xl font-bold">KOI</div>
        </div>

        <div className="w-full">
          <motion.button
            whileHover={{ x: 0, y: 0, boxShadow: '2px 2px 0px 0px rgba(0,0,0,1)' }}
            whileTap={{ x: 5, y: 5, boxShadow: '0px 0px 0px 0px rgba(0,0,0,0)' }}
            className="w-full bg-white border-[3px] border-black hard-shadow p-3 rounded-md flex items-center justify-center gap-2"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path d="M2 7.5L12 13L22 7.5" stroke="#000" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
              <rect x="2" y="4" width="20" height="14" rx="2" stroke="#000" strokeWidth="1.5"/>
            </svg>
            <span className="font-bold">Start a conversation with KOI</span>
          </motion.button>
        </div>
      </div>
    </div>
  );
}
