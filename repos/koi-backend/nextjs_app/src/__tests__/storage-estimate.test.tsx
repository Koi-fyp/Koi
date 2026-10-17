import { renderHook, waitFor } from '@testing-library/react';
import { useStorageEstimate } from '@/hooks/useStorageEstimate';

const original = Object.getOwnPropertyDescriptor(navigator, 'storage');
afterEach(() => {
  if (original) Object.defineProperty(navigator, 'storage', original);
  else Reflect.deleteProperty(navigator, 'storage');
});
it('labels measured usage as an approximate origin-wide estimate, not personal KOI storage', async () => {
  Object.defineProperty(navigator, 'storage', { configurable: true, value: { estimate: async () => ({ usage: 1048576, quota: 10485760 }) } });
  const { result } = renderHook(useStorageEstimate);
  await waitFor(() => expect(result.current.percent).toBe(10));
  expect(result.current.label).toContain('1.00 MB of 10.00 MB');
  expect(result.current.label).toContain('includes caches and other accounts');
});
it.each([undefined, { estimate: async () => { throw Error('denied'); } },
  { estimate: async () => ({ usage: NaN, quota: 10 }) },
  { estimate: async () => ({ usage: 1, quota: 0 }) }])('does not fabricate usage when unavailable or invalid', async storage => {
  Object.defineProperty(navigator, 'storage', { configurable: true, value: storage });
  const { result } = renderHook(useStorageEstimate);
  await waitFor(() => expect(result.current.percent).toBeNull());
  expect(result.current.label).toContain('unavailable');
});
