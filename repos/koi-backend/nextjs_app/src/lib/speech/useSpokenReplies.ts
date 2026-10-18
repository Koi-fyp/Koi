'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import type { ChatServerEvent } from '../conversation/chatContract';
import type { SpeechTimeline } from './mouthCues';
import { SpeechPlayback } from './SpeechPlayback';
import { createSpeechClient } from './speechClient';
import { SpeechReplyController, type ReplyOutcome, type ReplyStatus, type ReplyStatusReason, type ReplyTurn } from './speechReplyController';
import { hasVoice, planReplyVoice } from './replyVoicePolicy';
import type { SpeechCompanionId } from './voiceChoice';
export type VoiceLine = 'idle' | 'speaking' | 'skipped' | 'unavailable';
export type ReplyVoiceController = SpeechTimeline & { speakReply(turn: ReplyTurn): Promise<ReplyOutcome>; cancel(): void; dispose(): void };
export interface SpokenReplyMessage { id: string; sender: 'user' | 'ai'; status: string; content: string; }
export interface SpokenRepliesOptions {
  enabled: boolean;
  uid: string | null | undefined;
  companion: SpeechCompanionId | null;
  messages: readonly SpokenReplyMessage[];
  pending: boolean;
  serverEvents?: ReadonlyArray<{ id: number; event: ChatServerEvent }>;
  baseUrl: string;
  getToken: () => Promise<string>;
  createController?: (deps: { baseUrl: string; getToken: () => Promise<string>; onStatus: (status: ReplyStatus) => void }) => ReplyVoiceController;
  newGenerationId?: () => string;
}
export interface SpokenReplies { line: VoiceLine; audioPlaying: boolean; speechSource?: SpeechTimeline; stop: () => void; }
const EXERCISE_ACTIONS = new Set(['start_breathing', 'start_grounding', 'start_plan', 'stop_breathing', 'pause_breathing']);
// Reasons that mean the service, not this reply, is the problem.
const SERVICE_REASONS = new Set<ReplyStatusReason>(['network', 'timeout', 'speech-unavailable', 'invalid-response', 'unauthenticated', 'rate-limited']);
const defaultController: NonNullable<SpokenRepliesOptions['createController']> = ({ baseUrl, getToken, onStatus }) =>
  new SpeechReplyController({ client: createSpeechClient({ baseUrl, getToken }), playback: new SpeechPlayback(), onStatus });
/** A crisis handoff, a high-risk result or any exercise action in this turn keeps the reply text-only. */
export function turnBlocksVoice(events: SpokenRepliesOptions['serverEvents']): boolean {
  return !!events?.some(({ event }) => event.event === 'handoff'
    || (event.event === 'risk' && event.data.status === 'ok' && (event.data.risk_category === 'HIGH' || event.data.risk_category === 'CRITICAL'))
    || (event.event === 'ui_action' && EXERCISE_ACTIONS.has(event.data.name)));
}
/** The latest message, only when it is a finished companion reply (not a streaming delta). */
function finishedReply(messages: readonly SpokenReplyMessage[], pending: boolean) {
  const last = messages[messages.length - 1];
  return !pending && last?.sender === 'ai' && last.status === 'completed' && last.content.trim() ? last : null;
}
/**
 * Optional spoken replies for the companion scene. Reads chat state only; never writes or logs the text.
 * Every cancel path stops audio and leaves the mouth neutral (the controller's idle frame).
 */
export function useSpokenReplies({ enabled, uid, companion, messages, pending, serverEvents, baseUrl, getToken, createController = defaultController,
  newGenerationId = () => globalThis.crypto.randomUUID() }: SpokenRepliesOptions): SpokenReplies {
  const [controller, setController] = useState<ReplyVoiceController>();
  const [line, setLine] = useState<VoiceLine>('idle');
  const [audioPlaying, setAudioPlaying] = useState(false);
  const [buildFailed, setBuildFailed] = useState(false);
  const tokenRef = useRef(getToken); tokenRef.current = getToken;
  const factoryRef = useRef(createController); factoryRef.current = createController;
  const turnRef = useRef(0);
  const turnStats = useRef({ played: false, serviceFailure: false });
  const reply = finishedReply(messages, pending);
  // Replies that already existed (history, or before voice was turned on) are never spoken.
  const handledRef = useRef<string | null>(reply?.id ?? null);
  const blocked = turnBlocksVoice(serverEvents);
  const active = enabled && !!uid && !!baseUrl && hasVoice(companion);
  const controllerRef = useRef(controller); controllerRef.current = controller;
  const stop = useCallback(() => {
    turnRef.current++;
    controllerRef.current?.cancel();
    setAudioPlaying(false); setLine('idle');
  }, []);
  useEffect(() => {
    setBuildFailed(false);
    if (!active) return;
    let created: ReplyVoiceController;
    try {
      created = factoryRef.current({ baseUrl, getToken: () => tokenRef.current(), onStatus: (status) => {
        if (status.state === 'playing') { turnStats.current.played = true; setLine('speaking'); }
        if (status.reason && SERVICE_REASONS.has(status.reason)) turnStats.current.serviceFailure = true;
        setAudioPlaying(status.state === 'playing');
      } });
    } catch { setBuildFailed(true); return; }
    setController(created);
    return () => { turnRef.current++; created.dispose(); setController(undefined); setAudioPlaying(false); setLine('idle'); };
  }, [active, baseUrl]);
  // Cancel rules: toggle off, uid or companion change, a new user message (pending), crisis/exercise, page hidden.
  useEffect(() => { handledRef.current = reply?.id ?? handledRef.current; stop(); }, [enabled, uid, companion, stop]);
  useEffect(() => { if (pending || blocked) stop(); }, [pending, blocked, stop]);
  useEffect(() => {
    const onVisibility = () => { if (document.visibilityState === 'hidden') stop(); };
    document.addEventListener('visibilitychange', onVisibility);
    return () => document.removeEventListener('visibilitychange', onVisibility);
  }, [stop]);
  useEffect(() => {
    if (!reply || reply.id === handledRef.current) return;
    handledRef.current = reply.id;
    if (!active || blocked || !controller || !uid || document.visibilityState === 'hidden') return;
    const plan = planReplyVoice(reply.content);
    if (!plan.speak) { setLine('skipped'); return; }
    const turn = ++turnRef.current;
    turnStats.current = { played: false, serviceFailure: false };
    setLine('idle');
    void controller.speakReply({ text: reply.content, companion: companion!, ownerUid: uid, generationId: newGenerationId(), languageHint: plan.languageHint })
      .then((outcome) => {
        if (turn !== turnRef.current) return;
        setAudioPlaying(false);
        const { played, serviceFailure } = turnStats.current;
        setLine(outcome === 'cancelled' || (outcome === 'completed' && played) ? 'idle' : outcome === 'error' || serviceFailure ? 'unavailable' : 'skipped');
      }, () => { if (turn === turnRef.current) { setAudioPlaying(false); setLine('unavailable'); } });
  }, [reply?.id, active, blocked, controller, uid, companion]);
  return { line: buildFailed && active ? 'unavailable' : line, audioPlaying, speechSource: controller, stop };
}
