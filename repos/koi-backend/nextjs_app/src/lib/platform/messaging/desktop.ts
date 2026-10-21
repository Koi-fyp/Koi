const KEY = 'koi.messages.desktop';
const read = (): string | null => { try { return window.localStorage.getItem(KEY); } catch { return null; } };
const write = (value: string | null) => { try { if (value) window.localStorage.setItem(KEY, value); else window.localStorage.removeItem(KEY); } catch { /* storage unavailable */ } };
export const desktopSupported = () => typeof window !== 'undefined' && 'Notification' in window;
export const desktopPermission = (): NotificationPermission | 'unsupported' => desktopSupported() ? Notification.permission : 'unsupported';
/** Opted in by the user AND permission granted. */
export const desktopEnabled = () => desktopSupported() && read() === '1' && Notification.permission === 'granted';
/** Must only be called from a user click: this is the only place permission is requested. */
export async function enableDesktop(): Promise<NotificationPermission | 'unsupported'> {
  if (!desktopSupported()) return 'unsupported';
  const result = Notification.permission === 'default' ? await Notification.requestPermission() : Notification.permission;
  write(result === 'granted' ? '1' : null); return result;
}
export const disableDesktop = () => write(null);
export const tabInBackground = () => document.hidden || !document.hasFocus();
/** Shows a notification with GENERIC text only, and only when the tab is hidden or unfocused. Returns whether shown. */
export function notifyDesktop(text: string): boolean {
  if (!desktopEnabled() || !tabInBackground()) return false;
  try { new Notification(text, { tag: 'koi-new-message', silent: false }); return true; } catch { return false; }
}
