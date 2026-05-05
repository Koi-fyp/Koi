import { NextRequest, NextResponse } from 'next/server';
import { adminAuth, adminFirestore } from '@/lib/firebase-admin';

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { email, password } = body;
    if (!email || !password) {
      return NextResponse.json({ error: 'Missing email or password' }, { status: 400 });
    }

    // Verify caller by ID token in Authorization header
    const authHeader = req.headers.get('authorization') || '';
    const match = authHeader.match(/^Bearer (.*)$/);
    if (!match) return NextResponse.json({ error: 'Authorization required' }, { status: 401 });
    const idToken = match[1];

    const decoded = await adminAuth.verifyIdToken(idToken);
    const uid = decoded.uid;

    // Update user with email/password (this links credentials to the same uid)
    await adminAuth.updateUser(uid, { email, password, emailVerified: false });

    // Generate verification link (client will send)
    const verificationLink = await adminAuth.generateEmailVerificationLink(email);

    // Persist email to Firestore for cross-device sync metadata
    await adminFirestore.collection('users').doc(uid).set({ email, emailVerified: false }, { merge: true });

    return NextResponse.json({ userId: uid, emailVerified: false, verificationLink });
  } catch (err: any) {
    console.error('Link email failed', err?.message || err);
    return NextResponse.json({ error: 'Failed to link email' }, { status: 500 });
  }
}
