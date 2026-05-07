'use client';

import { ButtonHTMLAttributes } from 'react';

interface BubblyButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary';
  fullWidth?: boolean;
}

export default function BubblyButton({
  variant = 'primary',
  fullWidth = false,
  className = '',
  children,
  disabled,
  ...props
}: BubblyButtonProps) {
  const base =
    'rounded-full px-8 py-4 text-base font-semibold shadow-bubbly ' +
    'transition-transform duration-150 select-none ' +
    'hover:scale-105 active:scale-95 ' +
    'disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100 disabled:active:scale-100';

  const variants: Record<string, string> = {
    primary: 'bg-koi-primary text-white',
    secondary: 'bg-white text-koi-primary border-2 border-koi-primary',
  };

  return (
    <button
      {...props}
      disabled={disabled}
      className={`${base} ${variants[variant]} ${fullWidth ? 'w-full' : ''} ${className}`.trim()}
    >
      {children}
    </button>
  );
}
