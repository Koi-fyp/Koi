import { parsePollMs } from '../poll-config';
/** Client-safe messaging polling intervals. Invalid input uses the default, out-of-range input is clamped. */
/** Open conversation: how often its messages are re-read while the tab is visible. */
export const messagePollMs = (raw = process.env.NEXT_PUBLIC_KOI_PLATFORM_MESSAGE_POLL_MS) => parsePollMs(raw, 8000, 3000, 60000);
/** Unread badge: how often notifications are re-read while the tab is visible. */
export const unreadPollMs = (raw = process.env.NEXT_PUBLIC_KOI_PLATFORM_UNREAD_POLL_MS) => parsePollMs(raw, 30000, 10000, 300000);
export const MAX_BACKOFF_MS = 60000;
