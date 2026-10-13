import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
const assets = new Set(['koi-male.vrm', 'koi-female.vrm']);

export async function GET(_request: Request, { params }: { params: { asset: string } }) {
  if (process.env.NODE_ENV !== 'development' || !assets.has(params.asset)) {
    return new Response('Not found', { status: 404 });
  }
  const directory = process.env.KOI_SANDBOX_MODELS_DIR;
  if (!directory) return new Response('Start with npm run dev:avatar.', { status: 503 });
  try {
    const bytes = await readFile(join(directory, params.asset));
    return new Response(new Uint8Array(bytes), {
      headers: { 'Content-Type': 'application/octet-stream',
        'Content-Length': String(bytes.byteLength), 'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff' },
    });
  } catch {
    return new Response('The requested VRM asset is unavailable.', { status: 404 });
  }
}
