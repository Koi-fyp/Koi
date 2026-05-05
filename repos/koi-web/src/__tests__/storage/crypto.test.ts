import { CryptoService } from '../../lib/crypto';

const localStorageMock = (() => {
  let store: Record<string, string> = {};
  return {
    getItem: (key: string): string | null => store[key] ?? null,
    setItem: (key: string, value: string): void => { store[key] = value; },
    removeItem: (key: string): void => { delete store[key]; },
    clear: (): void => { store = {}; },
  };
})();

Object.defineProperty(globalThis, 'localStorage', {
  value: localStorageMock,
  writable: true,
});

describe('CryptoService', () => {
  let svc: CryptoService;

  beforeEach(async () => {
    localStorageMock.clear();
    svc = new CryptoService();
    await svc.init();
  });

  it('initializes successfully', () => {
    expect(svc.isInitialized()).toBe(true);
  });

  it('encrypts and decrypts round-trip', async () => {
    const plaintext = 'Hello, KOI!';
    const ciphertext = await svc.encrypt(plaintext);
    expect(ciphertext).not.toBe(plaintext);
    expect(await svc.decrypt(ciphertext)).toBe(plaintext);
  });

  it('re-imports key from localStorage on second init', async () => {
    const cipher = await svc.encrypt('persistent');
    const svc2 = new CryptoService();
    await svc2.init();
    expect(await svc2.decrypt(cipher)).toBe('persistent');
  });

  it('different plaintexts produce different ciphertexts', async () => {
    const c1 = await svc.encrypt('one');
    const c2 = await svc.encrypt('two');
    expect(c1).not.toBe(c2);
  });

  it('throws before init', async () => {
    const uninit = new CryptoService();
    await expect(uninit.encrypt('x')).rejects.toThrow('not initialized');
  });
});
