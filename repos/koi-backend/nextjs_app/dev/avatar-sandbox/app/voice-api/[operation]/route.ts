import { readFile } from 'node:fs/promises';
import path from 'node:path';
export const dynamic = 'force-dynamic';
const ORIGIN = 'http://127.0.0.1:3001', LIMIT = 2 * 1024 * 1024;
export async function POST(request: Request, { params }: { params: { operation: string } }) {
 if (process.env.NODE_ENV !== 'development') return new Response('Not found',{status:404});
 if (request.headers.get('origin') !== ORIGIN || request.headers.get('host') !== '127.0.0.1:3001' || request.headers.get('x-koi-voice-intent') !== '1') return Response.json({error:{code:'forbidden',message:'Local voice access denied.'}},{status:403});
 if (!['health','transcribe','synthesize'].includes(params.operation)) return new Response('Not found',{status:404});
 const reader = request.body?.getReader(), chunks: Uint8Array[] = []; let size = 0;
 if (reader) { while (true) { const result = await reader.read(); if (result.done) break; size += result.value.byteLength; if (size > LIMIT) { await reader.cancel(); return Response.json({error:{code:'size-limit',message:'Payload exceeds 2 MiB.'}},{status:413}); } chunks.push(result.value); } }
 const bytes = new Uint8Array(size); let position = 0; for (const chunk of chunks) { bytes.set(chunk,position); position += chunk.length; }
 const abort = new AbortController(), cancel = () => abort.abort(); request.signal.addEventListener('abort',cancel,{once:true}); const timer = setTimeout(cancel,90000);
 try {
  const root = path.resolve(process.env.KOI_SANDBOX_MODELS_DIR!, '../..');
  const token = (await readFile(path.join(root,'dev/avatar-sandbox/.voice-tools/service-token'),'utf8')).trim();
  if (!/^[a-f0-9]{64}$/.test(token)) throw new Error('configuration');
  const result = await fetch(`http://127.0.0.1:3002/${params.operation}`,{method:'POST',headers:{Authorization:`Bearer ${token}`,Origin:ORIGIN,'Content-Type':request.headers.get('content-type') ?? 'application/octet-stream','X-Koi-Language':request.headers.get('x-koi-language') ?? 'auto'},body:bytes,signal:abort.signal,redirect:'error',cache:'no-store'});
  return new Response(await result.arrayBuffer(),{status:result.status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
 } catch { return Response.json({error:{code:'unavailable',message:'Local voice worker unavailable or timed out. Start node scripts/voice-dev.cjs.'}},{status:503}); }
 finally { clearTimeout(timer); request.signal.removeEventListener('abort',cancel); }
}
