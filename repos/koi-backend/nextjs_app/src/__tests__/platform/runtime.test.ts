/** @jest-environment node */
jest.mock('server-only', () => ({}), { virtual: true });
jest.mock('@/lib/platform/server/admin-config.cjs', () => ({ getPlatformAdmin: jest.fn() }));
import { NextRequest } from 'next/server';
import { getPlatformRuntime } from '@/lib/platform/server/runtime';
const adminConfig = require('@/lib/platform/server/admin-config.cjs');
const verify = jest.fn();
beforeEach(() => { verify.mockReset(); adminConfig.getPlatformAdmin.mockReturnValue({ auth: { verifyIdToken: verify }, db: {}, config: { project: 'demo-koi-platform', cursorKey: 'cursor-key-with-at-least-32-characters' } }); });
const request = () => new NextRequest('http://localhost/api/v1/me/capabilities', { headers: { Authorization: 'Bearer firebase-id-token' } });
const decoded = () => ({ uid: 'clinician_a', sub: 'clinician_a', aud: 'demo-koi-platform', iss: 'https://securetoken.google.com/demo-koi-platform', auth_time: 123 });
it('uses revocation/disabled checks and pins issuer, audience and UID to the configured project', async () => {
  verify.mockResolvedValue(decoded()); expect(await getPlatformRuntime().authenticate(request())).toEqual({ uid: 'clinician_a', authTime: 123 }); expect(verify).toHaveBeenCalledWith('firebase-id-token', true);
});
it.each([{ aud: 'foreign-project' }, { iss: 'https://evil.invalid' }, { sub: 'different' }, { uid: '../foreign' }])('denies an invalid decoded identity %j', async patch => {
  verify.mockResolvedValue({ ...decoded(), ...patch }); await expect(getPlatformRuntime().authenticate(request())).rejects.toMatchObject({ status: 401 });
});
it('denies revoked/disabled/expired tokens without surfacing SDK diagnostics', async () => {
  verify.mockRejectedValue(new Error('sensitive auth diagnostic')); await expect(getPlatformRuntime().authenticate(request())).rejects.toMatchObject({ status: 401, code: 'unauthenticated' });
});
it('defaults to unavailable rather than an in-memory production store', () => {
  adminConfig.getPlatformAdmin.mockImplementationOnce(() => { throw new Error('missing credentials'); }); expect(() => getPlatformRuntime()).toThrow('unavailable');
});
