// Mobile entry: does what repos/koi-backend/nextjs_app/src/app/avatar-host/page.tsx
// does (feat/avatar-webview-host 223e97c) — read ?model=, mount the host —
// plus window.KoiSpeech below. `female` picks female; anything else picks
// male.
import './base.css';
import { createRoot } from 'react-dom/client';
import VRMAvatarRenderer from './components/avatar/VRMAvatarRenderer';
import styles from './components/avatar/AvatarWebViewHost.module.css';
import type { AvatarHostModel } from './components/avatar/AvatarWebViewHost';
import { parseMouthCues, type MouthCue, type SpeechFrame, type SpeechTimeline } from './lib/speech/mouthCues';

// Older Android WebViews (< Chromium 93) lack Object.hasOwn, which
// VRMAvatarController.ts uses.
if (!Object.hasOwn) Object.defineProperty(Object, 'hasOwn', { value: (o: object, k: PropertyKey) => Object.prototype.hasOwnProperty.call(o, k), configurable: true, writable: true });

// Lip-sync for the app's voice (Prompt 25). Dart plays the audio and calls
// KoiSpeech.start(cuesJson) when playback starts (only after AVATAR_READY,
// argument via jsonEncode) and KoiSpeech.stop() when it stops. Cues are
// Rhubarb {start, end, value} in seconds from start(); invalid cues stop
// the mouth instead of throwing.
declare global {
  interface Window {
    KoiSpeech?: { start(cuesJson: string): boolean; stop(): void };
  }
}
const IDLE: SpeechFrame = Object.freeze({ active: false, time: 0, cues: Object.freeze([]) });
let cues: readonly MouthCue[] = [];
let startedAt: number | null = null;
const stop = () => { startedAt = null; cues = []; };
const speech: SpeechTimeline = {
  getFrame() {
    if (startedAt === null) return IDLE;
    const time = (performance.now() - startedAt) / 1000;
    if (time >= cues[cues.length - 1].end) { stop(); return IDLE; }
    return { active: true, time, cues };
  },
};
window.KoiSpeech = Object.freeze({
  start(cuesJson: string) {
    try {
      const parsed = parseMouthCues(JSON.parse(cuesJson));
      if (parsed.length === 0) { stop(); return false; }
      cues = parsed; startedAt = performance.now();
      return true;
    } catch { stop(); return false; }
  },
  stop,
});

// Mirrors Fatima's AvatarWebViewHost (same markup, CSS module and
// VRMAvatarRenderer props) plus speechSource, which her host does not pass.
// Her copied files stay unchanged.
const MODEL_URLS: Record<AvatarHostModel, string> = {
  male: '/models/koi-male.vrm',
  female: '/models/koi-female.vrm',
};
function Host({ model }: { model: AvatarHostModel }) {
  return (
    <main className={styles.host} data-testid="avatar-host" data-model={model}>
      <section className={styles.stage} aria-label="KOI companion avatar">
        <VRMAvatarRenderer
          modelUrl={MODEL_URLS[model]}
          minHeight={0}
          maxPixelRatio={1.25}
          exposeController
          notifyKoiBridgeOnReady
          showStatus={false}
          speechSource={speech}
        />
      </section>
    </main>
  );
}

const model: AvatarHostModel = new URLSearchParams(window.location.search).get('model') === 'female' ? 'female' : 'male';
createRoot(document.getElementById('root')!).render(<Host model={model} />);
