'use client';

import { useEffect, useRef, useState } from 'react';
import type { ChatServerEvent, ExerciseClientEvent } from '@/lib/conversation/chatContract';
import { BreathingClock, getBreathingFrame, parseBreathingPattern, type BreathingPattern } from '@/lib/conversation/exerciseContract';
import { useBreathingResultCallback } from '@/components/progress/BreathingActivityBridge';
import type { BreathingResult } from '@/lib/activities/breathingActivity';
import styles from './CompanionScene.module.css';

type SessionEvent = { id: number; event: ChatServerEvent };
type BreathingCommand = { id: number; action: 'pause' };

function PacedBreathingPanel({ runId, pattern, command, onComplete, onStop, registerMeasurement }: {
  runId: number;
  pattern: BreathingPattern;
  command: BreathingCommand | null;
  onComplete: () => void;
  onStop: () => void;
  registerMeasurement: (measure: () => { durationMs: number; cyclesCompleted: number }) => void;
}) {
  const clock = useRef(new BreathingClock());
  const lastCommand = useRef(0);
  const completionSent = useRef(false);
  const callbacks = useRef({ onComplete, onStop });
  callbacks.current = { onComplete, onStop };
  const [elapsed, setElapsed] = useState(0);
  const [paused, setPaused] = useState(false);
  const [complete, setComplete] = useState(false);

  useEffect(() => {
    clock.current.start(performance.now());
    registerMeasurement(() => {
      const elapsed = clock.current.elapsedAt(performance.now());
      return { durationMs: Math.max(0, elapsed * 1000), cyclesCompleted: Math.min(pattern.cycles, Math.floor(elapsed / (pattern.inhale_s + pattern.exhale_s))) };
    });
    setElapsed(0);
    setPaused(false);
    setComplete(false);
    completionSent.current = false;
    return () => clock.current.pause(performance.now());
  }, [runId]);

  useEffect(() => {
    if (!command || command.id <= lastCommand.current) return;
    lastCommand.current = command.id;
    const now = performance.now();
    setElapsed(clock.current.elapsedAt(now));
    clock.current.pause(now);
    setPaused(true);
  }, [command]);

  useEffect(() => {
    if (paused || complete) return;
    const tick = () => {
      const now = performance.now();
      const seconds = clock.current.elapsedAt(now);
      const frame = getBreathingFrame(pattern, seconds);
      if (frame.complete) {
        clock.current.pause(now);
        setElapsed((pattern.inhale_s + pattern.exhale_s) * pattern.cycles);
        setComplete(true);
        if (!completionSent.current) {
          completionSent.current = true;
          callbacks.current.onComplete();
        }
      } else setElapsed(seconds);
    };
    const timer = window.setInterval(tick, 100);
    tick();
    return () => window.clearInterval(timer);
  }, [runId, pattern, paused, complete]);

  const frame = getBreathingFrame(pattern, elapsed);
  const phaseLabel = frame.phase === 'inhale' ? pattern.cue_audio[0] : pattern.cue_audio[1];
  const scale = frame.phase === 'inhale' ? 0.82 + frame.phaseProgress * 0.18 : 1 - frame.phaseProgress * 0.18;
  const pauseNow = () => {
    const now = performance.now();
    setElapsed(clock.current.elapsedAt(now));
    clock.current.pause(now);
    setPaused(true);
  };
  const resume = () => { clock.current.resume(performance.now()); setPaused(false); };

  return <section className={styles.exerciseCard} aria-label="Paced breathing activity">
    <h3>Paced breathing</h3>
    <p className={styles.exerciseCue} aria-live="polite">{complete ? 'Activity complete' : paused ? 'Paused' : phaseLabel}</p>
    <p className={styles.exerciseProgressText}>Cycle {Math.min(frame.cycle, pattern.cycles)} of {pattern.cycles}</p>
    <div className={styles.breathOrbWrap} aria-hidden="true">
      <div className={styles.breathOrb} data-phase={frame.phase} style={{ transform: `scale(${scale})` }} />
    </div>
    <div className={styles.exerciseProgress} role="progressbar" aria-label="Activity progress" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(frame.overallProgress * 100)}>
      <span style={{ width: `${frame.overallProgress * 100}%` }} />
    </div>
    <p className={styles.exerciseNotice}>On-screen cues only. No audio is played.</p>
    <div className={styles.exerciseButtons}>
      {!complete && (paused
        ? <button type="button" onClick={resume}>Resume</button>
        : <button type="button" onClick={pauseNow}>Pause</button>)}
      {!complete && <button type="button" onClick={callbacks.current.onStop}>Stop</button>}
    </div>
  </section>;
}

export default function ExerciseDirector({ events, disabled = false, interruptKey = 0, onRequest, onQueueClientEvent, consumeEvent, onBreathingResult }: {
  events: SessionEvent[];
  onBreathingResult?: (result: BreathingResult) => void;
  consumeEvent?: (id: number) => boolean;
  disabled?: boolean;
  interruptKey?: number;
  onRequest: (event: ExerciseClientEvent) => void;
  onQueueClientEvent: (event: ExerciseClientEvent) => void;
}) {
  const bridgeCallback = useBreathingResultCallback();
  const resultCallback = useRef(onBreathingResult ?? bridgeCallback);
  resultCallback.current = onBreathingResult ?? bridgeCallback;
  const run = useRef<{ sessionId: string; startedAt: string; cyclesPlanned: number } | null>(null);
  const measure = useRef<(() => { durationMs: number; cyclesCompleted: number }) | null>(null);
  const report = (endReason: BreathingResult['endReason']) => {
    const current = run.current; if (!current) return;
    run.current = null;
    const measured = measure.current?.() ?? { durationMs: 0, cyclesCompleted: 0 };
    // A failed observer must not change existing exercise/client-event behavior.
    try { resultCallback.current?.({ ...current, ...measured, endedAt: new Date().toISOString(), endReason }); } catch { /* No reward confirmed; keep normal exercise cleanup. */ }
  };
  const lastEventId = useRef(0);
  const [breathing, setBreathing] = useState<{ runId: number; pattern: BreathingPattern } | null>(null);
  const activeBreathing = useRef(false);
  const [command, setCommand] = useState<BreathingCommand | null>(null);
  const [notice, setNotice] = useState('');
  const queueRef = useRef(onQueueClientEvent);
  queueRef.current = onQueueClientEvent;
  const mountGeneration = useRef(0);
  useEffect(() => {
    const generation = ++mountGeneration.current;
    return () => { queueMicrotask(() => {
      if (mountGeneration.current === generation && activeBreathing.current) {
        report('navigation');
        activeBreathing.current = false;
        queueRef.current('playback_stopped');
      }
    }); };
  }, []);


  useEffect(() => {
    if (!interruptKey) return;
    const wasActive = activeBreathing.current;
    if (wasActive) report('handoff');
    activeBreathing.current = false;
    setBreathing(null);
    setCommand(null);
    if (wasActive) {
      setNotice('The activity paused for a safety check.');
      queueRef.current('playback_stopped');
    }
  }, [interruptKey]);

  useEffect(() => {
    for (const item of events) {
      if (item.id <= lastEventId.current) continue;
      lastEventId.current = item.id;
      if (item.event.event === 'handoff') {
        if (activeBreathing.current) { report('handoff'); activeBreathing.current = false; setBreathing(null); setCommand(null); queueRef.current('playback_stopped'); }
        continue;
      }
      if (item.event.event !== 'ui_action') continue;
      if (consumeEvent && !consumeEvent(item.id)) continue;
      const { name, args } = item.event.data;
      if (name === 'start_breathing') {
        const pattern = parseBreathingPattern(args);
        if (!pattern) {
          activeBreathing.current = false;
          setBreathing(null);
          setNotice('Breathing guidance is unavailable because its timing or cues were incomplete.');
        } else {
          if (activeBreathing.current) report('navigation');
          run.current = { sessionId: crypto.randomUUID(), startedAt: new Date().toISOString(), cyclesPlanned: pattern.cycles };
          measure.current = null;
          activeBreathing.current = true;
          setNotice('');
          setCommand(null);
          setBreathing({ runId: item.id, pattern });
        }
      } else if (name === 'pause_breathing') {
        setCommand({ id: item.id, action: 'pause' });
      } else if (name === 'stop_breathing') {
        const wasActive = activeBreathing.current;
        if (wasActive) report('user_stop');
        activeBreathing.current = false;
        setBreathing(null);
        setCommand(null);
        setNotice('The activity was stopped by KOI.');
        if (wasActive) queueRef.current('playback_stopped');
      } else if (name === 'start_grounding' || name === 'start_plan') {
        if (activeBreathing.current) report('navigation');
        activeBreathing.current = false;
        setBreathing(null);
        setNotice('This activity is not available in the current Web view yet.');
      } else if (name === 'save_task' || name === 'save_go_to') {
        setNotice('This action is not available in the current Web view yet.');
      }
    }
  }, [events]);

  const stopBreathing = () => {
    report('user_stop');
    activeBreathing.current = false;
    setBreathing(null);
    setNotice('Activity stopped.');
    onQueueClientEvent('playback_stopped');
  };
  const requestButtonsDisabled = disabled || breathing !== null;
  return <section className={styles.exerciseDirector} aria-label="KOI activity controls">
    <details>
      <summary>Request an activity</summary>
      <div className={styles.exerciseButtons}>
        <button type="button" disabled={requestButtonsDisabled} onClick={() => onRequest('start_breathing')}>Breathing</button>
        <button type="button" disabled={requestButtonsDisabled} onClick={() => onRequest('start_grounding')}>Grounding</button>
        <button type="button" disabled={requestButtonsDisabled} onClick={() => onRequest('start_plan')}>Make a plan</button>
      </div>
      <p>KOI decides whether an activity can start. Text-only chat remains available.</p>
    </details>
    {notice && <p className={styles.exerciseNotice} role="status">{notice}</p>}
    {breathing && <PacedBreathingPanel key={breathing.runId} runId={breathing.runId} pattern={breathing.pattern} command={command} registerMeasurement={callback => { measure.current = callback; }}
      onComplete={() => { report('completed'); activeBreathing.current = false; onQueueClientEvent('playback_done'); }} onStop={stopBreathing} />}
  </section>;
}
