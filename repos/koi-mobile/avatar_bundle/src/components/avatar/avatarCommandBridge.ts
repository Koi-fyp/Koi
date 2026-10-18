// Copied from repos/koi-backend/nextjs_app/src/components/avatar/avatarCommandBridge.ts (branch feat/avatar-webview-host, commit 223e97c).
// Copied, do not edit here: change upstream and re-copy.
import { clampIntensity, normalizeConversationState, normalizeEmotion,
  type AvatarAnimationSnapshot, type ConversationState, type KoiEmotion, type VRMAvatarController } from './VRMAvatarController';

export interface AvatarCommandSnapshot {
  ready: boolean; lifecycle: 'not-ready' | 'ready' | 'disposed'; modelUrl: string | null;
  generation: number; animation: AvatarAnimationSnapshot | null;
}
export interface AvatarCommandContract {
  readonly ready: boolean;
  readonly lifecycle: AvatarCommandSnapshot['lifecycle'];
  setEmotion(emotion: KoiEmotion, intensity: number): boolean;
  setConversationState(state: ConversationState): void;
  reset(): void;
  getSnapshot(): AvatarCommandSnapshot;
}
export interface AvatarCommandRegistrationOptions {
  /** Forward only the approved readiness token to a native WebView channel. */
  notifyKoiBridgeOnReady?: boolean;
}
declare global {
  interface Window {
    AvatarController?: AvatarCommandContract;
    /** Reserved transport contract only. No Flutter channel is invoked in Increment 4. */
    KoiBridge?: { postMessage(message: string): void };
  }
}

/** Latest commands queue before readiness; bind/detach use identity to reject stale loads. */
export class AvatarCommandBridge implements AvatarCommandContract {
  private controller: VRMAvatarController | null = null;
  private emotion: KoiEmotion = 'neutral';
  private intensity = 0;
  private state: ConversationState = 'idle';
  private modelUrl: string | null = null;
  private generation = 0;
  private status: AvatarCommandSnapshot['lifecycle'] = 'not-ready';
  private listeners = new Set<(snapshot: AvatarCommandSnapshot) => void>();
  get ready() { return this.status === 'ready'; }
  get lifecycle() { return this.status; }
  subscribe(listener: (snapshot: AvatarCommandSnapshot) => void) {
    this.listeners.add(listener); listener(this.getSnapshot());
    return () => { this.listeners.delete(listener); };
  }
  private notify() { for (const listener of this.listeners) listener(this.getSnapshot()); }
  bind(controller: VRMAvatarController, modelUrl: string) {
    if (this.status === 'disposed') return;
    this.controller = controller; this.modelUrl = modelUrl; this.generation++; this.status = 'not-ready';
    controller.setEmotion(this.emotion, this.intensity); controller.setConversationState(this.state); this.notify();
  }
  markReady(controller: VRMAvatarController) {
    if (this.status !== 'disposed' && this.controller === controller && !this.ready) { this.status = 'ready'; this.notify(); }
  }
  detach(controller: VRMAvatarController) {
    if (this.controller !== controller) return;
    this.controller = null; this.modelUrl = null; this.status = 'not-ready'; this.notify();
  }
  setEmotion(emotion: KoiEmotion, intensity: number) {
    if (this.status === 'disposed') return false;
    this.emotion = normalizeEmotion(emotion); this.intensity = clampIntensity(intensity);
    return this.controller?.setEmotion(this.emotion, this.intensity) ?? true;
  }
  setConversationState(state: ConversationState) {
    if (this.status === 'disposed') return;
    this.state = normalizeConversationState(state); this.controller?.setConversationState(this.state);
  }
  reset() {
    if (this.status === 'disposed') return;
    this.emotion = 'neutral'; this.intensity = 0; this.state = 'idle'; this.controller?.reset();
  }
  getSnapshot(): AvatarCommandSnapshot {
    return { ready: this.ready, lifecycle: this.status, modelUrl: this.modelUrl, generation: this.generation, animation: this.controller?.getSnapshot() ?? null };
  }
  dispose() {
    if (this.status === 'disposed') return;
    this.controller = null; this.modelUrl = null; this.status = 'disposed'; this.notify(); this.listeners.clear();
  }
}

export function registerAvatarCommands(
  bridge: AvatarCommandBridge,
  target: Window = window,
  options: AvatarCommandRegistrationOptions = {},
) {
  if (bridge.lifecycle === 'disposed') throw new Error('Cannot register a disposed avatar interface.');
  if (target.AvatarController) throw new Error('An avatar command interface is already registered.');
  // Publish only commands/diagnostics, never model references or bind/update/dispose internals.
  const facade: AvatarCommandContract = Object.freeze({
    get ready() { return bridge.ready; },
    get lifecycle() { return bridge.lifecycle; },
    setEmotion: (emotion: KoiEmotion, intensity: number) => bridge.setEmotion(emotion, intensity),
    setConversationState: (state: ConversationState) => bridge.setConversationState(state),
    reset: () => bridge.reset(),
    getSnapshot: () => bridge.getSnapshot(),
  });
  target.AvatarController = facade;
  let signalledGeneration: number | null = null;
  const unsubscribe = bridge.subscribe((snapshot) => {
    target.dispatchEvent(new CustomEvent(snapshot.ready ? 'AVATAR_READY' : 'AVATAR_NOT_READY',
      { detail: { type: snapshot.ready ? 'AVATAR_READY' : 'AVATAR_NOT_READY', modelUrl: snapshot.modelUrl, generation: snapshot.generation, lifecycle: snapshot.lifecycle } }));
    if (options.notifyKoiBridgeOnReady && snapshot.ready && signalledGeneration !== snapshot.generation) {
      signalledGeneration = snapshot.generation;
      try {
        target.KoiBridge?.postMessage('AVATAR_READY');
      } catch {
        // A missing or failing native channel must never break avatar rendering.
      }
    }
  });
  return () => {
    bridge.dispose(); unsubscribe();
    if (target.AvatarController === facade) delete target.AvatarController;
  };
}
