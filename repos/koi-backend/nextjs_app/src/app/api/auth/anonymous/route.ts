import { NextRequest, NextResponse } from 'next/server';
import { v4 as uuidv4 } from 'uuid';
import { adminAuth, adminFirestore, admin } from '@/lib/firebase-admin';

export async function POST(req: NextRequest) {
  try {
    const uid = uuidv4();

    // Create a custom token so client can signInWithCustomToken
    const token = await adminAuth.createCustomToken(uid);

    // Ensure Firestore user doc exists
    const userRef = adminFirestore.collection('users').doc(uid);
    const snap = await userRef.get();
    if (!snap.exists) {
      await userRef.set({
        koiUuid: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastActive: admin.firestore.FieldValue.serverTimestamp(),
        profile: { avatar: null, language: 'en', notificationTime: null },
        classification: {},
        settings: { notifications_enabled: true, sound_enabled: true, haptic_enabled: true },
        stats: { total_conversations: 0, total_check_ins: 0, current_streak: 0, longest_streak: 0, jigsaw_pieces: 0 },
      });
    }

    return NextResponse.json({ userId: uid, token }, { status: 201 });
  } catch (err: any) {
    console.error('Anonymous creation failed', err?.message || err);
    return NextResponse.json({ error: 'Failed to create anonymous user' }, { status: 500 });
  }
}
