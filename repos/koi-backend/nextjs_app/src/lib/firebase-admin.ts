import admin from 'firebase-admin';

function getAdminApp(): admin.app.App {
  if (admin.apps.length > 0) return admin.app();
  const raw = process.env.FIREBASE_ADMIN_SDK;
  if (!raw) throw new Error('FIREBASE_ADMIN_SDK env var is required (JSON string)');
  const cred = JSON.parse(raw) as admin.ServiceAccount;
  return admin.initializeApp({ credential: admin.credential.cert(cred) });
}

export { admin };
export const adminAuth = getAdminApp().auth();
export const adminFirestore = getAdminApp().firestore();
