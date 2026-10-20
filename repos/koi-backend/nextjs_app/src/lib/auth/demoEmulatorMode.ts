/** Explicit development-only opt-in. Invalid requests fail before any Firebase initialization. */
export function companionDemoEmulators(flag?: string, mode?: string, project?: string, authUrl?: string) {
  if (flag !== 'true') return false;
  if (mode !== 'development' || project !== 'demo-koi-platform-web1' || authUrl !== 'http://127.0.0.1:5199') throw new Error('Invalid isolated companion demo configuration');
  return true;
}
