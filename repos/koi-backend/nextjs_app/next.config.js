const { PHASE_DEVELOPMENT_SERVER } = require('next/constants');

/** @type {import('next').NextConfig} */
const nextConfig = {
  transpilePackages: ['dexie', 'dexie-react-hooks'],
  experimental: {
    serverComponentsExternalPackages: ['firebase-admin'],
  },
};

// `next build` empties its distDir; a dev server sharing `.next` then serves 404s
// for every chunk and the landing page never hydrates. Keep dev output separate.
module.exports = (phase) => (
  phase === PHASE_DEVELOPMENT_SERVER ? { ...nextConfig, distDir: '.next-dev' } : nextConfig
);
