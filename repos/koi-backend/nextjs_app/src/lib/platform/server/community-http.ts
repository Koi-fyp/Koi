import 'server-only';
import { randomUUID } from 'node:crypto';
import { NextRequest, NextResponse } from 'next/server';
import { getPlatformRuntime, type Runtime } from './runtime';
import type { CommunityService } from './community';
import { checkSchema } from './contract';
import { readBody } from './http';
import { invalid, PlatformError } from './errors';
const methods = { patientHistory: 'GET', archive: 'POST', getArchive: 'GET', submissionNotices: 'GET', experts: 'GET', expert: 'GET', profile: 'PUT', ownProfile: 'GET', analytics: 'GET', message: 'POST', messages: 'GET', appointment: 'POST', appointments: 'GET', transitionAppointment: 'POST', notifications: 'GET', readNotification: 'POST' } as const;
export async function communityRoute(req: NextRequest, op: keyof typeof methods, id?: string, runtime: () => Runtime = getPlatformRuntime) {
  const headers = { 'Cache-Control': 'private, no-store', Vary: 'Authorization', 'Referrer-Policy': 'no-referrer' };
  try {
    if (req.method !== methods[op]) throw invalid();
    if (!/^Bearer [^\s]+$/.test(req.headers.get('authorization') ?? '')) throw new PlatformError(401, 'unauthenticated');
    if (id) checkSchema('Id', id);
    const rt = runtime(), actor = await rt.authenticate(req), service = rt.service as CommunityService;
    const q = req.nextUrl.searchParams, allowed = op === 'submissionNotices' ? ['organization_id', 'limit', 'cursor'] : ['ownProfile', 'analytics'].includes(op) ? ['organization_id'] : ['patientHistory', 'experts', 'messages', 'appointments', 'notifications'].includes(op) ? ['limit', 'cursor'] : [];
    if ([...q.keys()].some(k => !allowed.includes(k) || q.getAll(k).length !== 1)) throw invalid();
    if (q.has('limit') && !/^[0-9]{1,3}$/.test(q.get('limit')!)) throw invalid();
    const limit = q.has('limit') ? Number(q.get('limit')) : 25, cursor = q.get('cursor') ?? undefined;
    let body: unknown, key = '';
    if (req.method !== 'GET') { key = req.headers.get('Idempotency-Key') ?? ''; checkSchema('Id', key); body = await readBody(req); }
    let result;
    switch (op) {
      case 'patientHistory': result = await service.patientHistory(actor, id!, limit, cursor); break;
      case 'archive': result = await service.archive(actor, id!, body, key); break;
      case 'getArchive': result = await service.archive(actor, id!); break;
      case 'submissionNotices': result = await service.submissionNotices(actor, q.get('organization_id') ?? '', limit, cursor); break;
      case 'experts': result = await service.experts(actor, limit, cursor); break;
      case 'expert': result = await service.experts(actor, 25, undefined, id!); break;
      case 'profile': result = await service.profile(actor, '', body, key); break;
      case 'ownProfile': result = await service.profile(actor, q.get('organization_id') ?? ''); break;
      case 'analytics': result = await service.analytics(actor, q.get('organization_id') ?? ''); break;
      case 'message': result = await service.sendMessage(actor, body, key); break;
      case 'appointment': result = await service.appointment(actor, body, key); break;
      case 'transitionAppointment': result = await service.appointment(actor, body, key, id!); break;
      case 'messages': case 'appointments': result = await service.conversation(actor, id!, op, limit, cursor); break;
      case 'notifications': result = await service.notifications(actor, limit, cursor); break;
      case 'readNotification': checkSchema('MarkNotificationReadRequest', body); result = await service.notifications(actor, 25, undefined, id!); break;
    }
    return NextResponse.json(result, { status: ['message', 'appointment'].includes(op) ? 201 : 200, headers });
  } catch (error) {
    const e = error instanceof PlatformError ? error : new PlatformError(503, 'unavailable');
    return NextResponse.json({ code: e.code, request_id: randomUUID(), retryable: [429, 503].includes(e.status) }, { status: e.status, headers });
  }
}
