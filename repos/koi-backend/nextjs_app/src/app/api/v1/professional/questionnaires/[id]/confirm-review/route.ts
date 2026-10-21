import { NextRequest } from 'next/server';
import { postRoute } from '@/lib/platform/ai/route-kit';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
// Proposed contract 0.5.3: server-side "I reviewed this draft" (ai_drafted -> manual).
export function POST(req: NextRequest, { params }: { params: { id: string } }) {
  return postRoute(req, ({ actor, service, body, key }) => service.confirmAiDraftReview(actor, params.id, body, key));
}
