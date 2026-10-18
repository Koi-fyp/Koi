import type { User } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { decrypt, peekActiveCryptoContext } from '@/lib/crypto';

export type OwnedReadResult<T> =
  | { status: 'ready'; value: T }
  | { status: 'locked'; reason: 'key-unavailable' | 'owner-unverified' | 'decrypt-failed' }
  | { status: 'unavailable'; reason: 'aborted' | 'storage-unavailable' };
/** Thrown by decryptOwned when the owner changed or the read was aborted; readers must let it propagate. */
export class OwnerReadCancelled extends Error {}
/** Thrown by decryptOwned when one ciphertext cannot be authenticated; readers may mark that item locked. */
export class OwnedDecryptFailed extends Error {}

function linked(user: User) {
  return !user.isAnonymous && user.providerData.some(provider => provider.providerId === 'password');
}

/**
 * Scoped, read-only decryption with the key already on this device. The owner is checked before and
 * after every await; plaintext produced after an abort or UID change is discarded. No key, salt or
 * record is ever created, written, synced or fetched, and no raw key leaves this function.
 */
export async function withOwnedDecryptor<T>(uid: string, signal: AbortSignal,
  read: (decryptOwned: (ciphertext: string) => Promise<string>) => Promise<T>): Promise<OwnedReadResult<T>> {
  const owned = () => !signal.aborted && !!uid && auth?.currentUser?.uid === uid;
  const lost = (): OwnedReadResult<T> => signal.aborted ? { status: 'unavailable', reason: 'aborted' } : { status: 'locked', reason: 'owner-unverified' };
  if (!owned()) return lost();
  const user = auth!.currentUser as User;
  let context: ReturnType<typeof peekActiveCryptoContext>;
  try {
    // Linked accounts have no stored secret on this device; they stay locked rather than prompting or deriving.
    context = linked(user) ? null : peekActiveCryptoContext(uid, { isLinked: false });
  } catch { return { status: 'unavailable', reason: 'storage-unavailable' }; }
  if (!context) return { status: 'locked', reason: 'key-unavailable' };
  const { secret } = context;
  const decryptOwned = async (ciphertext: string) => {
    if (!owned()) throw new OwnerReadCancelled();
    let plaintext: string;
    try { plaintext = await decrypt(ciphertext, secret); } catch { throw owned() ? new OwnedDecryptFailed() : new OwnerReadCancelled(); }
    if (!owned()) throw new OwnerReadCancelled();
    return plaintext;
  };
  try {
    const value = await read(decryptOwned);
    return owned() ? { status: 'ready', value } : lost();
  } catch (error) {
    if (!owned() || error instanceof OwnerReadCancelled) return lost();
    if (error instanceof OwnedDecryptFailed) return { status: 'locked', reason: 'decrypt-failed' };
    return { status: 'unavailable', reason: 'storage-unavailable' };
  }
}
