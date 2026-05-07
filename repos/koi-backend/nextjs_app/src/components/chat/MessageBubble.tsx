'use client';
import React from 'react';
import { motion } from 'framer-motion';
import { ChatMessage } from '@/hooks/useChat';

function formatTime(date: Date): string {
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

interface MessageBubbleProps {
  message: ChatMessage;
  showAvatar?: boolean;
}

export default function MessageBubble({ message, showAvatar = false }: MessageBubbleProps) {
  const isUser = message.sender === 'user';

  return (
    <div
      data-sender={message.sender}
      className={`flex flex-col ${isUser ? 'items-end' : 'items-start'} px-4 py-2 animate-[koiSlideIn_0.25s_cubic-bezier(0.34,1.56,0.64,1)_both]`}
    >
      <div className="flex gap-2 items-end max-w-[82%]">
        {!isUser && (
          <div className="w-9 h-9 flex-shrink-0">
            {showAvatar && (
              <div className="w-9 h-9 rounded-full bg-[var(--neo-blue)] border-[2.5px] border-black flex items-center justify-center font-bold text-white">
                K
              </div>
            )}
          </div>
        )}

        <motion.div
          whileTap={{ x: isUser ? 5 : 0, y: isUser ? 5 : 0, scale: 0.995 }}
          className={
            `p-3 border-[2px] border-black rounded-[15px] text-sm leading-6 break-words font-[var(--font-body)] ` +
            (isUser
              ? 'bg-[#3B82F6] text-white hard-shadow'
              : 'glass-white text-black hard-shadow-cyan')
          }
        >
          {message.content}
        </motion.div>
      </div>

      <div className={`text-[11px] text-gray-600 mt-2 ${isUser ? 'self-end pr-1' : 'self-start pl-1'}`}>
        {formatTime(message.timestamp)}
      </div>
    </div>
  );
}
