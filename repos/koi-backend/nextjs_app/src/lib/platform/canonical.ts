/** RFC 8785 for schema-validated JSON: ECMAScript numbers, sorted UTF-16 keys, no invalid Unicode. */
export function canonicalJson(value: unknown): string {
  if (value === null || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error('Non-finite JSON number');
    return JSON.stringify(value);
  }
  if (typeof value === 'string') {
    for (let i = 0; i < value.length; i++) {
      const c = value.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff) {
        const next = value.charCodeAt(++i);
        if (!(next >= 0xdc00 && next <= 0xdfff)) throw new Error('Invalid Unicode');
      } else if (c >= 0xdc00 && c <= 0xdfff) throw new Error('Invalid Unicode');
    }
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return '[' + value.map(canonicalJson).join(',') + ']';
  if (typeof value === 'object' && value && Object.prototype.toString.call(value) === '[object Object]') {
    return '{' + Object.keys(value).sort().map(key => canonicalJson(key) + ':' + canonicalJson((value as Record<string, unknown>)[key])).join(',') + '}';
  }
  throw new Error('Unsupported JSON value');
}

export async function browserContentHash(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(canonicalJson(value));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}
