import type { CareNotification, HumanMessage } from '../community-types';

export const MESSAGE_LIMIT = 4000;
export const MAX_THREAD_MESSAGES = 300;
export const MAX_CONVERSATIONS = 10;
/** Server counts JSON-schema string length in code points. */
export const bodyLength = (text: string) => Array.from(text).length;
export const canSend = (text: string) => !!text.trim() && bodyLength(text) <= MESSAGE_LIMIT;

/** Message ids are hashes, so the API order is meaningless: always order by time (id as a stable tiebreak). */
export const sortMessages = <T extends { created_at: string; id: string }>(items: T[]): T[] => [...items].sort((a, b) => a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id));
export function mergeMessages(old: HumanMessage[], incoming: HumanMessage[]): HumanMessage[] {
  const byId = new Map(old.map(m => [m.id, m])); for (const m of incoming) byId.set(m.id, m);
  return sortMessages([...byId.values()]);
}
const dayStart = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
export const dayKey = (iso: string) => { const d = new Date(iso); return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`; };
export function dayLabel(iso: string, now: Date = new Date(), locale?: string): string {
  const diff = Math.round((dayStart(now) - dayStart(new Date(iso))) / 86400000);
  if (diff === 0) return 'Today'; if (diff === 1) return 'Yesterday';
  return new Date(iso).toLocaleDateString(locale, { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
}
export const timeLabel = (iso: string, locale?: string) => new Date(iso).toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit' });
export const preview = (text: string, max = 60) => { const flat = text.replace(/\s+/g, ' ').trim(); const chars = Array.from(flat); return chars.length > max ? `${chars.slice(0, max - 1).join('')}…` : flat; };
export const shortId = (uid: string) => uid.slice(-4);

export const unreadMessageNotices = (notices: CareNotification[]) => notices.filter(n => n.kind === 'new_message' && !n.read_at && 'message_id' in n.reference);
export const noticeMessageId = (n: CareNotification) => 'message_id' in n.reference ? n.reference.message_id : '';
/** Unread notices belonging to one conversation, matched through its already loaded message ids. */
export function unreadForThread(notices: CareNotification[], messages: HumanMessage[]): CareNotification[] {
  const ids = new Set(messages.map(m => m.id));
  return unreadMessageNotices(notices).filter(n => ids.has(noticeMessageId(n)));
}
export const badgeText = (count: number) => count > 9 ? '9+' : String(count);
const PREFIX = /^\(\d+\)\s/;
export function titleWithCount(title: string, count: number): string {
  const base = title.replace(PREFIX, '');
  return count > 0 ? `(${count}) ${base}` : base;
}
export type MessagingRole = 'patient' | 'professional' | 'both';
/** Generic text only: never the message body. */
export const desktopNoticeText = (role: MessagingRole) => role === 'patient' ? 'New message from your psychologist' : role === 'professional' ? 'New message from a patient' : 'New message';
