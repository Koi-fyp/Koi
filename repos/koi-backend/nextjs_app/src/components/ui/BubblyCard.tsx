import { HTMLAttributes } from 'react';

type AccentColor = 'pink' | 'blue' | 'lavender' | 'mint';

interface BubblyCardProps extends HTMLAttributes<HTMLDivElement> {
  accent?: AccentColor;
}

const accentMap: Record<AccentColor, string> = {
  pink:     'bg-koi-pastelPink',
  blue:     'bg-koi-pastelBlue',
  lavender: 'bg-koi-pastelLavender',
  mint:     'bg-koi-pastelMint',
};

export default function BubblyCard({
  accent,
  className = '',
  children,
  ...props
}: BubblyCardProps) {
  const bg = accent ? accentMap[accent] : 'bg-white';

  return (
    <div
      {...props}
      className={`rounded-koi shadow-bubbly p-6 ${bg} ${className}`.trim()}
    >
      {children}
    </div>
  );
}
