import { NextRequest } from 'next/server';
import { communityRoute } from '@/lib/platform/server/community-http';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export function POST(req: NextRequest, { params }: { params: { id: string } }) { return communityRoute(req, 'archive', params.id); }
export function GET(req: NextRequest, { params }: { params: { id: string } }) { return communityRoute(req, 'getArchive', params.id); }
