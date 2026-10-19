import 'server-only';
export type ErrorCode = 'unauthenticated' | 'account_registration_required' | 'forbidden' | 'not_found' | 'conflict' | 'invalid_request' | 'rate_limited' | 'unavailable';
export class PlatformError extends Error {
  constructor(readonly status: number, readonly code: ErrorCode) { super(code); }
}
export const denied = () => new PlatformError(403, 'forbidden');
export const notFound = () => new PlatformError(404, 'not_found');
export const conflict = () => new PlatformError(409, 'conflict');
export const invalid = () => new PlatformError(422, 'invalid_request');
export const unavailable = () => new PlatformError(503, 'unavailable');
