module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'jsdom',
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '^next/navigation$': '<rootDir>/src/__mocks__/next-navigation.ts',
    '^next/link$': '<rootDir>/src/__mocks__/next-link.tsx',
    '^dexie$': '<rootDir>/src/__mocks__/dexie.ts',
  },
  transform: {
    '^.+\\.tsx?$': 'ts-jest'
  },
  testMatch: ['**/__tests__/**/*.test.{ts,tsx}'],
  setupFiles: ['<rootDir>/src/__tests__/setup.env.ts'],
  setupFilesAfterEnv: ['@testing-library/jest-dom'],
  transformIgnorePatterns: [
    'node_modules/(?!(firebase|@firebase|dexie)/)'
  ]
};
