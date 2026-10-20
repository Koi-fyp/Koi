const PROJECT = 'demo-koi-platform-web1';
const IDENTITIES = Object.freeze({
  psychologist: { uid: 'koi_demo_web4_psychologist', email: 'psychologist@koi-demo.example' },
  general: { uid: 'koi_demo_web4_general', email: 'general@koi-demo.example' },
  patient: { uid: 'koi_demo_web4_patient', email: 'patient@koi-demo.example' },
});
function guard(env = process.env) {
  if (env.KOI_PLATFORM_MODE !== 'emulator' || env.KOI_PLATFORM_FIREBASE_PROJECT_ID !== PROJECT || env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:5180' || env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:5199') throw new Error('exact_demo_emulators_required');
  for (const name of ['GOOGLE_APPLICATION_CREDENTIALS', 'FIREBASE_ADMIN_SDK', 'FIREBASE_TOKEN', 'GOOGLE_OAUTH_ACCESS_TOKEN', 'GOOGLE_CREDENTIALS', 'FIREBASE_SERVICE_ACCOUNT', 'KOI_PLATFORM_RULESET_SHA256']) if (env[name]) throw new Error('production_credentials_forbidden');
  for (const name of ['GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'FIREBASE_PROJECT_ID']) if (env[name] && env[name] !== PROJECT) throw new Error('conflicting_project_forbidden');
  if (env.FIREBASE_CONFIG) { let c; try { c = JSON.parse(env.FIREBASE_CONFIG); } catch { throw new Error('firebase_config_forbidden'); } if (c.projectId !== PROJECT || c.credential || c.databaseURL) throw new Error('firebase_config_forbidden'); }
  return { project: PROJECT, base: 'http://127.0.0.1:3107' };
}
function passwords(env = process.env) {
  return Object.fromEntries(Object.keys(IDENTITIES).map(role => {
    const value = env[`KOI_DEMO_${role.toUpperCase()}_PASSWORD`] || env.KOI_DEMO_PASSWORD;
    if (typeof value !== 'string' || value.length < 12 || value.length > 128) throw new Error('demo_passwords_require_12_to_128_characters');
    return [role, value];
  }));
}
module.exports = { PROJECT, IDENTITIES, guard, passwords };
