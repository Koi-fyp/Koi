import { NextRequest } from 'next/server';
import { platformRoute } from '@/lib/platform/server/http';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export function POST(req: NextRequest) { return platformRoute(req, 'create'); }
export function GET(req: NextRequest) { return platformRoute(req, 'list'); }
