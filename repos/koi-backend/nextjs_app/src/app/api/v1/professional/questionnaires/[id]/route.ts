import { NextRequest } from 'next/server';
import { platformRoute } from '@/lib/platform/server/http';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export function GET(req: NextRequest, { params }: { params: { id: string } }) { return platformRoute(req, 'get', params.id); }
export function PUT(req: NextRequest, { params }: { params: { id: string } }) { return platformRoute(req, 'update', params.id); }
