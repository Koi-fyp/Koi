import type { AnchorHTMLAttributes } from 'react';

export type CareLinkVariant = 'primary' | 'secondary' | 'compact';

/** Semantic navigation using the care platform's existing Neo button tokens. */
export default function CareLink({ variant = 'compact', className = '', ...props }: AnchorHTMLAttributes<HTMLAnchorElement> & { variant?: CareLinkVariant }) {
  const neo = variant === 'primary' ? 'neo-btn-primary' : variant === 'secondary' ? 'neo-btn-ghost' : '';
  return <a {...props} className={`care-link care-link--${variant} ${neo} ${className}`} />;
}
