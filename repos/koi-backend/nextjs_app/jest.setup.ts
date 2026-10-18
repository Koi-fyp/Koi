import '@testing-library/jest-dom';

// JSDOM omits randomUUID; production uses the browser's native secure UUID implementation.
import { webcrypto } from 'crypto';
if (!globalThis.crypto.randomUUID) Object.defineProperty(globalThis.crypto, 'randomUUID', { configurable: true, value: webcrypto.randomUUID.bind(webcrypto) });
