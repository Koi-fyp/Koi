'use client';
import { useEffect, useState } from 'react';
import { getApps, initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, onIdTokenChanged, signInWithEmailAndPassword, signOut, type Auth, type User } from 'firebase/auth';

/** A named Auth instance isolates professional sign-in/logout from the existing companion session. */
let professionalAuth: Auth | null = null;
export function getProfessionalAuth(): Auth {
  if (professionalAuth) return professionalAuth;
  const projectId = process.env.NEXT_PUBLIC_KOI_PLATFORM_FIREBASE_PROJECT_ID || process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID;
  const emulator = process.env.NEXT_PUBLIC_KOI_PLATFORM_AUTH_EMULATOR_URL;
  if (!projectId) throw new Error('Professional sign-in is not configured.');
  if (emulator) {
    const url = new URL(emulator);
    if (process.env.NODE_ENV !== 'development' || !projectId.startsWith('demo-') || !['localhost', '127.0.0.1'].includes(url.hostname) || url.protocol !== 'http:' || url.username || url.password || url.search || url.hash || (url.pathname !== '/' && url.pathname !== '')) throw new Error('Professional emulator configuration is invalid.');
  }
  const apiKey = emulator ? 'demo-platform-key' : process.env.NEXT_PUBLIC_FIREBASE_API_KEY;
  if (!apiKey) throw new Error('Professional sign-in is not configured.');
  const name = 'koi-professional-web1';
  const app = getApps().find(candidate => candidate.name === name) ?? initializeApp({ projectId, apiKey,
    authDomain: emulator ? `${projectId}.firebaseapp.com` : process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN }, name);
  if (app.options.projectId !== projectId) throw new Error('Professional project changed. Reload the application.');
  const auth = getAuth(app);
  if (emulator && !auth.emulatorConfig) connectAuthEmulator(auth, emulator, { disableWarnings: true });
  professionalAuth = auth;
  return auth;
}
export function useProfessionalAuth() {
  const [state, setState] = useState<{ loading: boolean; user: User | null; error: boolean }>({ loading: true, user: null, error: false });
  useEffect(() => {
    try { return onIdTokenChanged(getProfessionalAuth(), user => setState({ loading: false, user, error: false }), () => setState({ loading: false, user: null, error: true })); }
    catch { setState({ loading: false, user: null, error: true }); }
  }, []);
  return { ...state, currentUser: () => getProfessionalAuth().currentUser,
    signIn: async (email: string, password: string) => { await signInWithEmailAndPassword(getProfessionalAuth(), email, password); },
    signOut: async () => { await signOut(getProfessionalAuth()); },
  };
}
