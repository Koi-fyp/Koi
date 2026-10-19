import { NextRequest } from 'next/server';
import { getPlatformRuntime } from '@/lib/platform/server/runtime';
import { hash } from '@/lib/platform/server/contract';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
/** Separate, short-lived platform invalidation stream. Companion SSE is untouched. */
export async function GET(req: NextRequest) {
  const headers = { 'Cache-Control': 'private, no-store', Vary: 'Authorization', 'X-Accel-Buffering': 'no' };
  try {
    const rt = getPlatformRuntime(), actor = await rt.authenticate(req);
    const first = await rt.service.capabilities(actor);
    if (first.account_state !== 'registered') return new Response(null, { status: 403, headers });
    let stopped = false, timer: ReturnType<typeof setTimeout> | undefined;
    const stream = new ReadableStream({
      start(controller) {
        const encoder = new TextEncoder(), started = Date.now(); let previous = '', sequence = Math.max(1, first.authorization_revision);
        const close = () => { if (stopped) return; stopped = true; clearTimeout(timer); try { controller.close(); } catch {} };
        req.signal.addEventListener('abort', close, { once: true });
        const tick = async () => {
          try {
            if (stopped || req.signal.aborted || Date.now() - started > 250000) { close(); return; }
            const currentActor = await rt.authenticate(req), caps = await rt.service.capabilities(currentActor);
            if (caps.account_state !== 'registered') { close(); return; }
            const signature = hash(caps);
            if (signature !== previous) {
              previous = signature;
              controller.enqueue(encoder.encode(`event: authorization_changed\ndata: ${JSON.stringify({ event: 'authorization_changed', authorization_revision: Math.max(sequence++, caps.authorization_revision), occurred_at: new Date().toISOString() })}\n\n`));
            } else controller.enqueue(encoder.encode(': heartbeat\n\n'));
            timer = setTimeout(tick, 2000);
          } catch { close(); }
        };
        void tick();
      },
      cancel() { stopped = true; clearTimeout(timer); },
    });
    return new Response(stream, { headers: { ...headers, 'Content-Type': 'text/event-stream' } });
  } catch { return new Response(null, { status: 401, headers }); }
}
