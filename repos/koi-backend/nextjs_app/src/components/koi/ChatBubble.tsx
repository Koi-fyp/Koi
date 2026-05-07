'use client';
import React from 'react';
import { motion } from 'framer-motion';

interface ChatBubbleProps {
  text: string;
  time?: string;
  incoming?: boolean; // left
}

export default function ChatBubble({ text, time, incoming = true }: ChatBubbleProps) {
  const bubbleClasses = incoming
    ? 'glass-white border-[2px] border-black rounded-[15px] text-black'
    : 'bg-[#3B82F6] text-white border-[2px] border-black rounded-[15px]';

  const containerAlign = incoming ? 'items-start' : 'items-end';

  return (
    <div className={`flex flex-col ${containerAlign} px-2 py-1`}>
      <motion.div
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.2 }}
        className={`max-w-[78%] ${bubbleClasses} p-3 font-sans neo-btn-ghost`}>
        <div className="relative">
          <div className="text-sm leading-6">{text}</div>
        </div>
      </motion.div>

      <div className={`text-[11px] text-gray-600 mt-2 ${incoming ? 'self-start pl-1' : 'self-end pr-1'}`}>
        {time}
      </div>
    </div>
  );
}
