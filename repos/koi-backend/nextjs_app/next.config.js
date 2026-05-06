/** @type {import('next').NextConfig} */
const nextConfig = {
  transpilePackages: ['dexie', 'dexie-react-hooks'],
  experimental: {
    serverComponentsExternalPackages: ['firebase-admin'],
  },
};
module.exports = nextConfig;
