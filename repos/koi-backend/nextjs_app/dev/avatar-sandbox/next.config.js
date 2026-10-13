const path = require('node:path');
const { PHASE_DEVELOPMENT_SERVER } = require('next/constants');

module.exports = (phase) => {
  if (phase !== PHASE_DEVELOPMENT_SERVER || process.env.NODE_ENV !== 'development') {
    throw new Error('KOI avatar sandbox cannot be built or served in production.');
  }
  return {
    reactStrictMode: true,
    experimental: { externalDir: true },
    webpack(config) {
      config.resolve.alias['@'] = path.resolve(__dirname, '../../src');
      return config;
    },
  };
};
