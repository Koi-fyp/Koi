import React from 'react';

const Link = ({ href, children, ...props }: React.AnchorHTMLAttributes<HTMLAnchorElement> & { href: string }) => (
  <a href={href} {...props}>
    {children}
  </a>
);

export default Link;
