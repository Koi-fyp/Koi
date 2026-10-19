import type { User } from 'firebase/auth';

export class PlatformClientError extends Error {
  constructor(readonly status: number, readonly code: string) { super(code); }
}
export interface ProfessionalApi {
  request<T>(path: string, method?: 'GET' | 'POST' | 'PUT' | 'PATCH', body?: unknown): Promise<T>;
  dispose(): void;
}
export function professionalApi(uid: string, currentUser: () => Pick<User, 'uid' | 'getIdToken'> | null, fetcher: typeof fetch = fetch, beforeMutation?: () => Promise<void>): ProfessionalApi {
  const controller = new AbortController();
  const pendingKeys = new Map<string, string>();
  const guard = () => { if (controller.signal.aborted || currentUser()?.uid !== uid) throw new PlatformClientError(401, 'unauthenticated'); };
  return {
    async request<T>(path: string, method = 'GET', body?: unknown): Promise<T> {
      guard();
      if (!path.startsWith('/api/v1/') || path.includes('://')) throw new PlatformClientError(422, 'invalid_request');
      if (method !== 'GET' && method !== 'PATCH' && beforeMutation) { await beforeMutation(); guard(); }
      let token: string;
      try { token = await currentUser()!.getIdToken(); }
      catch (failure: any) { guard(); throw new PlatformClientError(failure?.code === 'auth/network-request-failed' ? 503 : 401, failure?.code === 'auth/network-request-failed' ? 'unavailable' : 'unauthenticated'); }
      guard();
      const headers: Record<string, string> = { Authorization: `Bearer ${token}` };
      const fingerprint = JSON.stringify([method, path, body ?? null]);
      if (method !== 'GET') {
        if (!pendingKeys.has(fingerprint)) pendingKeys.set(fingerprint, crypto.randomUUID());
        headers['Idempotency-Key'] = pendingKeys.get(fingerprint)!; headers['Content-Type'] = 'application/json';
      }
      let response: Response;
      try { response = await fetcher(path, { method, headers, body: method === 'GET' ? undefined : JSON.stringify(body), cache: 'no-store', credentials: 'omit', signal: controller.signal }); }
      catch { guard(); throw new PlatformClientError(503, 'unavailable'); }
      guard();
      let data: any;
      try { data = await response.json(); } catch { throw new PlatformClientError(503, 'unavailable'); }
      guard();
      if (!response.ok) {
        if (response.status < 500) pendingKeys.delete(fingerprint);
        throw new PlatformClientError(response.status, typeof data?.code === 'string' ? data.code : 'unavailable');
      }
      pendingKeys.delete(fingerprint);
      return data as T;
    },
    dispose() { controller.abort(); pendingKeys.clear(); },
  };
}
