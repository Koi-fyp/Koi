'use client';
import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { professionalApi } from '@/lib/platform/client';
import type { CareNotification } from '@/lib/platform/community-types';
import { desktopEnabled, notifyDesktop } from '@/lib/platform/messaging/desktop';
import { desktopNoticeText, noticeMessageId, titleWithCount, unreadMessageNotices, type MessagingRole } from '@/lib/platform/messaging/model';
import { unreadPollMs } from '@/lib/platform/messaging/poll-config';
import { createPoller } from '@/lib/platform/messaging/poller';
import { unreadStore } from '@/lib/platform/messaging/unread-store';

const PAGE = 100, MAX_PAGES = 3, MAX_MARK = 20, TOAST_MS = 6000;
const status = (e: unknown) => (e as { status?: number } | null)?.status;
const fatal = (e: unknown) => status(e) === 401 || status(e) === 403;

export const useUnreadState = () => useSyncExternalStore(unreadStore.subscribe, unreadStore.get, unreadStore.get);
export const useUnreadCount = () => unreadMessageNotices(useUnreadState().notices).length;

/**
 * Owns the single unread-notification poller of this window (menu badge, toast, tab title, desktop notice).
 * Only polls while enabled, visible and online; stops and clears everything when access is lost.
 */
export function useUnreadMessages(uid: string | null | undefined, currentUser: () => { uid: string } | null, enabled: boolean, role: MessagingRole) {
  const token = useRef(Symbol('unread')).current, user = useRef(currentUser); user.current = currentUser;
  const roleRef = useRef(role); roleRef.current = role;
  const ownerless = useSyncExternalStore(unreadStore.subscribe, () => unreadStore.get().owner === null, () => false);
  const [leader, setLeader] = useState(false), [toast, setToast] = useState(false), leading = useRef(false);
  const state = useUnreadState(), count = unreadMessageNotices(state.notices).length;
  const canClaim = ownerless || leading.current;
  useEffect(() => {
    if (!uid || !enabled) return;
    if (!unreadStore.claim(token)) return;
    leading.current = true; setLeader(true);
    const api = professionalApi(uid, () => user.current() as never);
    const seen = new Set<string>(); let first = true, alive = true, toastTimer: ReturnType<typeof setTimeout> | null = null;
    const announce = async (fresh: CareNotification[]) => {
      try { await unreadStore.activeChat?.refresh(); } catch { /* the chat reports its own failures */ }
      const chat = unreadStore.activeChat, outside = fresh.filter(n => !chat?.hasMessage(noticeMessageId(n)));
      if (!alive || !outside.length) return;
      setToast(true); if (toastTimer) clearTimeout(toastTimer); toastTimer = setTimeout(() => { if (alive) setToast(false); }, TOAST_MS);
      if (desktopEnabled()) notifyDesktop(desktopNoticeText(roleRef.current));
    };
    const poller = createPoller({
      intervalMs: unreadPollMs(),
      run: async () => {
        const found: CareNotification[] = []; let cursor: string | null = null;
        for (let page = 0; page < MAX_PAGES; page++) {
          const result: { items?: CareNotification[]; next_cursor?: string | null } = await api.request(`/api/v1/notifications?limit=${PAGE}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
          if (!Array.isArray(result?.items)) break;
          found.push(...result.items.filter(n => n.kind === 'new_message'));
          cursor = result.next_cursor ?? null; if (!cursor) break;
        }
        if (!alive) return;
        const fresh = unreadMessageNotices(found).filter(n => !seen.has(n.id));
        for (const n of found) seen.add(n.id);
        unreadStore.publish(uid, found);
        if (!first && fresh.length) void announce(fresh); first = false;
      },
      isFatal: fatal,
      onFatal: () => { unreadStore.clear(); setToast(false); },
    });
    unreadStore.refresh = () => poller.trigger();
    unreadStore.markRead = async ids => {
      for (const id of ids.slice(0, MAX_MARK)) {
        try { const next = await api.request<CareNotification>(`/api/v1/notifications/${encodeURIComponent(id)}/read`, 'POST', {}); if (next?.id === id) unreadStore.patch(id, next); }
        catch (e) { if (fatal(e)) { poller.stop(); unreadStore.clear(); return; } /* already read / gone: ignore */ }
      }
    };
    poller.start();
    return () => { alive = false; poller.stop(); api.dispose(); if (toastTimer) clearTimeout(toastTimer); unreadStore.refresh = null; unreadStore.markRead = null; leading.current = false; unreadStore.release(token); setLeader(false); setToast(false); };
  }, [uid, enabled, canClaim, token]);
  useEffect(() => {
    if (!leader) return;
    document.title = titleWithCount(document.title, count);
    return () => { document.title = titleWithCount(document.title, 0); };
  }, [leader, count]);
  return { count, toast: leader && toast, dismissToast: () => setToast(false) };
}
