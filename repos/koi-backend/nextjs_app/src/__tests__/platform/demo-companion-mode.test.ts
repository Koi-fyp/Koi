import { companionDemoEmulators } from '@/lib/auth/demoEmulatorMode';
it('leaves the original initialization path unchanged without explicit opt-in', () => {
  expect(companionDemoEmulators(undefined, 'production', 'live-project', undefined)).toBe(false);
});
it('accepts only the exact development demo project and local Auth endpoint', () => {
  expect(companionDemoEmulators('true', 'development', 'demo-koi-platform-web1', 'http://127.0.0.1:5199')).toBe(true);
  for (const [mode, project, host] of [['production', 'demo-koi-platform-web1', 'http://127.0.0.1:5199'], ['development', 'live-project', 'http://127.0.0.1:5199'], ['development', 'demo-koi-platform-web1', 'https://example.com']]) expect(() => companionDemoEmulators('true', mode, project, host)).toThrow();
});
