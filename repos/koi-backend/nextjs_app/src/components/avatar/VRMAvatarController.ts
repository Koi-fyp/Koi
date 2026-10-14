import { VRMMouthController, type MouthSnapshot } from './VRMMouthController';
import type { SpeechTimeline } from '../../lib/speech/mouthCues';
import { Euler, Quaternion, Vector3, type Object3D } from 'three';
import type { VRMExpressionManager, VRMHumanoid } from '@pixiv/three-vrm';

export type KoiEmotion = 'neutral' | 'joy' | 'angry' | 'sorrow' | 'fun';
export type ConversationState = 'idle' | 'listening' | 'thinking' | 'speaking';
export const EMOTION_PRESETS = { joy: 'happy', angry: 'angry', sorrow: 'sad', fun: 'relaxed' } as const;
const presets = Object.values(EMOTION_PRESETS);
export const MAX_EMOTION_WEIGHT = 0.65;
export function normalizeEmotion(value: unknown): KoiEmotion {
  return typeof value === 'string' && (value === 'neutral' || Object.hasOwn(EMOTION_PRESETS, value)) ? value as KoiEmotion : 'neutral';
}
export function normalizeConversationState(value: unknown): ConversationState {
  return ['idle', 'listening', 'thinking', 'speaking'].includes(value as string) ? value as ConversationState : 'idle';
}
export function clampIntensity(value: number): number { return Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0; }
interface AnimationRig {
  expressionManager?: Pick<VRMExpressionManager, 'getExpression' | 'getValue' | 'setValue'> | null;
  humanoid: Pick<VRMHumanoid, 'getNormalizedBoneNode'>;
}
interface BoneBase { node: Object3D; position: Vector3; quaternion: Quaternion; }
interface Fade { from: number; to: number; elapsed: number; duration: number; leaving: boolean; }
export interface AvatarAnimationSnapshot {
  emotion: KoiEmotion; intensity: number; conversationState: ConversationState;
  weights: Record<string, number>; mouthWeights: Record<string, number>; blinkWeight: number; nextBlinkIn: number;
  headRotation: number[]; chestOffset: number; reducedMotion: boolean; disposed: boolean;
  availableEmotions: KoiEmotion[];
  speech: MouthSnapshot;
}
export interface AvatarAnimationController {
  setEmotion(emotion: KoiEmotion, intensity: number): boolean;
  setConversationState(state: ConversationState): void;
  reset(): void;
  update(deltaTime: number): void;
  dispose(): void;
}

/** No timers or rendering ownership. Call update BEFORE vrm.update in the existing loop. */
export class VRMAvatarController implements AvatarAnimationController {
  private readonly manager;
  private readonly mouth: VRMMouthController;
  private readonly head?: BoneBase;
  private readonly chest?: BoneBase;
  private readonly blinkNames: string[];
  private readonly rotation = new Quaternion();
  private readonly euler = new Euler();
  private targetEmotion: KoiEmotion = 'neutral';
  private intensity = 0;
  private state: ConversationState = 'idle';
  private active: string | null = null;
  private weight = 0;
  private fade: Fade | null = null;
  private time = 0;
  private pitch = 0;
  private yaw = 0;
  private roll = 0;
  private seed: number;
  private readonly initialSeed: number;
  private nextBlink = 0;
  private blinkTime = -1;
  private blinkWeight = 0;
  private reducedMotion: boolean;
  private disposed = false;

  constructor(rig: AnimationRig, options: { seed?: number; reducedMotion?: boolean } = {}) {
    this.manager = rig.expressionManager;
    this.mouth = new VRMMouthController(this.manager);
    this.seed = this.initialSeed = (options.seed ?? 0x4b4f49) >>> 0;
    this.reducedMotion = options.reducedMotion ?? false;
    const capture = (node: Object3D | null): BoneBase | undefined => node ? { node, position: node.position.clone(), quaternion: node.quaternion.clone() } : undefined;
    this.head = capture(rig.humanoid.getNormalizedBoneNode('head'));
    this.chest = capture(rig.humanoid.getNormalizedBoneNode('chest') ?? rig.humanoid.getNormalizedBoneNode('spine'));
    this.blinkNames = this.has('blink') ? ['blink'] : this.has('blinkLeft') && this.has('blinkRight') ? ['blinkLeft', 'blinkRight'] : [];
    this.clearOwnedExpressions();
    this.nextBlink = this.blinkInterval();
  }
  private has(name: string): boolean { return !!this.manager?.getExpression(name); }
  private write(name: string, weight: number) { if (this.has(name)) this.manager!.setValue(name, weight); }
  private random() {
    this.seed = (this.seed + 0x6d2b79f5) >>> 0;
    let value = this.seed;
    value = Math.imul(value ^ value >>> 15, value | 1);
    value ^= value + Math.imul(value ^ value >>> 7, value | 61);
    return ((value ^ value >>> 14) >>> 0) / 4294967296;
  }
  private blinkInterval() { return 3.2 + this.random() * 3; }
  private clearOwnedExpressions() {
    for (const preset of presets) this.write(preset, 0);
    this.write('neutral', 0); // Rest is zero emotional weights, not a forced neutral morph.
    for (const name of this.blinkNames) this.write(name, 0);
  }
  private beginFade(to: number, leaving: boolean) {
    this.fade = { from: this.weight, to, elapsed: 0, duration: leaving ? 0.22 : 0.38, leaving };
  }
  setEmotion(emotion: KoiEmotion, intensity: number): boolean {
    if (this.disposed) return false;
    let next = normalizeEmotion(emotion);
    const supported = next === 'neutral' || this.has(EMOTION_PRESETS[next]);
    if (!supported) next = 'neutral';
    const amount = next === 'neutral' ? 0 : clampIntensity(intensity);
    if (next === this.targetEmotion && amount === this.intensity) return supported;
    this.targetEmotion = next;
    this.intensity = amount;
    const targetPreset = next === 'neutral' || amount === 0 ? null : EMOTION_PRESETS[next];
    if (this.active && this.active !== targetPreset) this.beginFade(0, true);
    else { this.active = targetPreset; this.beginFade(amount * MAX_EMOTION_WEIGHT, false); }
    return supported;
  }
  setConversationState(state: ConversationState) { if (!this.disposed) this.state = normalizeConversationState(state); }
  setSpeechSource(source?: SpeechTimeline) { this.mouth.setSource(source); }
  setReducedMotion(reduced: boolean) { if (!this.disposed) this.reducedMotion = reduced; }
  reset() {
    if (this.disposed) return;
    this.setEmotion('neutral', 0);
    this.mouth.reset();
    this.state = 'idle'; this.time = 0; this.pitch = this.yaw = this.roll = 0;
    this.seed = this.initialSeed; this.nextBlink = this.blinkInterval(); this.blinkTime = -1; this.blinkWeight = 0;
    for (const name of this.blinkNames) this.write(name, 0);
    this.restoreBones();
  }
  private restoreBones() {
    for (const bone of [this.head, this.chest]) if (bone) { bone.node.position.copy(bone.position); bone.node.quaternion.copy(bone.quaternion); }
  }
  private updateEmotion(delta: number) {
    let remaining = delta;
    while (this.fade && remaining > 0) {
      const fade = this.fade;
      const step = Math.min(remaining, fade.duration - fade.elapsed);
      fade.elapsed += step; remaining -= step;
      const t = Math.min(1, fade.elapsed / fade.duration);
      const smooth = t * t * (3 - 2 * t);
      this.weight = fade.from + (fade.to - fade.from) * smooth;
      if (t < 1) break;
      this.fade = null;
      if (fade.leaving) {
        this.active = this.targetEmotion === 'neutral' || this.intensity === 0 ? null : EMOTION_PRESETS[this.targetEmotion];
        if (this.active) this.beginFade(this.intensity * MAX_EMOTION_WEIGHT, false);
      }
    }
    // Exclusive ownership: at most one emotional preset is nonzero, including during transitions.
    for (const preset of presets) this.write(preset, preset === this.active ? this.weight : 0);
    this.write('neutral', 0);
  }
  private updateBlink(delta: number) {
    if (!this.blinkNames.length) return;
    if (this.blinkTime < 0) {
      this.nextBlink -= delta;
      if (this.nextBlink <= 0) this.blinkTime = -this.nextBlink;
    } else this.blinkTime += delta;
    if (this.blinkTime >= 0) {
      const t = this.blinkTime;
      const smooth = (value: number) => value * value * (3 - 2 * value);
      this.blinkWeight = t < 0.075 ? smooth(t / 0.075) : t < 0.1 ? 1 : t < 0.22 ? 1 - smooth((t - 0.1) / 0.12) : 0;
      if (t >= 0.22) { this.blinkTime = -1; this.nextBlink = this.blinkInterval(); }
    }
    for (const name of this.blinkNames) this.write(name, this.blinkWeight);
  }
  private updatePosture(delta: number) {
    if (this.reducedMotion) { this.restoreBones(); return; }
    const response = 1 - Math.exp(-4 * delta);
    const pitchTarget = this.state === 'listening' ? -0.018 : this.state === 'thinking' ? 0.012 : 0;
    const yawTarget = this.state === 'thinking' ? 0.035 : 0;
    const rollTarget = this.state === 'listening' ? 0.008 : 0;
    this.pitch += (pitchTarget - this.pitch) * response;
    this.yaw += (yawTarget - this.yaw) * response;
    this.roll += (rollTarget - this.roll) * response;
    const speaking = this.state === 'speaking' ? 1 : 0;
    if (this.head) {
      this.euler.set(this.pitch + Math.sin(this.time * 0.7) * 0.004 + speaking * Math.sin(this.time * 1.8) * 0.006,
        this.yaw + Math.sin(this.time * 0.41) * 0.007,
        this.roll + Math.sin(this.time * 0.31) * 0.003);
      this.head.node.quaternion.copy(this.head.quaternion).multiply(this.rotation.setFromEuler(this.euler));
    }
    if (this.chest) {
      this.chest.node.position.copy(this.chest.position);
      this.chest.node.position.y += Math.sin(this.time * 1.25) * 0.0015;
      this.euler.set(-this.pitch * 0.15, 0, 0);
      this.chest.node.quaternion.copy(this.chest.quaternion).multiply(this.rotation.setFromEuler(this.euler));
    }
  }
  update(deltaTime: number) {
    if (this.disposed || !Number.isFinite(deltaTime) || deltaTime <= 0) return;
    const delta = Math.min(deltaTime, 0.1); // Avoid a burst after background-tab stalls.
    this.time += delta;
    this.updateEmotion(delta); this.updateBlink(delta); this.updatePosture(delta); this.mouth.update();
  }
  getSnapshot(): AvatarAnimationSnapshot {
    return { speech: this.mouth.getSnapshot(), emotion: this.targetEmotion, intensity: this.intensity, conversationState: this.state,
      weights: Object.fromEntries(presets.map((name) => [name, this.manager?.getValue(name) ?? 0])),
      mouthWeights: Object.fromEntries(['aa', 'ih', 'ou', 'ee', 'oh'].map((name) => [name, this.manager?.getValue(name) ?? 0])),
      blinkWeight: this.blinkWeight, nextBlinkIn: this.nextBlink,
      headRotation: this.head?.node.quaternion.toArray() ?? [],
      chestOffset: this.chest ? this.chest.node.position.y - this.chest.position.y : 0,
      reducedMotion: this.reducedMotion, disposed: this.disposed,
      availableEmotions: ['neutral', ...Object.keys(EMOTION_PRESETS).filter((name) => this.has(EMOTION_PRESETS[name as keyof typeof EMOTION_PRESETS]))] as KoiEmotion[] };
  }
  dispose() {
    if (this.disposed) return;
    this.mouth.dispose();
    this.clearOwnedExpressions(); this.restoreBones(); this.fade = null; this.weight = 0; this.blinkWeight = 0; this.active = null; this.disposed = true;
  }
}
