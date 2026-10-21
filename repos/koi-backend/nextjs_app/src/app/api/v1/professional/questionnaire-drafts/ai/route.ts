import { NextRequest } from 'next/server';
import { postRoute } from '@/lib/platform/ai/route-kit';
import { AI_NOTICE, aiBase, generate, parseRequest } from '@/lib/platform/ai/questionnaire-draft';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const maxDuration = 70;
// Proposed contract 0.5.3 (not part of frozen v0.5.2).
export function POST(req: NextRequest) {
  return postRoute(req, async ({ actor, service, body, authorization }) => {
    await service.authorizeAiDraft(actor);
    const request = parseRequest(body);
    aiBase();
    const { content, provenance } = await generate(request, authorization);
    return { content, provenance, notice: AI_NOTICE };
  });
}
