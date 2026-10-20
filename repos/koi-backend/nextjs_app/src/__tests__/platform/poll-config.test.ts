import { accessPollMs, navPollMs, parsePollMs } from '@/lib/platform/poll-config';
it('uses defaults for missing or non-integer input', () => {
  for (const raw of [undefined, '', 'abc', '10.5', '-3000', '1e4']) { expect(accessPollMs(raw)).toBe(10000); expect(navPollMs(raw)).toBe(15000); }
});
it('accepts valid integers', () => { expect(accessPollMs('30000')).toBe(30000); expect(navPollMs(' 20000 ')).toBe(20000); });
it('clamps below the minimum', () => { expect(accessPollMs('100')).toBe(2000); expect(navPollMs('0')).toBe(5000); });
it('clamps above the maximum', () => { expect(accessPollMs('999999')).toBe(60000); expect(navPollMs('999999')).toBe(120000); });
it('falls back when the integer is unsafe', () => { expect(parsePollMs('9'.repeat(20), 7, 1, 10)).toBe(7); });
