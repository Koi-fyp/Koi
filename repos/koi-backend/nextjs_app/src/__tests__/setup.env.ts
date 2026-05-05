process.env.NEXT_PUBLIC_FIREBASE_API_KEY = 'AIzaSyTest123456789Test123456789Test123456';
process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN = 'koi-companion-fyp.firebaseapp.com';
process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID = 'koi-companion-fyp';
process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET = 'koi-companion-fyp.appspot.com';
process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID = '123456789012';
process.env.NEXT_PUBLIC_FIREBASE_APP_ID = '1:123456789012:web:abc123def456ghi789jkl';
process.env.FIREBASE_ADMIN_SDK = JSON.stringify({
  type: 'service_account',
  project_id: 'koi-companion-fyp',
  private_key_id: 'test-key-id',
  private_key: '-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7\n-----END PRIVATE KEY-----\n',
  client_email: 'firebase-adminsdk@koi-companion-fyp.iam.gserviceaccount.com',
  client_id: '123456789',
  auth_uri: 'https://accounts.google.com/o/oauth2/auth',
  token_uri: 'https://oauth2.googleapis.com/token',
});
