/** Only allowlisted categories reach UI. Never expose Firebase payloads, UIDs or error text. */
export function preferenceSyncFailure(reason: unknown): string {
  const code = reason && typeof reason === 'object' && 'code' in reason ? reason.code : null;
  if (code === 'permission-denied' || code === 'firestore/permission-denied') return 'Account sync was denied. Your local choice is still available; retrying cannot change account permissions.';
  if (code === 'unauthenticated' || code === 'firestore/unauthenticated') return 'Account sync could not authenticate this request. Your local choice is still available.';
  if (code === 'unavailable' || code === 'deadline-exceeded' || code === 'firestore/unavailable') return 'The account sync service is unavailable. Your local choice is still available; you can retry later.';
  return 'Account sync could not be confirmed. Your local choice is still available; the cause has not been verified.';
}
