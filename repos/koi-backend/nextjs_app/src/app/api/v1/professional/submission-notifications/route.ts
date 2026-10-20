import { NextRequest } from 'next/server';
import { communityRoute } from '@/lib/platform/server/community-http';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export function GET(req: NextRequest) { return communityRoute(req, 'submissionNotices'); }
