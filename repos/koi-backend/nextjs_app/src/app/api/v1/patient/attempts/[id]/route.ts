import { NextRequest } from 'next/server';
import { lifecycleRoute } from '@/lib/platform/server/lifecycle-http';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export function PATCH(req: NextRequest, { params }: { params: { id: string } }) { return lifecycleRoute(req, 'save', params.id); }
