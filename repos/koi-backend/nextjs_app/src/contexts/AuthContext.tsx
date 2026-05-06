"use client";
import React, { createContext, useContext, useEffect, useState } from 'react';
import { auth } from '@/lib/firebase';
import { signInWithCustomToken, signOut as firebaseSignOut } from 'firebase/auth';

interface AuthContextType {
  user: any | null;
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

async function storeEncrypted(key: string, data: any) {
  const raw = JSON.stringify(data);
  const enc = new TextEncoder().encode(raw);
  const cryptoKey = await window.crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, true, ["encrypt", "decrypt"]);
  const iv = window.crypto.getRandomValues(new Uint8Array(12));
  const ct = await window.crypto.subtle.encrypt({ name: 'AES-GCM', iv }, cryptoKey, enc);
  // store key and ciphertext in IndexedDB (simple using localStorage for demo)
  const exportedKey = await window.crypto.subtle.exportKey('raw', cryptoKey);
  const exportedKeyArr = new Uint8Array(exportedKey);
  localStorage.setItem(`${key}:key`, btoa(String.fromCharCode(...exportedKeyArr)));
  localStorage.setItem(`${key}:iv`, btoa(String.fromCharCode(...iv)));
  const ctArr = new Uint8Array(ct);
  localStorage.setItem(`${key}:data`, btoa(String.fromCharCode(...ctArr)));
}

function Uint8List(buf: ArrayBuffer) {
  return new Uint8Array(buf);
}

async function decryptStored(key: string) {
  try {
    const k = localStorage.getItem(`${key}:key`);
    const ivB = localStorage.getItem(`${key}:iv`);
    const dataB = localStorage.getItem(`${key}:data`);
    if (!k || !ivB || !dataB) return null;
    const keyBytes = Uint8Array.from(atob(k), c => c.charCodeAt(0));
    const iv = Uint8Array.from(atob(ivB), c => c.charCodeAt(0));
    const dataBytes = Uint8Array.from(atob(dataB), c => c.charCodeAt(0));
    const cryptoKey = await window.crypto.subtle.importKey('raw', keyBytes.buffer, 'AES-GCM', true, ['decrypt']);
    const plain = await window.crypto.subtle.decrypt({ name: 'AES-GCM', iv }, cryptoKey, dataBytes);
    return JSON.parse(new TextDecoder().decode(plain));
  } catch (e) {
    console.warn('decryptStored failed', e);
    return null;
  }
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<any | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    (async () => {
      // Try to restore encrypted session
      const stored = await decryptStored('koi_auth');
      if (stored && stored.authToken) {
        try {
          await signInWithCustomToken(auth, stored.authToken);
        } catch (e) {
          console.warn('Token sign-in failed', e);
        }
      }
      setLoading(false);
    })();
  }, []);

  const signInAnonymously = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/auth/anonymous', { method: 'POST' });
      if (!res.ok) throw new Error('Failed to create anonymous session');
      const data = await res.json();
      await signInWithCustomToken(auth, data.token);
      // store encrypted
      await storeEncrypted('koi_auth', { userId: data.userId, authToken: data.token, lastActive: new Date().toISOString() });
      setUser({ uid: data.userId });
    } catch (e: any) {
      setError(e);
    } finally {
      setLoading(false);
    }
  };

  const linkWithEmail = async (email: string, password: string) => {
    setLoading(true);
    setError(null);
    try {
      // Get current idToken for verification
      const idToken = await auth.currentUser?.getIdToken();
      const res = await fetch('/api/auth/link-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${idToken}` },
        body: JSON.stringify({ email, password }),
      });
      if (!res.ok) throw new Error('Failed to link email');
      const payload = await res.json();
      // The server provides a verification link; client should show user the verification step
      return payload;
    } catch (e: any) {
      setError(e);
      throw e;
    } finally {
      setLoading(false);
    }
  };

  const signOut = async () => {
    setLoading(true);
    setError(null);
    try {
      await firebaseSignOut(auth);
      // clear stored encrypted data but keep for offline sign-in if needed - per privacy we keep user key but here we clear
      localStorage.removeItem('koi_auth:key');
      localStorage.removeItem('koi_auth:iv');
      localStorage.removeItem('koi_auth:data');
      setUser(null);
    } catch (e: any) {
      setError(e);
    } finally {
      setLoading(false);
    }
  };

  const value: AuthContextType = {
    user,
    loading,
    error,
    signInAnonymously,
    linkWithEmail: async (e, p) => await linkWithEmail(e, p),
    signOut,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
