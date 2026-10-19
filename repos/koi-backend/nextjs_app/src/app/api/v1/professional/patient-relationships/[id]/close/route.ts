import { NextRequest } from 'next/server';
import { lifecycleRoute } from '@/lib/platform/server/lifecycle-http';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export function POST(req: NextRequest, { params }: { params: { id: string } }) { return lifecycleRoute(req, 'close', params.id); }
