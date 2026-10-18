// Copied from repos/koi-backend/nextjs_app/src/components/avatar/VRMMouthController.ts (branch feat/avatar-webview-host, commit 223e97c).
// Copied, do not edit here: change upstream and re-copy.
import type { VRMExpressionManager } from '@pixiv/three-vrm';
import { MOUTH_PRESETS, mouthAt, type SpeechTimeline } from '../../lib/speech/mouthCues';
export interface MouthSnapshot { time: number | null; active: boolean; cue: string | null; preset: string | null; weight: number; }
export class VRMMouthController {
  private snapshot: MouthSnapshot = { time: null, active: false, cue: null, preset: null, weight: 0 };
  getSnapshot() { return { ...this.snapshot }; }
  private source?: SpeechTimeline; private disposed = false;
  constructor(private manager?: Pick<VRMExpressionManager, 'getExpression' | 'setValue'> | null) {}
  setSource(source?: SpeechTimeline) { if (this.disposed || source === this.source) return; this.reset(); this.source = source; }
  update() {
    if (this.disposed || !this.source) return;
    const frame = this.source.getFrame(), target = mouthAt(frame);
    this.snapshot = { time: frame.time, active: frame.active, ...target };
    for (const name of MOUTH_PRESETS) if (this.manager?.getExpression(name)) this.manager.setValue(name, name === target.preset ? target.weight : 0);
  }
  reset() { if (this.disposed || !this.source) return; this.snapshot = { time: null, active: false, cue: null, preset: null, weight: 0 }; for (const name of MOUTH_PRESETS) if (this.manager?.getExpression(name)) this.manager.setValue(name, 0); }
  dispose() { if (this.disposed) return; if (this.source) this.reset(); this.source = undefined; this.disposed = true; }
}
