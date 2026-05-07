'use client';
import React, { useState } from 'react';
import { motion } from 'framer-motion';

export default function ChatInput({ onSend }: { onSend?: (text: string) => void }) {
  const [text, setText] = useState('');

  function send() {
    if (!text.trim()) return;
    onSend?.(text.trim());
    setText('');
  }

  return (
    <div className="w-full flex items-center gap-3">
      <div className="flex-1 flex items-center bg-white/80 backdrop-blur-md neo-brutalist border-[2px] border-black rounded-full px-4 py-2">
        <input
          className="flex-1 bg-transparent outline-none text-black placeholder-gray-500"
          placeholder="Write a message..."
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') send(); }}
        />

        <motion.button
          onClick={send}
          whileHover={{ scale: 1.02, boxShadow: '2px 2px 0px 0px rgba(0,0,0,1)' }}
          whileTap={{ x: 5, y: 5, boxShadow: '0px 0px 0px 0px rgba(0,0,0,0)', translateY: 5 }}
          className="ml-3 w-10 h-10 rounded-full bg-black flex items-center justify-center"
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M22 2L11 13" stroke="#fff" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
            <path d="M22 2L15 22L11 13L2 9L22 2Z" stroke="#fff" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </motion.button>
      </div>
    </div>
  );
}
