import { HTMLAttributes } from 'react';

export type NeoCardVariant = 'default' | 'yellow' | 'elevated';

interface NeoCardProps extends HTMLAttributes<HTMLDivElement> {
  variant?: NeoCardVariant;
}

export default function NeoCard({
  variant = 'default',
  children,
  className = '',
  ...props
}: NeoCardProps) {
  const variantClass = variant === 'default' ? 'neo-card' : `neo-card--${variant}`;
  return (
    <div
      {...props}
      className={[variantClass, className].filter(Boolean).join(' ')}
    >
      {children}
    </div>
  );
}
