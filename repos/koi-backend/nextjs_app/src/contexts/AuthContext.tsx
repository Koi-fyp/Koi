"use client";
import React, { createContext, useContext, useEffect, useState } from 'react';
import { auth, firebaseConfigurationError } from '@/lib/firebase';
import {
  onAuthStateChanged,
  signInWithCustomToken,
  signOut as firebaseSignOut,
  User,
} from 'firebase/auth';

/**
 * 🆕 [SESSION FIX — see SESSION_HANDOFF.md §22.3 addition]
 *
 * This file previously restored sessions via a hand-rolled
 * storeEncrypted()/decryptStored() pair. That mechanism has been REMOVED
 * for two independent reasons, found during review for the
 * getActiveCryptoContext() offline/new-device fix:
 *
 *   1. NOT SECURE — it generated a random AES-GCM key per call, then
 *      exported and stored that key in localStorage right next to the
 *      ciphertext it encrypted (`${key}:key`, `${key}:iv`, `${key}:data`
 *      all in the same, equally-readable storage). This provided no real
 *      confidentiality — anyone with devtools access to the browser could
 *      decrypt `koi_auth:data` immediately. It did not use the locked
 *      PBKDF2+AES-GCM pipeline already implemented in `crypto.ts` in this
 *      same codebase.
 *
 *   2. NOT NECESSARY — Firebase Auth's JS SDK persists sessions locally
 *      (IndexedDB, `browserLocalPersistence` by default in web
 *      environments) and restores them automatically, including OFFLINE —
 *      `onAuthStateChanged` fires with the cached user before any network
 *      round-trip completes. The custom mechanism was solving a problem
 *      Firebase already solves correctly, for free.
 *
 * Replaced with `onAuthStateChanged`, Firebase's own listener. This also
 * fixes a real bug: the previous `signInWithCustomToken` restore call was
 * a network request with no offline path — on an offline app launch, it
 * threw, was silently swallowed by a `catch`, and `user` stayed `null`
 * even for an already-signed-in person. That is fixed as a side effect of
 * this change, not a separate patch.
 *
 * `isAnonymous` and `isLinked` are newly exposed here — needed by
 * `getActiveCryptoContext()`'s locked block/retry logic to distinguish a
 * previously-linked user (who must block on missing salt+offline) from an
 * anonymous one (for whom local salt generation remains correct, per
 * existing accepted behavior).
 *
 * NOT fixed here, flagged rather than silently assumed away: linked-phase
 * `secret` (the user's password) has no session re-entry path anywhere in
 * this file. `linkWithEmail()` only ever sees a password at the moment of
 * initial linking. A "re-enter password to unlock" step for a *returning*
 * linked session does not exist yet. Callers needing a linked user's
 * secret (e.g. `getActiveCryptoContext`) must be supplied one from
 * wherever that future step lives — this file does not provide it.
 */

interface AuthContextType {
  user: User | null;
  isAnonymous: boolean;
  isLinked: boolean;
  loading: boolean;
  error: Error | null;
  signInAnonymously: () => Promise<void>;
  linkWithEmail: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
};

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    if (!auth) {
      setError(firebaseConfigurationError ?? new Error('Firebase authentication is unavailable in this environment.'));
      setLoading(false);
      return;
    }

    // Firebase's own persisted-session listener. Fires synchronously with
    // the cached user (if any) before any network call completes, so this
    // works offline. Updates again once/if a fresh token round-trip
    // resolves. No manual encryption/decryption needed — see file header.
    try {
      const unsubscribe = onAuthStateChanged(
        auth,
        (firebaseUser) => {
          setUser(firebaseUser);
          setLoading(false);
          setError(null);
        },
        (listenerError) => {
          setError(listenerError);
          setLoading(false);
        },
      );
      return () => unsubscribe();
    } catch {
      setError(firebaseConfigurationError ?? new Error('Firebase authentication could not be initialized.'));
      setLoading(false);
    }
  }, []);

  // Derived, not stored — always reflects Firebase's own live user object.
  const isAnonymous = user?.isAnonymous ?? false;
  const isLinked =
    user != null &&
    !user.isAnonymous &&
    user.providerData.some((p) => p.providerId === 'password');

  const signInAnonymously = async () => {
    if (!auth) {
      setError(firebaseConfigurationError ?? new Error('Firebase authentication is unavailable in this environment.'));
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/auth/anonymous', { method: 'POST' });
      if (!res.ok) throw new Error('Failed to create anonymous session');
      const data = await res.json();
      await signInWithCustomToken(auth, data.token);
      // No manual storeEncrypted() call needed — onAuthStateChanged above
      // picks up the new session automatically, and Firebase persists it.
    } catch (e: any) {
      setError(e);
    } finally {
      setLoading(false);
    }
  };

  const linkWithEmail = async (email: string, password: string) => {
    if (!auth) {
      const configurationError = firebaseConfigurationError ?? new Error('Firebase authentication is unavailable in this environment.');
      setError(configurationError);
      throw configurationError;
    }
    setLoading(true);
    setError(null);
    try {
      const idToken = await auth.currentUser?.getIdToken();
      const res = await fetch('/api/auth/link-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${idToken}` },
        body: JSON.stringify({ email, password }),
      });
      if (!res.ok) throw new Error('Failed to link email');
      const payload = await res.json();
      // Caller is responsible for triggering reencryptOnLinking() (see
      // crypto.ts) using this same `password` value before it goes out of
      // scope — this function does not do that itself, unchanged from
      // before this patch.
      return payload;
    } catch (e: any) {
      setError(e);
      throw e;
    } finally {
      setLoading(false);
    }
  };

  const signOut = async () => {
    if (!auth) {
      setError(firebaseConfigurationError ?? new Error('Firebase authentication is unavailable in this environment.'));
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      await firebaseSignOut(auth);
      // No manual localStorage cleanup needed — nothing is written there
      // by this file anymore. Firebase clears its own persisted session.
      setUser(null);
    } catch (e: any) {
      setError(e);
    } finally {
      setLoading(false);
    }
  };

  const value: AuthContextType = {
    user,
    isAnonymous,
    isLinked,
    loading,
    error,
    signInAnonymously,
    linkWithEmail,
    signOut,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
