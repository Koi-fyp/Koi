import type { RiskResult } from './chatContract';

export interface CrisisInterventionDisplay {
  source: 'backend' | 'verified_fallback' | 'backend_fallback';
  items: Array<{ id: string; title: string; body: string }>;
  helpline?: { label: string; number: string; source: string };
  confidence?: 'reduced';
}

const boundedText = (value: unknown, maxLength: number) => typeof value === 'string' && value.trim().length > 0 && value.length <= maxLength;

/** Validates the internal display shape; it is not a parser for a deployed API payload. */
export function parseCrisisInterventionDisplay(raw: unknown): CrisisInterventionDisplay | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const value = raw as Record<string, unknown>;
  if (value.source !== 'backend' && value.source !== 'verified_fallback' && value.source !== 'backend_fallback') return null;
  if (!Array.isArray(value.items) || value.items.length > 8) return null;
  const items: CrisisInterventionDisplay['items'] = [];
  for (const rawItem of value.items) {
    if (!rawItem || typeof rawItem !== 'object' || Array.isArray(rawItem)) return null;
    const item = rawItem as Record<string, unknown>;
    if (!boundedText(item.id, 80) || !boundedText(item.title, 160) || !boundedText(item.body, 1200)) return null;
    items.push({ id: item.id as string, title: item.title as string, body: item.body as string });
  }
  let helpline: CrisisInterventionDisplay['helpline'];
  if (value.helpline !== undefined) {
    if (!value.helpline || typeof value.helpline !== 'object' || Array.isArray(value.helpline)) return null;
    const candidate = value.helpline as Record<string, unknown>;
    if (!boundedText(candidate.label, 100) || !boundedText(candidate.number, 40) || !boundedText(candidate.source, 200)) return null;
    helpline = { label: candidate.label as string, number: candidate.number as string, source: candidate.source as string };
  }
  if (items.length === 0 && !helpline) return null;
  if (value.confidence !== undefined && value.confidence !== 'reduced') return null;
  return { source: value.source, items, ...(helpline ? { helpline } : {}), ...(value.confidence === 'reduced' ? { confidence: 'reduced' } : {}) };
}

/** Converts only validated server intervention fields into the constrained Flow 4 display model. */
export function riskInterventionForDisplay(risk: RiskResult | null | undefined): CrisisInterventionDisplay | undefined {
  if (!risk || risk.status !== 'ok' || (risk.risk_category !== 'HIGH' && risk.risk_category !== 'CRITICAL')
    || !risk.intervention_content) return undefined;
  const content = risk.intervention_content;
  const display = parseCrisisInterventionDisplay({
    source: content.source === 'fallback' ? 'backend_fallback' : 'backend',
    items: content.items.map((item, index) => ({
      id: item.chunk_id || `server-item-${index + 1}`,
      title: 'Support information',
      body: item.text,
    })),
    ...(content.helpline ? { helpline: {
      label: content.helpline.name,
      number: content.helpline.number,
      source: content.helpline.verified ? 'Backend marked verified; not independently checked here' : 'Backend marked unverified',
    } } : {}),
    ...(risk.confidence === 'reduced' ? { confidence: 'reduced' } : {}),
  });
  return display ?? undefined;
}
