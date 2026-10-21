import type { ProfessionalApi } from '../client';
import type { HumanMessage } from '../community-types';
import type { Page } from '../patient-types';
import { MAX_THREAD_MESSAGES, sortMessages } from './model';

const PAGE = 100;
/** Ids are hashes, so every page is needed to know the newest message: load all pages up to the cap, then sort by time. */
export async function loadThread(api: Pick<ProfessionalApi, 'request'>, relationshipId: string): Promise<{ messages: HumanMessage[]; capped: boolean }> {
  const collected: HumanMessage[] = []; let cursor: string | null = null, capped = false;
  for (let page = 0; page < MAX_THREAD_MESSAGES / PAGE; page++) {
    const result: Page<HumanMessage> = await api.request(`/api/v1/relationships/${encodeURIComponent(relationshipId)}/messages?limit=${PAGE}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
    collected.push(...(Array.isArray(result?.items) ? result.items : []));
    cursor = result?.next_cursor ?? null; if (!cursor) break;
    if (collected.length >= MAX_THREAD_MESSAGES) { capped = true; break; }
  }
  return { messages: sortMessages(collected), capped: capped || !!cursor };
}
