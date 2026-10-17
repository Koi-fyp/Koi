const clientKeys = [
  'NEXT_PUBLIC_FIREBASE_API_KEY',
  'NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN',
  'NEXT_PUBLIC_FIREBASE_PROJECT_ID',
  'NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET',
  'NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID',
  'NEXT_PUBLIC_FIREBASE_APP_ID',
] as const;

const mockApp = { name: '[DEFAULT]' };
const mockAuth = { currentUser: null };
const mockFirestore = { app: mockApp };
const mockGetApps = jest.fn(() => [] as Array<{ name: string }>);

jest.mock('firebase/app', () => ({
  getApps: mockGetApps,
  initializeApp: jest.fn(() => mockApp),
}));
jest.mock('firebase/auth', () => ({ getAuth: jest.fn(() => mockAuth) }));
jest.mock('firebase/firestore', () => ({ getFirestore: jest.fn(() => mockFirestore) }));

const completeEnvironment = () => {
  clientKeys.forEach((key, index) => {
    process.env[key] = `test-firebase-value-${index}`;
  });
};

describe('Firebase client initialization', () => {
  const originalValues = new Map(clientKeys.map((key) => [key, process.env[key]]));

  afterEach(() => {
    jest.resetModules();
    mockGetApps.mockReset().mockReturnValue([]);
    clientKeys.forEach((key) => {
      const original = originalValues.get(key);
      if (original === undefined) delete process.env[key];
      else process.env[key] = original;
    });
    jest.clearAllMocks();
  });

  it('exports no SDK-shaped fallback and reports missing configuration', () => {
    clientKeys.forEach((key) => delete process.env[key]);
    let client!: typeof import('@/lib/firebase');
    jest.isolateModules(() => { client = require('@/lib/firebase'); });

    expect(client.auth).toBeNull();
    expect(client.firestore).toBeNull();
    expect(client.isFirebaseConfigured).toBe(false);
    expect(client.firebaseConfigurationError?.missingKeys).toHaveLength(clientKeys.length);
    expect(client.firebaseConfigurationError?.message).toMatch(/not fully configured/i);
    expect(require('firebase/app').initializeApp).not.toHaveBeenCalled();
  });

  it('creates typed Auth and Firestore instances from complete configuration', () => {
    completeEnvironment();
    let client!: typeof import('@/lib/firebase');
    let firebaseAppModule: typeof import('firebase/app');
    jest.isolateModules(() => {
      firebaseAppModule = require('firebase/app');
      client = require('@/lib/firebase');
    });

    expect(client.auth).toBe(mockAuth);
    expect(client.firestore).toBe(mockFirestore);
    expect(client.isFirebaseConfigured).toBe(true);
    expect(client.firebaseConfigurationError).toBeNull();
    expect(firebaseAppModule!.initializeApp).toHaveBeenCalledTimes(1);
  });

  it('does not initialize a partial configuration or reuse a named app as the default', () => {
    completeEnvironment();
    delete process.env.NEXT_PUBLIC_FIREBASE_APP_ID;
    let partial!: typeof import('@/lib/firebase');
    let partialAppModule: typeof import('firebase/app');
    jest.isolateModules(() => {
      partialAppModule = require('firebase/app');
      partial = require('@/lib/firebase');
    });
    expect(partial.auth).toBeNull();
    expect(partial.firebaseConfigurationError?.missingKeys).toEqual(['NEXT_PUBLIC_FIREBASE_APP_ID']);
    expect(partialAppModule!.initializeApp).not.toHaveBeenCalled();

    jest.resetModules();
    completeEnvironment();
    const namedApp = { name: 'some-other-app' };
    mockGetApps.mockReturnValue([namedApp]);
    let configured!: typeof import('@/lib/firebase');
    let appModule: typeof import('firebase/app');
    let authModule: typeof import('firebase/auth');
    jest.isolateModules(() => {
      appModule = require('firebase/app');
      authModule = require('firebase/auth');
      configured = require('@/lib/firebase');
    });
    expect(configured.isFirebaseConfigured).toBe(true);
    expect(appModule!.initializeApp).toHaveBeenCalledTimes(1);
    expect(authModule!.getAuth).toHaveBeenCalledWith(mockApp);
  });
});
