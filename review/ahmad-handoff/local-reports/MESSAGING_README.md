# KOI Messages (WhatsApp/Messenger-style) - client-side batch

## What was built
- `Messages` menu item for patients with an active relationship (`/patient?view=messages#messages`) and for the professional workspace (`/professional?view=messages#messages`), with an unread badge (9+ cap).
- Messages screen: conversation list (<=10, title, preview, time, unread bubble) and chat pane (bubbles, Today/Yesterday separators, times, plain text with `dir="auto"`, optimistic "Sending...", "Sent", "Not sent. Tap to retry" with the SAME Idempotency-Key, Enter sends / Shift+Enter newline, counter near 4000, "New messages" jump button, `role="log"` live region). Two panes on wide screens, one pane + back button on narrow.
- Notifications: tab title `(n) KOI`, in-page "New message" toast (no text), opt-in "Enable desktop notifications" (generic text, only when the window is hidden/unfocused), opening a conversation marks its notices read.
- Polling: only on a visible, online tab; immediate refresh on visibilitychange/focus/online; x2 backoff to 60 s; stops and clears on 401/403/404.

Uses only existing endpoints through the existing api client. No server, contract, rules or package changes. No read/seen ticks (contract has no per-message read state).

## Env (client-safe, optional)
- `NEXT_PUBLIC_KOI_PLATFORM_MESSAGE_POLL_MS` - open chat, default 8000, clamp 3000..60000.
- `NEXT_PUBLIC_KOI_PLATFORM_UNREAD_POLL_MS` - badge, default 30000, clamp 10000..300000.
Invalid values fall back to the default. Raise both to protect the Firestore Spark quota (see MESSAGING_REPORT.md for the read estimate).

## Files
See MESSAGING_REPORT.md ("Edited EXISTING files" and "New files").

## Demo (manual, two Chrome profiles)
1. Profile A: sign in at `/patient` as `patient@koi-demo.example`. Profile B: sign in at `/professional` as `psychologist@koi-demo.example` (the two need an active relationship).
2. Both: open KOI menu -> Messages. Send messages both ways; sending asks for your password if your sign-in is older than ~4 minutes, then sends.
3. Put B on another page or another window and send from A: B's menu badge, tab title `(1) KOI` and the toast appear within ~30 s (or immediately when B refocuses the tab). Open the conversation: the badge clears.
4. Click "Enable desktop notifications" in the Messages list (browser permission is asked only then). Make B's window unfocused (but visible) and send from A: a generic "New message from a patient" appears (psychologist side) / "from your psychologist" (patient side).
5. Go offline / hide the tab: network requests to messages and notifications stop; they resume immediately when you return.

## UNTESTED
No live run: not started in a browser, no real Firebase/Firestore, no real re-authentication dialog, no real browser Notification permission prompt, no responsive layout check, no Firestore read measurement. All behaviour is covered only by jest/RTL tests with mocked api (43 new tests; full suite 93 suites / 778 tests green).
