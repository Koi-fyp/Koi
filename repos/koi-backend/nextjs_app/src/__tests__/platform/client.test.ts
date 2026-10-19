/** @jest-environment node */
import { professionalApi } from '@/lib/platform/client';
it('guards UID changes during token resolution and discards late responses', async () => {
  let uid = 'a'; const fetcher = jest.fn();
  const api = professionalApi('a', () => ({ uid, getIdToken: async () => { uid = 'b'; return 'private-token'; } }), fetcher);
  await expect(api.request('/api/v1/me/capabilities')).rejects.toMatchObject({ status: 401 }); expect(fetcher).not.toHaveBeenCalled();
  uid = 'a'; const late = jest.fn(async () => { uid = 'b'; return new Response(JSON.stringify({ private: 'a' })); });
  const api2 = professionalApi('a', () => ({ uid, getIdToken: async () => 'private-token' }), late as any);
  await expect(api2.request('/api/v1/me/capabilities')).rejects.toMatchObject({ status: 401 });
});
it('retains an idempotency key across uncertain network results and uses private bearer requests', async () => {
  const fetcher = jest.fn().mockRejectedValueOnce(new Error('network')).mockResolvedValueOnce(new Response('{"id":"saved"}'));
  const api = professionalApi('a', () => ({ uid: 'a', getIdToken: async () => 'private-token' }), fetcher);
  await expect(api.request('/api/v1/professional/organizations', 'POST', { name: 'Practice' })).rejects.toMatchObject({ status: 503 });
  await api.request('/api/v1/professional/organizations', 'POST', { name: 'Practice' });
  expect(fetcher.mock.calls[0][1].headers['Idempotency-Key']).toBe(fetcher.mock.calls[1][1].headers['Idempotency-Key']);
  expect(fetcher.mock.calls[1][1]).toMatchObject({ cache: 'no-store', credentials: 'omit', headers: { Authorization: 'Bearer private-token' } });
  api.dispose(); await expect(api.request('/api/v1/me/capabilities')).rejects.toMatchObject({ status: 401 });
});
