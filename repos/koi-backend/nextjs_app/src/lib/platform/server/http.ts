import 'server-only';
import { randomUUID } from 'node:crypto';
import { NextRequest, NextResponse } from 'next/server';
import { getPlatformRuntime, type Runtime } from './runtime';
import { checkSchema } from './contract';
import { invalid, PlatformError } from './errors';

export type Web1Operation = 'capabilities' | 'organization' | 'create' | 'list' | 'get' | 'update' | 'publish' | 'version';
const methods: Record<Web1Operation, string> = { capabilities: 'GET', organization: 'POST', create: 'POST', list: 'GET', get: 'GET', update: 'PUT', publish: 'POST', version: 'GET' };
export async function readBody(req: NextRequest): Promise<unknown> {
  if (req.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/json') throw invalid();
  const reader = req.body?.getReader();
  if (!reader) throw invalid();
  const chunks: Uint8Array[] = []; let size = 0;
  while (true) {
    const result = await reader.read();
    if (result.done) break;
    size += result.value.byteLength;
    if (size > 512_000) { await reader.cancel(); throw invalid(); }
    chunks.push(result.value);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw invalid(); }
}
export async function platformRoute(req: NextRequest, operation: Web1Operation, id?: string, runtime: () => Runtime = getPlatformRuntime) {
  const requestId = randomUUID();
  const headers = { 'Cache-Control': 'private, no-store', Vary: 'Authorization', 'X-Request-Id': requestId };
  try {
    if (req.method !== methods[operation]) throw new PlatformError(400, 'invalid_request');
    // Reject missing bearer before configuration or request-body work; do not read credentials from cookies.
    if (!req.headers.get('authorization')?.match(/^Bearer [^\s]+$/)) throw new PlatformError(401, 'unauthenticated');
    const { service, authenticate } = runtime();
    const actor = await authenticate(req);
    let body: unknown, key: string;
    if (req.method !== 'GET') {
      key = req.headers.get('Idempotency-Key') ?? ''; checkSchema('Id', key);
      body = await readBody(req);
    }
    let result: unknown;
    switch (operation) {
      case 'capabilities': result = await service.capabilities(actor); break;
      case 'organization': result = await service.createOrganization(actor, body, key!); break;
      case 'create': result = await service.createDraft(actor, body, key!); break;
      case 'get': result = await service.getDraft(actor, id!); break;
      case 'update': result = await service.updateDraft(actor, id!, body, key!); break;
      case 'publish': result = await service.publish(actor, id!, body, key!); break;
      case 'version': result = await service.getVersion(actor, id!); break;
      case 'list': {
        const query = req.nextUrl.searchParams;
        if (Array.from(query.keys()).some(k => !['organization_id', 'limit', 'cursor'].includes(k)) || ['organization_id', 'limit', 'cursor'].some(k => query.getAll(k).length > 1)) throw invalid();
        const rawLimit = query.get('limit');
        if (rawLimit !== null && !/^[0-9]{1,3}$/.test(rawLimit)) throw invalid();
        result = await service.listDrafts(actor, query.get('organization_id') ?? '', rawLimit === null ? 25 : Number(rawLimit), query.get('cursor') ?? undefined);
        break;
      }
    }
    return NextResponse.json(result, { status: operation === 'create' ? 201 : 200, headers });
  } catch (error) {
    // Never log or serialize arbitrary SDK failures, request bodies, IDs, tokens or documents.
    const failure = error instanceof PlatformError ? error : new PlatformError(503, 'unavailable');
    return NextResponse.json({ code: failure.code, request_id: requestId, retryable: failure.status === 503 || failure.status === 429 }, {
      status: failure.status, headers: { ...headers, ...(failure.status === 401 ? { 'WWW-Authenticate': 'Bearer' } : {}) },
    });
  }
}
