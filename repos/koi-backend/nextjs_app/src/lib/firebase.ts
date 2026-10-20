import { getApps, initializeApp, type FirebaseOptions } from 'firebase/app';
import { connectAuthEmulator, getAuth, type Auth } from 'firebase/auth';
import { connectFirestoreEmulator, getFirestore, type Firestore } from 'firebase/firestore';
import { companionDemoEmulators } from './auth/demoEmulatorMode';

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

const missingConfig = Object.entries(firebaseConfig)
  .filter(([, value]) => typeof value !== 'string' || value.trim().length === 0)
  .map(([key]) => `NEXT_PUBLIC_FIREBASE_${key.replace(/[A-Z]/g, (letter) => `_${letter}`).toUpperCase()}`);

const CONFIGURATION_MESSAGE =
  'Firebase sign-in is unavailable because this environment is not fully configured. Set the required NEXT_PUBLIC_FIREBASE_* values and restart the application.';
const INITIALIZATION_MESSAGE =
  'Firebase sign-in is unavailable because the client SDK could not initialize. Check the NEXT_PUBLIC_FIREBASE_* configuration and restart the application.';

export class FirebaseConfigurationError extends Error {
  readonly missingKeys: readonly string[];

  constructor(missingKeys: readonly string[] = [], message = CONFIGURATION_MESSAGE) {
    super(message);
    this.name = 'FirebaseConfigurationError';
    this.missingKeys = missingKeys;
  }
}

let initializedAuth: Auth | null = null;
let initializedFirestore: Firestore | null = null;
let initializedDemoEmulators = false;
let initializationError: FirebaseConfigurationError | null = missingConfig.length
  ? new FirebaseConfigurationError(missingConfig)
  : null;

if (!initializationError) {
  try {
    const demo = companionDemoEmulators(process.env.NEXT_PUBLIC_KOI_COMPANION_DEMO_EMULATOR, process.env.NODE_ENV, firebaseConfig.projectId, process.env.NEXT_PUBLIC_KOI_PLATFORM_AUTH_EMULATOR_URL);
    // Resolve the default app by name, rather than assuming that any Firebase
    // app in the process is the default app used by getAuth()/getFirestore().
    const app = getApps().find((candidate) => candidate.name === '[DEFAULT]')
      ?? initializeApp(firebaseConfig as FirebaseOptions);
    initializedAuth = getAuth(app);
    initializedFirestore = getFirestore(app);
    if (demo) {
      if (app.options.projectId !== 'demo-koi-platform-web1') throw new Error('Demo project mismatch');
      if (!initializedAuth.emulatorConfig) connectAuthEmulator(initializedAuth, 'http://127.0.0.1:5199', { disableWarnings: true });
      connectFirestoreEmulator(initializedFirestore, '127.0.0.1', 5180);
      initializedDemoEmulators = true;
    }
  } catch {
    // Keep module import safe so the application can render a useful setup
    // message. Never substitute an object that only resembles an SDK service.
    initializedAuth = null;
    initializedFirestore = null;
    initializationError = new FirebaseConfigurationError([], INITIALIZATION_MESSAGE);
  }
}

export const auth: Auth | null = initializedAuth;
export const firestore: Firestore | null = initializedFirestore;
export const firebaseConfigurationError = initializationError;
export const isFirebaseConfigured = auth !== null && firestore !== null;
export const isCompanionDemoEmulator = initializedDemoEmulators;
