const KEY_STORAGE_KEY = 'koi_crypto_key';

export class CryptoService {
  private key: CryptoKey | null = null;

  async init(): Promise<void> {
    const storedKey = localStorage.getItem(KEY_STORAGE_KEY);
    if (storedKey) {
      this.key = await this.importKey(storedKey);
    } else {
      this.key = await this.generateKey();
      const exported = await this.exportKey(this.key);
      localStorage.setItem(KEY_STORAGE_KEY, exported);
    }
  }

  private async generateKey(): Promise<CryptoKey> {
    return crypto.subtle.generateKey(
      { name: 'AES-GCM', length: 256 },
      true,
      ['encrypt', 'decrypt'],
    );
  }

  private async exportKey(key: CryptoKey): Promise<string> {
    const exported = await crypto.subtle.exportKey('raw', key);
    return btoa(String.fromCharCode(...new Uint8Array(exported)));
  }

  private async importKey(stored: string): Promise<CryptoKey> {
    const raw = Uint8Array.from(atob(stored), (c) => c.charCodeAt(0));
    return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, true, [
      'encrypt',
      'decrypt',
    ]);
  }

  async encrypt(data: string): Promise<string> {
    if (!this.key) throw new Error('CryptoService not initialized — call init() first');
    const encoder = new TextEncoder();
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const encryptedBuffer = await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv },
      this.key,
      encoder.encode(data),
    );
    const combined = new Uint8Array(12 + encryptedBuffer.byteLength);
    combined.set(iv);
    combined.set(new Uint8Array(encryptedBuffer), 12);
    return btoa(String.fromCharCode(...combined));
  }

  async decrypt(encrypted: string): Promise<string> {
    if (!this.key) throw new Error('CryptoService not initialized — call init() first');
    const combined = Uint8Array.from(atob(encrypted), (c) => c.charCodeAt(0));
    const iv = combined.slice(0, 12);
    const data = combined.slice(12);
    const decryptedBuffer = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv },
      this.key,
      data,
    );
    return new TextDecoder().decode(decryptedBuffer);
  }

  isInitialized(): boolean {
    return this.key !== null;
  }
}

export const cryptoService = new CryptoService();
