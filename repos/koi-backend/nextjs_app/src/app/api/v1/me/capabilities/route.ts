import { NextRequest } from 'next/server';
import { platformRoute } from '@/lib/platform/server/http';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export function GET(req: NextRequest) { return platformRoute(req, 'capabilities'); }
