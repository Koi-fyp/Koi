// Shared by server-only runtime and the explicitly invoked restricted CLI. Never imported by clients.
const { initializeApp, getApps, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

function configuration(env = process.env) {
  const project = env.KOI_PLATFORM_FIREBASE_PROJECT_ID;
  if (!project || !/^[a-z0-9][a-z0-9-]{3,62}$/.test(project)) throw new Error('Platform project must be pinned');
  const mode = env.KOI_PLATFORM_MODE;
  let credential;
  if (mode === 'emulator') {
    const loopback = /^(127\.0\.0\.1|localhost):[1-9][0-9]{1,4}$/;
    if (!project.startsWith('demo-') || !loopback.test(env.FIRESTORE_EMULATOR_HOST || '') || !loopback.test(env.FIREBASE_AUTH_EMULATOR_HOST || '')) throw new Error('Use isolated loopback emulators and a demo project');
  } else if (mode === 'reviewed-production') {
    if (env.FIRESTORE_EMULATOR_HOST || env.FIREBASE_AUTH_EMULATOR_HOST || !/^[a-f0-9]{64}$/.test(env.KOI_PLATFORM_RULESET_SHA256 || '')) throw new Error('Published rules review is required');
    const serviceAccount = JSON.parse(env.FIREBASE_ADMIN_SDK || '{}');
    if (serviceAccount.project_id !== project) throw new Error('Platform credential project mismatch');
    credential = serviceAccount;
  } else throw new Error('Platform is disabled until an environment is explicitly selected');
  const cursorKey = env.KOI_PLATFORM_CURSOR_SIGNING_KEY || (mode === 'emulator' ? 'demo-only-platform-cursor-key-never-use-in-production' : '');
  if (cursorKey.length < 32) throw new Error('Platform cursor signing key is required');
  return { project, mode, credential, cursorKey };
}

function getPlatformAdmin() {
  const config = configuration();
  const name = 'koi-platform-server-web1';
  let app = getApps().find(candidate => candidate.name === name);
  if (app && app.options.projectId !== config.project) throw new Error('Platform project changed; restart the server');
  if (!app) app = initializeApp({ projectId: config.project, ...(config.credential ? { credential: cert(config.credential) } : {}) }, name);
  return { auth: getAuth(app), db: getFirestore(app), config };
}
module.exports = { configuration, getPlatformAdmin };
