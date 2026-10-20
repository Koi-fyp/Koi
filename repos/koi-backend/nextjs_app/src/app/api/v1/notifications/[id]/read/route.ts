import { NextRequest } from 'next/server';
import { communityRoute } from '@/lib/platform/server/community-http';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export function POST(req: NextRequest, { params }: { params: { id: string } }) { return communityRoute(req, 'readNotification', params.id); }
