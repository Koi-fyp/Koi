# KOI v1.1 client integration map

Updated 2026-10-17 during P4.1. This is an inventory of the checked-in
client surfaces; "missing" means there is no implementation in the client
tree, not that the backend contract is unavailable.

## Web client

| Surface | Location | Status / evidence | Last author |
| --- | --- | --- | --- |
| Chat page/component | `repos/koi-backend/nextjs_app/src/app/(authenticated)/chat/page.tsx` | Exists. Renders the message list, input and static image avatar. It currently consumes only `messages`, `isTyping`, and `send`. | `feat(avatar)` history |
| Message list/bubbles | `src/components/chat/MessageList.tsx`, `MessageBubble.tsx` | Exists. Renders `ChatMessage` records; no streamed delta or transcript event surface. | `feat(avatar)` history |
| Input and modality toggles | `src/components/chat/InputBar.tsx` | Text input exists. Audio/video capture and the four modality combinations are missing. | `feat(avatar)` history |
| Conversation service | `src/lib/conversation/conversationService.ts` | Exists. POSTs JSON to `/api/v1/chat`, parses latency/delta/done, and saves encrypted messages. It has no multipart, transcript, risk, ui_action, handoff, redirect, or health handling. | `feat(avatar)` history |
| Chat hook | `src/hooks/useChat.ts` | Exists. Calls the service and appends one final assistant message; no per-event state, session-history transcript append, or crisis flow. | `feat(avatar)` history |
| Avatar emotion | `src/components/avatar/AvatarAnimator.ts` | `AvatarAnimator.setEmotion()` exists (lines 105-114), but the current chat page uses `/Male.png`; no `setEmotion` bridge is connected to the chat stream. The deployed web union is `happy|sad|anxious|calm|neutral`, while v1.1 wire values are `neutral|joy|angry|sorrow|fun`; a read-side legacy map is required. | `feat(avatar)` history |
| KoiBridge | `src/` | Missing. No KoiBridge symbol is present in the checked-in web client. | N/A |
| Piper TTS / Rhubarb lip-sync | `src/` | Missing from the checked-in `src`; no existing sentence playback adapter was found. | N/A |
| Breathing animation | `src/` | Missing as a chat exercise UI. `AvatarAnimator` has only idle breathing (`applyBreathe`, lines 148-155), not a `ui_action` exercise controller. | `feat(avatar)` history |
| Crisis/safety modal | `src/` | Missing. No crisis modal or Flow 4 component is present. | N/A |
| Firestore message writes | `src/lib/conversation/conversationService.ts`, `src/lib/firestore/sync.ts` | Exists through `syncQueue`, but writes `conversations/{cid}/messages/{mid}` (service line 73), not the required `users/{uid}/conversations/{cid}/messages/{mid}`. No read-only legacy fallback exists. | `feat(avatar)` history |
| Salt write | `src/lib/crypto.ts` | Exists for salt generation and lookup through Firestore; the account/key-creation wiring is not present in the inspected client flow. | `feat(avatar)` history |
| API base | `src/lib/conversation/conversationService.ts` | `NEXT_PUBLIC_KOI_API_BASE` is read at module load (line 44). | `feat(avatar)` history |
| Tests/config | `src/__tests__/setup.env.ts` | Test environment file exists, but the expected `jest.setup.ts` referenced by the project configuration is missing (recorded in P3 report). | P3 audit |

## Flutter client

| Surface | Location | Status / evidence | Last author |
| --- | --- | --- | --- |
| Chat page/component | `repos/koi-backend/flutter_lib/lib/` | Missing in this checkout. The Flutter library contains models, storage, auth and crypto, but no chat screen or widget tree. | N/A |
| Message list/input/toggles | `flutter_lib/lib/` | Missing. `HiveMessage` and `MessageRepository` provide storage only; there is no input or modality UI. | N/A |
| Conversation service reference | `docs/contracts/clients/dart/koi_chat_client.dart` | Exists as the checked-in transport/state reference. It already posts only `/api/v1/chat`, parses chunk-safe UTF-8 SSE, ignores unknown events, handles transcript/risk/ui_action/exercise state/handoff, and keeps the 401 fallback. It is not wired to a Flutter widget. | P4 Dart client |
| AvatarController / KoiBridge | `flutter_lib/lib/` | Missing. No avatar bridge or emotion controller is checked in. The Dart reference documents the required callback in `README_DART.md`. | N/A |
| Piper TTS / Rhubarb lip-sync | `flutter_lib/lib/` | Missing. No audio playback or lip-sync adapter is checked in. | N/A |
| Breathing animation | `flutter_lib/lib/` | Missing. The Dart transport exposes `UiAction` and exercise events, but no animation widget consumes them. | N/A |
| Crisis/safety modal | `flutter_lib/lib/` | Missing. The Dart reference has state (`crisisFlowOpen`, `resolveCrisis`) but no modal implementation. | P4 Dart client |
| Firestore message writes | `flutter_lib/lib/storage/repositories/message_repository.dart` | Local Hive persistence exists. A Firestore sync path for `users/{uid}/conversations/{cid}/messages/{mid}` is missing. | Existing storage history |
| Salt write | `flutter_lib/lib/services/crypto_service.dart` | `generateSalt()` exists and explicitly documents `users/{uid}.public_crypto_metadata.salt` (lines 32-40), but no Firebase write is wired at key creation. | P4 Dart client |
| API base | `docs/contracts/clients/dart/koi_chat_client.dart` | Constructor-injected `chatBaseUrl` and `crisisBaseUrl` exist in the reference; Flutter app wiring is missing. | P4 Dart client |
| Emotion union | `docs/contracts/clients/dart/koi_chat_client.dart` | Wire enum is `neutral|joy|angry|sorrow|fun`; `EmotionWire.parse()` safely maps unknown values to neutral. | P4 Dart client |

## Branch/base discovery for P4.3

The P4.2 fetch found these newest remote client branches:

* Web wiring branch: `feat/web-vrm-avatar`, base
  `origin/feat/web-vrm-avatar` at `5ee2385` (2026-10-16 22:12 +0500,
  microphone capture and Whisper STT).
* Flutter wiring branch: `fatima-flutter`, base
  `origin/fatima-flutter` at `63e56df` (2026-10-11 03:36 +0500, Flutter
  app scaffold and shared library dependency).

The current branch's `origin/feat/exercise-director-modal` is newer overall,
but it has no newer client-specific commit than the selected bases; it remains
the integration-map branch.

## Scope gaps carried into P4.3

The existing web client can be extended in place in
`conversationService.ts`, `useChat.ts`, and existing chat components. No
parallel service file should be created. The Flutter repository has no chat
UI to wire; P4.3 may only extend existing library surfaces and the checked-in
Dart reference, and must report any UI that remains unbuilt. Protected
`koi_policy` files and the canonical docs directory remain untouched.
