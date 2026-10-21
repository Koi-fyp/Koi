import 'server-only';
import { randomUUID } from 'node:crypto';
import { NextRequest, NextResponse } from 'next/server';
import { getPlatformRuntime, type Runtime } from '../server/runtime';
import { checkSchema } from '../server/contract';
import { PlatformError } from '../server/errors';
import { readBody } from '../server/http';
import type { Actor } from '../server/service';

/** Error with a route-specific code (outside the frozen v0.5.2 ErrorCode set). */
export class RouteError extends Error {
  constructor(readonly status: number, readonly code: string) { super(code); }
}
export interface RouteContext { actor: Actor; service: Runtime['service']; key: string; body: unknown; authorization: string }

/**
 * Standalone POST handler with the same conventions as platformRoute: bearer check before config,
 * verified identity, mandatory Idempotency-Key, JSON body cap, no-store headers and
 * {code, request_id, retryable} errors that never carry bodies, tokens or stack traces.
 */
export async function postRoute(req: NextRequest, run: (ctx: RouteContext) => Promise<unknown>, runtime: () => Runtime = getPlatformRuntime) {
  const requestId = randomUUID();
  const headers = { 'Cache-Control': 'private, no-store', Vary: 'Authorization', 'X-Request-Id': requestId };
  try {
    if (req.method !== 'POST') throw new PlatformError(400, 'invalid_request');
    const authorization = req.headers.get('authorization') ?? '';
    if (!authorization.match(/^Bearer [^\s]+$/)) throw new PlatformError(401, 'unauthenticated');
    const { service, authenticate } = runtime();
    const actor = await authenticate(req);
    const key = req.headers.get('Idempotency-Key') ?? ''; checkSchema('Id', key);
    const body = await readBody(req);
    return NextResponse.json(await run({ actor, service, key, body, authorization }), { status: 200, headers });
  } catch (error) {
    const failure = error instanceof PlatformError || error instanceof RouteError ? error : new PlatformError(503, 'unavailable');
    return NextResponse.json({ code: failure.code, request_id: requestId, retryable: failure.status === 503 || failure.status === 429 }, {
      status: failure.status, headers: { ...headers, ...(failure.status === 401 ? { 'WWW-Authenticate': 'Bearer' } : {}) },
    });
  }
}
