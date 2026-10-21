import { randomUUID } from 'node:crypto';
import { NextRequest, NextResponse } from 'next/server';
import { getPlatformRuntime } from '@/lib/platform/server/runtime';
import type { LifecycleService } from '@/lib/platform/server/lifecycle';
import { checkSchema } from '@/lib/platform/server/contract';
import { readBody } from '@/lib/platform/server/http';
import { invalid, PlatformError } from '@/lib/platform/server/errors';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/** Same envelope as lifecycleRoute: owner-only authority, Idempotency-Key, no-store, generic errors. */
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const headers = { 'Cache-Control': 'private, no-store', Vary: 'Authorization', 'Referrer-Policy': 'no-referrer' }, requestId = randomUUID();
  try {
    if (req.method !== 'POST' || [...req.nextUrl.searchParams.keys()].length) throw invalid();
    if (!/^Bearer [^\s]+$/.test(req.headers.get('authorization') ?? '')) throw new PlatformError(401, 'unauthenticated');
    const rt = getPlatformRuntime(), actor = await rt.authenticate(req), service = rt.service as LifecycleService;
    const key = req.headers.get('Idempotency-Key') ?? ''; checkSchema('Id', key);
    const result = await service.createAiFeedback(actor, params.id, await readBody(req), key);
    return NextResponse.json(result, { status: 200, headers });
  } catch (error) {
    const e = error instanceof PlatformError ? error : new PlatformError(503, 'unavailable');
    return NextResponse.json({ code: e.code, request_id: requestId, retryable: [429, 503].includes(e.status) }, { status: e.status, headers });
  }
}
