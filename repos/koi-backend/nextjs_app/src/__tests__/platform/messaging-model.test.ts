import type { CareNotification, HumanMessage } from '@/lib/platform/community-types';
import { badgeText, bodyLength, canSend, dayLabel, desktopNoticeText, mergeMessages, preview, sortMessages, titleWithCount, unreadForThread, unreadMessageNotices } from '@/lib/platform/messaging/model';

const msg = (id: string, created_at: string, body = id): HumanMessage => ({ id, relationship_id: 'rel', sender_uid: 'a', body, created_at });
const notice = (id: string, messageId: string, read_at?: string, kind: CareNotification['kind'] = 'new_message'): CareNotification => ({ id, event_id: id, kind, reference: kind === 'new_message' ? { message_id: messageId } : { appointment_id: messageId }, created_at: '2026-01-01T00:00:00Z', ...(read_at ? { read_at } : {}) });

describe('ordering', () => {
  it('orders by created_at, not by hash id, and does not mutate the input', () => {
    const input = [msg('message_ff', '2026-03-02T10:00:00Z'), msg('message_00', '2026-03-02T12:00:00Z'), msg('message_aa', '2026-03-01T09:00:00Z')];
    expect(sortMessages(input).map(m => m.id)).toEqual(['message_aa', 'message_ff', 'message_00']);
    expect(input[0].id).toBe('message_ff');
  });
  it('merges by id without duplicates or losing earlier messages', () => {
    const merged = mergeMessages([msg('m1', '2026-03-01T00:00:00Z'), msg('m2', '2026-03-02T00:00:00Z')], [msg('m2', '2026-03-02T00:00:00Z'), msg('m3', '2026-03-03T00:00:00Z')]);
    expect(merged.map(m => m.id)).toEqual(['m1', 'm2', 'm3']);
  });
});

describe('date separators', () => {
  const now = new Date(2026, 5, 15, 12, 0, 0);
  it('labels Today, Yesterday and older dates', () => {
    expect(dayLabel(new Date(2026, 5, 15, 1, 0).toISOString(), now)).toBe('Today');
    expect(dayLabel(new Date(2026, 5, 14, 23, 59).toISOString(), now)).toBe('Yesterday');
    expect(dayLabel(new Date(2026, 5, 10, 8, 0).toISOString(), now, 'en-GB')).toMatch(/10 Jun 2026/);
  });
});

describe('composer limits', () => {
  it('rejects empty, whitespace-only and over-limit text (counted in code points)', () => {
    expect(canSend('')).toBe(false); expect(canSend('  \n ')).toBe(false); expect(canSend('hi')).toBe(true);
    expect(canSend('a'.repeat(4000))).toBe(true); expect(canSend('a'.repeat(4001))).toBe(false);
    expect(bodyLength('😀'.repeat(4000))).toBe(4000); expect(canSend('😀'.repeat(4000))).toBe(true);
  });
  it('truncates previews on one line', () => { expect(preview('a\n\nb')).toBe('a b'); expect(preview('x'.repeat(100), 10)).toBe('xxxxxxxxx…'); });
});

describe('unread logic', () => {
  it('only counts unread new_message notices', () => {
    const list = [notice('n1', 'm1'), notice('n2', 'm2', '2026-01-02T00:00:00Z'), notice('n3', 'a1', undefined, 'appointment_change')];
    expect(unreadMessageNotices(list).map(n => n.id)).toEqual(['n1']);
  });
  it('matches notices to a conversation through its loaded message ids', () => {
    const list = [notice('n1', 'm1'), notice('n2', 'other')];
    expect(unreadForThread(list, [msg('m1', '2026-01-01T00:00:00Z')]).map(n => n.id)).toEqual(['n1']);
    expect(unreadForThread(list, [])).toEqual([]);
  });
  it('caps the badge at 9+', () => { expect(badgeText(3)).toBe('3'); expect(badgeText(9)).toBe('9'); expect(badgeText(10)).toBe('9+'); });
});

describe('tab title and desktop text', () => {
  it('adds and restores the unread prefix', () => {
    expect(titleWithCount('KOI', 3)).toBe('(3) KOI'); expect(titleWithCount('(3) KOI', 4)).toBe('(4) KOI'); expect(titleWithCount('(4) KOI', 0)).toBe('KOI');
  });
  it('uses generic desktop text per role', () => {
    expect(desktopNoticeText('patient')).toBe('New message from your psychologist'); expect(desktopNoticeText('professional')).toBe('New message from a patient'); expect(desktopNoticeText('both')).toBe('New message');
  });
});
