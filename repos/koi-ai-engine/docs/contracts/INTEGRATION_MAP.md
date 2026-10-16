# KOI v1.1 integration map from P4 base branches

This inventory was rebuilt without checkout from the exact P4 bases:

* Web: `origin/feat/web-vrm-avatar` (`E:\Koi\wt_web`)
* Flutter: `origin/fatima-flutter` (`E:\Koi\wt_flutter`)

Every path and line below comes from a base-tree read. Last author is the
output of `git log -1 --format=%an <path>` on that base.

## Web base

| Surface | Base path and line evidence | Base finding | Last author |
| --- | --- | --- | --- |
| Real app/chat page | `repos/koi-backend/nextjs_app/src/app/(authenticated)/chat/page.tsx:5,46-69` | The production page uses `useChat`, `InputBar`, and the message list. | fatimaha5an / Ahmad Suleman |
| Chat hook | `repos/koi-backend/nextjs_app/src/hooks/useChat.ts:6,19-23` | `useChat` delegates to `conversationService.sendMessage`; no media or event callbacks are exposed at these lines. | fatimaha5an |
| Request/transport | `repos/koi-backend/nextjs_app/src/lib/conversation/chatContract.ts:1-7`; `repos/koi-backend/nextjs_app/src/lib/conversation/jsonChatTransport.ts:2,10-13` | The base contract is JSON request/response and the transport targets the configured chat endpoint. | fatimaha5an |
| Text input | `repos/koi-backend/nextjs_app/src/components/chat/InputBar.tsx:3-8` | Text-only `textarea` input; no audio/video toggle in this component. | Ahmad Suleman |
| Alternate composer | `repos/koi-backend/nextjs_app/src/components/companion/ChatComposer.tsx:3-14` | Text-only composer with focus/cancel hooks; it is a separate companion surface. | fatimaha5an |
| Avatar controller | `repos/koi-backend/nextjs_app/src/components/avatar/VRMAvatarController.ts:32-33,96-111` | `setEmotion`, `setConversationState`, `setSpeechSource`, blink, posture, and mouth timeline support exist. | fatimaha5an |
| Avatar command bridge | `repos/koi-backend/nextjs_app/src/components/avatar/avatarCommandBridge.ts:8-14,16-21,24-73,75-96` | **Present.** `AvatarCommandBridge` exposes `setEmotion`, `setConversationState`, `reset`, `getSnapshot`, readiness/lifecycle, `bind`, `markReady`, `detach`, and `dispose`. `registerAvatarCommands` publishes a restricted `window.AvatarController` facade. `window.KoiBridge` is only a reserved `{ postMessage(message: string): void }` declaration at lines 18-20; no implementation is provided. | fatimaha5an |
| Avatar animation/breathing | `repos/koi-backend/nextjs_app/src/components/avatar/ANIMATION.md:3-7,28-39` | Base documents emotional animation, blink, chest breathing, reduced motion, and head posture. | fatimaha5an |
| TTS/lip-sync | `repos/koi-backend/nextjs_app/src/lib/speech/mouthCues.ts:3-31`; `repos/koi-backend/nextjs_app/src/lib/speech/VOICE_INPUT.md:229-241` | Rhubarb cue parsing and VRM mouth mapping exist; Piper/Rhubarb integration is documented and benchmarked, but the chat page wiring is not evidenced by the base chat files. | fatimaha5an |
| Crisis UI/modal | `repos/koi-backend/nextjs_app/src/app/(authenticated)/chat/page.tsx:46-69`; base search over `src` for crisis/modal/Flow 4 | No production Flow 4 modal callback or risk-event consumer was found in the checked base chat path. This is a verified base-tree search result, not an unverified assumption. | Ahmad Suleman / fatimaha5an |
| Firestore message path | `repos/koi-backend/nextjs_app/src/hooks/useChat.ts:29-38`; `repos/koi-backend/nextjs_app/src/lib/conversation/conversationService.ts` is not present in the base file-name inventory | Local message loading is present. The service implementation path was not present in the selected base tree inventory: **UNVERIFIED** for exact write path and legacy fallback. | fatimaha5an |
| Salt write | `repos/koi-backend/nextjs_app/src/lib/crypto.ts` is not present in the selected base file-name inventory | **UNVERIFIED** in this base-tree inventory. | UNVERIFIED |
| API base | `repos/koi-backend/nextjs_app/src/lib/conversation/jsonChatTransport.ts:2-13` | Base uses `chatEndpoint(apiBase)` and therefore the injected API base; exact environment-name declaration is **UNVERIFIED** outside this transport. | fatimaha5an |
| Package/test manifest | `repos/koi-backend/nextjs_app/package.json`; `repos/koi-backend/nextjs_app/jest.config.cjs` | Next.js package and Jest config are present. `jest.setup.ts` is referenced by config but was not in the base file inventory. | fatimaha5an |

## Flutter base

The real Flutter application root is `repos/koi-mobile`, not
`repos/koi-backend/flutter_lib`. The base has both
`repos/koi-mobile/pubspec.yaml` and the reusable library manifest
`repos/koi-backend/flutter_lib/pubspec.yaml`.

| Surface | Base path and line evidence | Base finding | Last author |
| --- | --- | --- | --- |
| Real app root/widget | `repos/koi-mobile/pubspec.yaml:1-3,30-46`; `repos/koi-mobile/lib/main.dart:7-33,38-56` | The runnable app is the default Flutter counter app under `repos/koi-mobile`; it does not import the KOI chat library. | fatimaha5an |
| Chat page/input/toggles | Base search over `repos/koi-mobile/lib` and `repos/koi-backend/flutter_lib/lib` for chat/input/modality | No chat widget or modality toggle was found in the checked base tree. This is a verified search result, not an unverified assumption. | UNVERIFIED |
| Chat transport | Base search over both Flutter roots for `/api/v1/chat`, SSE, and conversation service | No Flutter chat transport was found in the selected base tree. **UNVERIFIED** for any generated/untracked runtime code. | UNVERIFIED |
| Avatar/KoiBridge | Base search over both Flutter roots for avatar, bridge, and KoiBridge | No Flutter avatar bridge was found. The web-only `window.AvatarController` bridge above is not a Flutter implementation. | UNVERIFIED |
| TTS/lip-sync | Base search over both Flutter roots for Piper, Rhubarb, TTS, and lip-sync | No Flutter TTS or lip-sync adapter was found. | UNVERIFIED |
| Breathing animation | Base search over both Flutter roots for breathing and exercise animation | No Flutter breathing widget was found. | UNVERIFIED |
| Crisis/safety modal | Base search over both Flutter roots for crisis, safety, Flow 4, and modal | No Flutter crisis modal was found. | UNVERIFIED |
| Local message storage | `repos/koi-backend/flutter_lib/lib/storage/repositories/message_repository.dart:5-35` | Hive message persistence exists (`saveMessage`, conversation reads, sync flags); no Firestore message sync is exposed here. | Ahmad |
| Firestore/auth | `repos/koi-backend/flutter_lib/lib/services/auth_service.dart:19,27,89-104,131-143` | Firebase Auth and Firestore user-document setup exist. The base user write does not include the required public crypto salt. | Ahmad |
| Crypto salt | `repos/koi-backend/flutter_lib/lib/services/crypto_service.dart:21,35-43` | `generateSalt()` exists and documents the intended `users/{uid}.public_crypto_metadata.salt` location, but the base auth write does not call it. | Ahmad |
| Package manifests | `repos/koi-mobile/pubspec.yaml:30-46`; `repos/koi-backend/flutter_lib/pubspec.yaml:1-18` | The app root depends only on Flutter/Cupertino plus the library; the library owns Firebase, Hive, crypto, and auth dependencies. | fatimaha5an / Ahmad |

## P4.3 wiring boundary

Only the base gaps are eligible for wiring. The web avatar bridge,
VRM emotion controller, breathing posture, and Rhubarb cue parser must be
reused rather than rebuilt. The real Flutter app is `repos/koi-mobile`; any
Flutter wiring must land there or in an existing library surface, not in a
new parallel chat service. Rows marked **UNVERIFIED** require a bounded
base-tree check before implementation.

## P4.3 worktree results

* Web worktree `E:\Koi\wt_web`, branch `feat/web-v11-wiring`, commit
  `81d6de0`: extended the existing `chatContract.ts`,
  `jsonChatTransport.ts`, and `ConversationSession.ts` surfaces to consume
  chunk-safe SSE frames and additive companion/delta payloads; added the
  already-referenced `jest.setup.ts`. The existing avatar bridge and speech
  files were not duplicated or rebuilt.
* Flutter worktree `E:\Koi\wt_flutter`, branch `feat/flutter-v11-wiring`,
  commit `58d6ca1`: extended the existing `auth_service.dart` user-document
  creation path to persist `public_crypto_metadata.salt` using the existing
  `KoiCryptoService.generateSalt()`. No new chat service was created.
* Not wired: the base Flutter app still has no chat transport/UI, crisis
  modal, avatar bridge, or TTS/lip-sync consumer; these remain explicit
  follow-up gaps rather than being rebuilt in the wrong library directory.
  Web audio/video multipart, Flow 4 rendering, and Firestore path migration
  also remain unimplemented because their base consumers were not present in
  the selected app path.
* Flutter UI and wiring are owned by Fatima and were not touched by this run.
