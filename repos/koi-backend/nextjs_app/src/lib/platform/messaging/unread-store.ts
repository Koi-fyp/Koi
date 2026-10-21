import type { CareNotification } from '../community-types';

/** In-memory (never persisted) unread notices shared by the menu badge, the toast and the Messages screen. */
export interface UnreadState { uid: string | null; notices: CareNotification[]; loaded: boolean; owner: symbol | null }
export interface ActiveChat { hasMessage(id: string): boolean; refresh(): Promise<void> }
const empty = (owner: symbol | null): UnreadState => ({ uid: null, notices: [], loaded: false, owner });
let state: UnreadState = empty(null);
const listeners = new Set<() => void>();
const emit = () => listeners.forEach(l => l());
export const unreadStore = {
  get: () => state,
  subscribe(listener: () => void) { listeners.add(listener); return () => { listeners.delete(listener); }; },
  /** Exactly one mounted instance polls; others only display. */
  claim(token: symbol) { if (state.owner && state.owner !== token) return false; state = { ...state, owner: token }; emit(); return true; },
  release(token: symbol) { if (state.owner === token) { state = empty(null); emit(); } },
  publish(uid: string, notices: CareNotification[]) { state = { ...state, uid, notices, loaded: true }; emit(); },
  patch(id: string, next: CareNotification) { state = { ...state, notices: state.notices.map(n => n.id === id ? next : n) }; emit(); },
  clear() { state = empty(state.owner); emit(); },
  markRead: null as null | ((ids: string[]) => Promise<void>),
  refresh: null as null | (() => void),
  activeChat: null as ActiveChat | null,
  reset() { state = empty(null); this.markRead = null; this.refresh = null; this.activeChat = null; emit(); },
};
