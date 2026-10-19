import { NextRequest } from 'next/server';
import { lifecycleRoute } from '@/lib/platform/server/lifecycle-http';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export function POST(req: NextRequest) { return lifecycleRoute(req, 'connection'); }
export function GET(req: NextRequest) { return lifecycleRoute(req, 'connections'); }
