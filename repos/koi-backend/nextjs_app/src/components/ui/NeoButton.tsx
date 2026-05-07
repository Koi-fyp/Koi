'use client';
import { ButtonHTMLAttributes } from 'react';

export type NeoButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger';

interface NeoButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: NeoButtonVariant;
  loading?: boolean;
  fullWidth?: boolean;
}

export default function NeoButton({
  variant = 'primary',
  loading = false,
  fullWidth = false,
  children,
  disabled,
  className = '',
  ...props
}: NeoButtonProps) {
  return (
    <button
      {...props}
      disabled={disabled || loading}
      className={[
        `neo-btn-${variant}`,
        fullWidth && 'w-full',
        className,
      ].filter(Boolean).join(' ')}
    >
      {loading ? (
        <>
          <span className="neo-spinner" />
          Loading…
        </>
      ) : children}
    </button>
  );
}
