import admin from 'firebase-admin';

let app: admin.app.App;

if (!admin.apps.length) {
  const raw = process.env.FIREBASE_ADMIN_SDK || '';
  if (!raw) {
    throw new Error('FIREBASE_ADMIN_SDK env var is required (JSON string)');
  }
  const cred = JSON.parse(raw);
  app = admin.initializeApp({ credential: admin.credential.cert(cred) });
} else {
  app = admin.app();
}

export { admin };
export const adminAuth = admin.auth();
export const adminFirestore = admin.firestore();
