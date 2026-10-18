# KOI Web integration conflict report - 2026-10-18

Local: `feat/web-product-data` / `b384ce2cef44e83e53db7f50182f3ccfaac32187` plus preserved dirty work.
Ahmad: `origin/avatar/vrm-emotion` / `884a278e0370835e98c07ae192cfa2dc8ba73495`.
Shared base: `223e97c489947b98677392f9b8ea383690ab1fe8`.

Compared actual fetched trees, committed local differences, current tracked modifications and relevant untracked implementation. No merge, checkout, cherry-pick, replacement or conflict resolution was performed. This is a path/semantic comparison, not a three-way merge execution.

## Direct path overlaps: SHARED FILE REQUIRES MERGE

| Exact path | Our actual work | Ahmad actual work | Integration instruction |
|---|---|---|---|
| `repos/koi-backend/nextjs_app/src/app/(authenticated)/chat/page.tsx` | History navigation (local committed) and ConversationProductControls insertion (dirty) | InputMode, sendVoice, mic/camera UI, layout/voice-aware chat | Keep his voice/camera/layout; manually insert product controls and history link. Do not replace his page with ours. |
| `repos/koi-backend/nextjs_app/src/app/(authenticated)/companion-scene/page.tsx` | BreathingActivityBridge wrapper and ConversationProductControls notice (dirty) | Companion identity, speech hook/toggle, camera/mic/modes, stop behavior and layout | Keep his page and media owners; integrate bridge/control exactly once, and verify exercise/audio interruption. Do not reintroduce our text-only notice over working reviewed media. |

## Related shared/proposed overlaps: APPROVAL REQUIRED

| Path | Comparison | Required decision |
|---|---|---|
| `repos/koi-backend/nextjs_app/src/lib/conversation/ConversationSession.ts` | Our runtime file unchanged; Ahmad adds voice input, private sendTurn and transcript handling. Do not overwrite it for the old session proposal. | Ahmad/security/product review as applicable; no automatic application. |
| `repos/koi-backend/nextjs_app/src/contexts/ConversationContext.tsx` | Our runtime unchanged; Ahmad forwards audio to the service. Archive/session selection must keep this routing and captured owner/session stable. | Ahmad/security/product review as applicable; no automatic application. |
| `repos/koi-backend/nextjs_app/src/hooks/useChat.ts` | Our runtime unchanged; unapplied consumer proposal modifies blocked; Ahmad adds voice placeholders and sendVoice. Compose the switching guard into his version, not replace the hook. | Ahmad/security/product review as applicable; no automatic application. |
| `repos/koi-backend/nextjs_app/src/lib/conversation/conversationService.ts` | Our runtime unchanged; Ahmad persists voice transcript after transcript event and assistant after done. Reconcile provenance/persistence failure semantics before enabling conversation completion or multi-chat voice acceptance. | Ahmad/security/product review as applicable; no automatic application. |
| `repos/koi-backend/nextjs_app/src/lib/conversation/jsonChatTransport.ts` | Our runtime unchanged; Ahmad adds multipart audio and audio MIME filename. Our WIP does not authorize removing or redesigning his transport. | Ahmad/security/product review as applicable; no automatic application. |
| `repos/koi-backend/nextjs_app/src/lib/conversation/chatContract.ts` | Our runtime unchanged; Ahmad adds audio Blob and voice request validation. Existing archive proposal tests only text; add reviewed text/transcript-only persistence tests without storing raw audio. | Ahmad/security/product review as applicable; no automatic application. |
| `repos/koi-backend/nextjs_app/src/lib/conversation/PersistentConversation.ts` | Unchanged runtime on our side and not listed as changed by Ahmad. Our unapplied archive draft refactors it; still a shared security/session boundary, not an automatically safe feature. | Ahmad/security/product review as applicable; no automatic application. |
| `repos/koi-backend/nextjs_app/src/lib/db.ts` | Our approved v3 three-store additive migration; Ahmad branch has no path edit since shared base. Preserve existing stores and review exact migration before integration. Proposed v4 remains unapplied. | Ahmad/security/product review as applicable; no automatic application. |
| `repos/koi-backend/nextjs_app/src/components/companion/ExerciseDirector.tsx` | Our additive optional breathing callback/monotonic measurement; Ahmad does not edit this path in the fetched diff. It runs inside his changed CompanionScene, so verify bridge/audio stop semantics and durationMs review. | Ahmad/security/product review as applicable; no automatic application. |
| `repos/koi-backend/nextjs_app/src/app/(authenticated)/layout.tsx` | Only Ahmad edits this path (InputMode provider). Our auth/conversation route lifetimes must survive it; not a text conflict but regression dependency. | Ahmad/security/product review as applicable; no automatic application. |
| `repos/koi-backend/nextjs_app/src/__tests__/companion-avatar.test.tsx` | Only Ahmad edits this test; no local actual diff. Keep his mock updates and extend separate product/bridge tests rather than replacing the mock. | Ahmad/security/product review as applicable; no automatic application. |

## SAFE TO REUSE - no direct Ahmad path collision

These are already implemented product changes, not a request to rebuild them. SAFE TO REUSE means no direct changed-path collision was detected; normal migration/privacy and combined regression review still applies.

- `src/lib/activities/**`, `src/lib/checkins/checkInService.ts`, existing `validateCheckIn.ts`: use the single ledger/writer; keep conversation producer disabled until its evidence exists.
- `src/hooks/useActivityData.ts`, `src/components/progress/{ActivityAvailability,RecordedBoard,BreathingActivityBridge}.tsx`, Progress page: retain receipt-backed data, not inferred/sample rewards.
- `src/lib/preferences/{userPreferences,preferenceSync,accountPreferenceSync.proposed,syncFailure}.ts`, `useUserPreferences`, `AccountPreferenceStatus`, Settings/onboarding changes: retain owner-only merge/acknowledgement/offline fallback.
- Ciphertext export/read-only import validators, Export/Import pages, truthful Wellness empty state, related tests. No restoration guarantee or import writes.
- Existing history read model/page can be reused for current-session read-only presentation; selection remains a separate reviewed implementation.
- Public-page truthfulness, AvatarPicker/modal accessibility and local-commit documentation/tests since shared base.
- Review diffs/reports/harness copies are evidence/proposals, not production files to blindly apply.

## DUPLICATE IMPLEMENTATION - conceptual overlap, not duplicate active production clients

| Existing local foundation | Ahmad implementation | Decision |
|---|---|---|
| `src/components/voice/VoiceCaptureControls.tsx` and fixture tests (in local HEAD, default disabled/unwired) | `src/components/voice/MicButton.tsx`, InputMode/voice controls plus voice-aware chat paths | Prefer Ahmad runtime. Local component is a consumer/fixture foundation; do not wire a second microphone/send/store. Keep or archive tests after API review; no automatic deletion performed. |
| `AudioCaptureResult` / VoiceOutput proposals in product ADR/handoff | Actual speech/capture/voice policy modules under Ahmad ownership | Reconcile types into his reviewed contract; a written proposal is not a deployed capability. |
| Our synthetic browser harness fixtures / disabled-media baseline assertions | Ahmad voice/camera/emotion/speech tests and observed media claims | Keep evidence classes separate. Update integrated assertions only after real capability acceptance; do not disable his features merely to satisfy old baseline tests. |

No identical newly added production file path occurs on both sides in the compared changes. No second speech/camera implementation was created in our uncommitted product batch.

## Complete changed-path inventory from Ahmad since shared base

- `repos/koi-backend/nextjs_app/AVATAR_ACCEPTANCE_WORKPACKAGE_B_2026-10-18.md`
- `repos/koi-backend/nextjs_app/scripts/fixtures/synthetic-cues-all-shapes.json`
- `repos/koi-backend/nextjs_app/scripts/fixtures/synthetic-cues-greeting.json`
- `repos/koi-backend/nextjs_app/scripts/fixtures/synthetic-cues-rapid.json`
- `repos/koi-backend/nextjs_app/scripts/test-avatar-emotion-matrix.cjs`
- `repos/koi-backend/nextjs_app/scripts/test-speech-turn.cjs`
- `repos/koi-backend/nextjs_app/scripts/verify-avatar-emotion-screens.cjs`
- `repos/koi-backend/nextjs_app/scripts/verify-avatar-lifecycle.cjs`
- `repos/koi-backend/nextjs_app/scripts/verify-camera-local.cjs`
- `repos/koi-backend/nextjs_app/src/__tests__/camera-session.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/camera-view.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/companion-avatar.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/companion-header.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/companion-scene-emotion.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/mode-selector.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/scene-voice.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/speech-client.test.ts`
- `repos/koi-backend/nextjs_app/src/__tests__/speech-status.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/speech-turn.test.ts`
- `repos/koi-backend/nextjs_app/src/__tests__/voice-input-transport.test.ts`
- `repos/koi-backend/nextjs_app/src/__tests__/voice-input-ui.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/voice-toggle.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/vrm-renderer-loop.test.tsx`
- `repos/koi-backend/nextjs_app/src/app/(authenticated)/chat/page.tsx`
- `repos/koi-backend/nextjs_app/src/app/(authenticated)/companion-scene/page.tsx`
- `repos/koi-backend/nextjs_app/src/app/(authenticated)/layout.tsx`
- `repos/koi-backend/nextjs_app/src/components/avatar/SpeechStatus.tsx`
- `repos/koi-backend/nextjs_app/src/components/camera/CameraPip.tsx`
- `repos/koi-backend/nextjs_app/src/components/camera/CameraView.tsx`
- `repos/koi-backend/nextjs_app/src/components/chat/InputBar.tsx`
- `repos/koi-backend/nextjs_app/src/components/companion/ChatComposer.tsx`
- `repos/koi-backend/nextjs_app/src/components/companion/CompanionHeader.tsx`
- `repos/koi-backend/nextjs_app/src/components/companion/CompanionScene.module.css`
- `repos/koi-backend/nextjs_app/src/components/companion/CompanionScene.tsx`
- `repos/koi-backend/nextjs_app/src/components/companion/ConversationControls.tsx`
- `repos/koi-backend/nextjs_app/src/components/companion/VoiceToggle.tsx`
- `repos/koi-backend/nextjs_app/src/components/layout/ModeSelector.tsx`
- `repos/koi-backend/nextjs_app/src/components/voice/MicButton.tsx`
- `repos/koi-backend/nextjs_app/src/contexts/ConversationContext.tsx`
- `repos/koi-backend/nextjs_app/src/contexts/InputModeContext.tsx`
- `repos/koi-backend/nextjs_app/src/hooks/useChat.ts`
- `repos/koi-backend/nextjs_app/src/lib/camera/cameraPrivacyGuard.ts`
- `repos/koi-backend/nextjs_app/src/lib/camera/cameraSession.ts`
- `repos/koi-backend/nextjs_app/src/lib/conversation/ConversationSession.ts`
- `repos/koi-backend/nextjs_app/src/lib/conversation/chatContract.ts`
- `repos/koi-backend/nextjs_app/src/lib/conversation/conversationService.ts`
- `repos/koi-backend/nextjs_app/src/lib/conversation/jsonChatTransport.ts`
- `repos/koi-backend/nextjs_app/src/lib/speech/SpeechTurnController.ts`
- `repos/koi-backend/nextjs_app/src/lib/speech/chunkReply.ts`
- `repos/koi-backend/nextjs_app/src/lib/speech/mouthCues.ts`
- `repos/koi-backend/nextjs_app/src/lib/speech/replyVoicePolicy.ts`
- `repos/koi-backend/nextjs_app/src/lib/speech/speechClient.ts`
- `repos/koi-backend/nextjs_app/src/lib/speech/speechReplyController.ts`
- `repos/koi-backend/nextjs_app/src/lib/speech/useSpokenReplies.ts`
- `repos/koi-backend/nextjs_app/src/lib/speech/voiceChoice.ts`
- `repos/koi-backend/nextjs_app/src/lib/speech/voiceGuard.ts`

## Local committed paths since shared base (inherited by future review branch)

- `KOI_W1_FINAL_ACCEPTANCE.md`
- `KOI_WEB_BASELINE_AND_FILE_OWNERSHIP.md`
- `KOI_WEB_IMPLEMENTATION_ACCEPTANCE.md`
- `KOI_WEB_PRODUCT_ADRS.md`
- `KOI_WEB_TO_AHMAD_HANDOFF.md`
- `repos/koi-backend/nextjs_app/src/__tests__/avatar-picker-accessibility.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/backup-draft.test.ts`
- `repos/koi-backend/nextjs_app/src/__tests__/backup-existing-key.test.ts`
- `repos/koi-backend/nextjs_app/src/__tests__/backup-preview.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/checkin-validation.test.ts`
- `repos/koi-backend/nextjs_app/src/__tests__/history-page.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/history.test.ts`
- `repos/koi-backend/nextjs_app/src/__tests__/progress.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/public-signin-retry.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/recorded-board.test.tsx`
- `repos/koi-backend/nextjs_app/src/__tests__/voice-controls.test.tsx`
- `repos/koi-backend/nextjs_app/src/app/(authenticated)/chat/page.tsx`
- `repos/koi-backend/nextjs_app/src/app/(authenticated)/history/page.tsx`
- `repos/koi-backend/nextjs_app/src/app/(authenticated)/progress/page.tsx`
- `repos/koi-backend/nextjs_app/src/app/(authenticated)/settings/components/AvatarPicker.tsx`
- `repos/koi-backend/nextjs_app/src/app/(authenticated)/settings/import/page.tsx`
- `repos/koi-backend/nextjs_app/src/app/how-it-works/page.tsx`
- `repos/koi-backend/nextjs_app/src/app/page.tsx`
- `repos/koi-backend/nextjs_app/src/components/data-portability/BackupPreview.tsx`
- `repos/koi-backend/nextjs_app/src/components/onboarding/WelcomeStep.tsx`
- `repos/koi-backend/nextjs_app/src/components/progress/RecordedBoard.tsx`
- `repos/koi-backend/nextjs_app/src/components/voice/VoiceCaptureControls.tsx`
- `repos/koi-backend/nextjs_app/src/hooks/useModalFocus.ts`
- `repos/koi-backend/nextjs_app/src/lib/checkins/validateCheckIn.ts`
- `repos/koi-backend/nextjs_app/src/lib/data-portability/backupDraft.ts`
- `repos/koi-backend/nextjs_app/src/lib/history/readHistory.ts`

The staging manifest separately enumerates every uncommitted path. The future WIP branch would inherit local commits `49ad948` and `b384ce2` as well as its new snapshot; staging only the delta does not omit those files. No merge/push/combined build/browser pass is claimed.
