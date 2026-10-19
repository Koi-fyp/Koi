import 'server-only';
import { randomUUID } from 'node:crypto';
import { NextRequest, NextResponse } from 'next/server';
import { getPlatformRuntime, type Runtime } from './runtime';
import type { LifecycleService } from './lifecycle';
import { checkSchema } from './contract';
import { readBody } from './http';
import { invalid, PlatformError } from './errors';
const methods = { invite: 'POST', revokeInvite: 'POST', redeem: 'POST', close: 'POST', connection: 'POST', connections: 'GET', transition: 'POST', demo: 'POST', assign: 'POST', assignments: 'GET', detail: 'GET', save: 'PATCH', submit: 'POST', relationships: 'GET', submissions: 'GET', submission: 'GET', evaluation: 'GET', workspace: 'GET', review: 'POST', decision: 'POST', reviews: 'GET', decisions: 'GET' } as const;
export type LifecycleOperation = keyof typeof methods;
export async function lifecycleRoute(req: NextRequest, op: LifecycleOperation, id?: string, runtime: () => Runtime = getPlatformRuntime) {
  const headers = { 'Cache-Control': 'private, no-store', Vary: 'Authorization', 'Referrer-Policy': 'no-referrer' }, requestId = randomUUID();
  try {
    if (req.method !== methods[op]) throw invalid();
    if (!/^Bearer [^\s]+$/.test(req.headers.get('authorization') ?? '')) throw new PlatformError(401, 'unauthenticated');
    const rt = runtime(), actor = await rt.authenticate(req), service = rt.service as LifecycleService;
    let body: unknown, key = '';
    if (req.method !== 'GET') { key = req.headers.get('Idempotency-Key') ?? ''; checkSchema('Id', key); body = await readBody(req); }
    const query = req.nextUrl.searchParams;
    const allowed = ['relationships', 'submissions'].includes(op) ? ['organization_id', 'limit', 'cursor'] : ['connections', 'assignments', 'reviews', 'decisions'].includes(op) ? ['limit', 'cursor'] : [];
    if ([...query.keys()].some(k => !allowed.includes(k) || query.getAll(k).length > 1)) throw invalid();
    const rawLimit = query.get('limit'); if (rawLimit !== null && !/^[0-9]{1,3}$/.test(rawLimit)) throw invalid();
    const org = query.get('organization_id') ?? '', limit = rawLimit ? Number(rawLimit) : 25, cursor = query.get('cursor') ?? undefined;
    let result: unknown;
    switch (op) {
      case 'invite': result = await service.createInvitation(actor, body, key); break;
      case 'revokeInvite': result = await service.revokeInvitation(actor, id!, body, key); break;
      case 'redeem': result = await service.redeemInvitation(actor, id!, body, key); break;
      case 'close': result = await service.closeRelationship(actor, id!, body, key); break;
      case 'connection': result = await service.createConnection(actor, body, key); break;
      case 'transition': result = await service.transitionConnection(actor, id!, body, key); break;
      case 'demo': result = await service.transitionConnection(actor, id!, body, key, true); break;
      case 'assign': result = await service.assign(actor, body, key); break;
      case 'detail': result = await service.patientDetail(actor, id!); break;
      case 'save': result = await service.saveAttempt(actor, id!, body, key); break;
      case 'submit': result = await service.saveAttempt(actor, id!, body, key, true); break;
      case 'submission': result = await service.getSubmission(actor, id!); break;
      case 'evaluation': result = await service.getEvaluation(actor, id!); break;
      case 'workspace': result = await service.workspace(actor, id!); break;
      case 'review': result = await service.createReview(actor, body, key); break;
      case 'decision': result = await service.createReview(actor, body, key, true); break;
      default: result = await service.list(actor, op, org, limit, cursor, id);
    }
    return NextResponse.json(result, { status: ['invite', 'connection', 'review'].includes(op) ? 201 : 200, headers });
  } catch (error) {
    const e = error instanceof PlatformError ? error : new PlatformError(503, 'unavailable');
    return NextResponse.json({ code: e.code, request_id: requestId, retryable: [429, 503].includes(e.status) }, { status: e.status, headers });
  }
}
