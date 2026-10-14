import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
export const dynamic = 'force-dynamic';
export async function GET(_request: Request, { params }: { params: { file: string } }) {
  if (process.env.NODE_ENV !== 'development') return new Response('Not found', { status: 404 });
  if (!['speech-sample.wav', 'speech-sample.json', 'piper-urdu.wav', 'piper-urdu.json', 'piper-english.wav', 'piper-english.json', 'piper-mixed.wav', 'piper-mixed.json'].includes(params.file)) return new Response('Not found', { status: 404 });
  try {
    // The established harness sets an absolute canonical model directory.
    const canonical = path.resolve(process.env.KOI_SANDBOX_MODELS_DIR!, '../..');
    const bytes = await readFile(path.join(canonical, 'dev/avatar-sandbox/.fixtures', params.file));
    const expectedHash = new URL(_request.url).searchParams.get('sha256');
    if (expectedHash && (!/^[a-f0-9]{64}$/.test(expectedHash) || createHash('sha256').update(bytes).digest('hex') !== expectedHash)) return new Response('The sample changed; reload its manifest.', { status: 409 });
    return new Response(new Uint8Array(bytes), { headers: { 'Content-Type': params.file.endsWith('.wav') ? 'audio/wav' : 'application/json', 'Cache-Control': 'no-store' } });
  } catch { return new Response('Generate the local speech fixture first.', { status: 404 }); }
}
