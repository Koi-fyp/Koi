export const CAMERA_DISCLOSURE = 'This camera view is for you only. KOI does not record, store, send or analyze your video.';

const MEDIA_TYPE = /^(video|image)\//i;
const MEDIA_TEXT = /data:(video|image)\/|content-type:\s*(video|image)\//i;

function describeBody(body: unknown): string | null {
  if (body === undefined || body === null) return null;
  if (typeof body === 'string') return MEDIA_TEXT.test(body) ? 'a media data URL or media part in a text body' : null;
  if (typeof Blob !== 'undefined' && body instanceof Blob) return MEDIA_TYPE.test(body.type) || !body.type ? `a ${body.type || 'untyped'} blob` : null;
  if (typeof FormData !== 'undefined' && body instanceof FormData) {
    for (const [field, value] of body.entries()) {
      if (typeof value !== 'string') return `a file in multipart field "${field}"`;
      if (MEDIA_TEXT.test(value)) return `media text in multipart field "${field}"`;
    }
    return null;
  }
  if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) return 'a binary body';
  if (typeof ReadableStream !== 'undefined' && body instanceof ReadableStream) return 'a streamed body';
  if (typeof MediaStream !== 'undefined' && body instanceof MediaStream) return 'a media stream';
  return null;
}

// Works without a global Headers class (jsdom does not provide one).
function contentTypeOf(headers: unknown): string {
  if (!headers) return '';
  const entries: Iterable<[string, string]> = typeof (headers as Headers).forEach === 'function' && !Array.isArray(headers)
    ? (() => { const list: [string, string][] = []; (headers as Headers).forEach((value, key) => list.push([key, value])); return list; })()
    : Array.isArray(headers) ? headers as [string, string][] : Object.entries(headers as Record<string, string>);
  for (const [key, value] of entries) if (key.toLowerCase() === 'content-type') return String(value);
  return '';
}

/**
 * Test helper. Accepts `fetch` mock calls ([input, init] tuples) and throws if any of them carries
 * camera-shaped data: media blobs, files in multipart, binary or streamed bodies, media data URLs.
 */
export function assertNoVideoLeavesDevice(fetchCalls: ReadonlyArray<ReadonlyArray<unknown>>): void {
  fetchCalls.forEach((call, index) => {
    const [input, init] = call;
    const request = typeof Request !== 'undefined' && input instanceof Request ? input : null;
    const body = (init as RequestInit | undefined)?.body ?? (request as unknown as { body?: unknown } | null)?.body;
    const found = describeBody(body);
    if (found) throw new Error(`Camera privacy violation: request #${index + 1} carried ${found}.`);
    const contentType = contentTypeOf((init as RequestInit | undefined)?.headers ?? request?.headers);
    if (MEDIA_TYPE.test(contentType)) throw new Error(`Camera privacy violation: request #${index + 1} declared ${contentType}.`);
  });
}
