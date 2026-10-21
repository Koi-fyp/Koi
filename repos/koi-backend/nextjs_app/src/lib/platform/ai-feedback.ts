/** Psychologist feedback about one AI evaluation. Professional-only; never part of any patient DTO. */
export const AI_FEEDBACK_TAGS = ['Accurate', 'Missed something', 'Too generic', 'Unsafe wording', 'Helpful follow-ups'] as const;
export type AiFeedbackTag = typeof AI_FEEDBACK_TAGS[number];
export const AI_FEEDBACK_COMMENT_MAX = 500;
export interface AiFeedbackRequest { rating: number; tags: AiFeedbackTag[]; comment?: string }
export interface AiFeedbackNote { evaluation_id: string; rating: number; tags: AiFeedbackTag[]; comment?: string; created_at: string; psychologist_uid: string }

/** Strict shape check shared by the route (authoritative) and the panel (early feedback). */
export function isAiFeedbackRequest(body: unknown): body is AiFeedbackRequest {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return false;
  const b = body as Record<string, unknown>;
  if (Object.keys(b).some(k => !['rating', 'tags', 'comment'].includes(k))) return false;
  if (typeof b.rating !== 'number' || !Number.isInteger(b.rating) || b.rating < 1 || b.rating > 5) return false;
  if (!Array.isArray(b.tags) || b.tags.length > AI_FEEDBACK_TAGS.length || new Set(b.tags).size !== b.tags.length || b.tags.some(t => !(AI_FEEDBACK_TAGS as readonly unknown[]).includes(t))) return false;
  if (b.comment !== undefined && (typeof b.comment !== 'string' || Array.from(b.comment).length > AI_FEEDBACK_COMMENT_MAX)) return false;
  return true;
}
