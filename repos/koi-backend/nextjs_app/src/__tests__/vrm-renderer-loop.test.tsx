import { StrictMode } from 'react';
import { act, render } from '@testing-library/react';
import type { SpeechTimeline } from '@/lib/speech/mouthCues';

const mockRenderers: { disposed: boolean; canvas: HTMLCanvasElement; renders: number }[] = [];
jest.mock('three', () => {
  const actual = jest.requireActual('three');
  class FakeWebGLRenderer {
    domElement = document.createElement('canvas');
    renderLists = { dispose: () => {} };
    outputColorSpace = ''; toneMapping = 0;
    private record = { disposed: false, canvas: this.domElement, renders: 0 };
    constructor() { mockRenderers.push(this.record); }
    setPixelRatio() {} setSize() {}
    render() { this.record.renders++; }
    dispose() { this.record.disposed = true; }
    forceContextLoss() {}
  }
  return { ...actual, WebGLRenderer: FakeWebGLRenderer };
});
jest.mock('three/addons/loaders/GLTFLoader.js', () => ({ GLTFLoader: class {} }), { virtual: true });
import VRMAvatarRenderer from '@/components/avatar/VRMAvatarRenderer';

const frames = new Map<number, FrameRequestCallback>();
let nextFrame = 0;
function runFrames(count: number) {
  for (let index = 0; index < count; index++) act(() => {
    const due = [...frames.entries()]; frames.clear();
    for (const [, callback] of due) callback(performance.now());
  });
}
beforeEach(() => {
  frames.clear(); mockRenderers.length = 0;
  window.requestAnimationFrame = jest.fn((callback: FrameRequestCallback) => { frames.set(++nextFrame, callback); return nextFrame; });
  window.cancelAnimationFrame = jest.fn((id: number) => { frames.delete(id); });
  window.matchMedia = jest.fn(() => ({ matches: false, addEventListener: () => {}, removeEventListener: () => {} })) as never;
  (window as unknown as { ResizeObserver: unknown }).ResizeObserver = class { observe() {} disconnect() {} };
  // Model never arrives: the loop and canvas exist from mount, independent of the VRM download.
  global.fetch = jest.fn(() => new Promise<Response>(() => {}));
});

const source = (): SpeechTimeline => ({ getFrame: () => ({ active: false, time: 0, cues: [] }) });
describe('VRMAvatarRenderer animation loop', () => {
  it('keeps exactly one rAF chain and one canvas across speech, emotion and state changes, StrictMode and remounts', () => {
    const { container, rerender, unmount } = render(<StrictMode><VRMAvatarRenderer speechSource={source()} /></StrictMode>);
    const live = () => mockRenderers.filter(renderer => !renderer.disposed);
    expect(container.querySelectorAll('canvas')).toHaveLength(1);
    expect(live()).toHaveLength(1);
    expect(frames.size).toBe(1);
    runFrames(5); expect(frames.size).toBe(1);
    for (const [emotion, state] of [['joy', 'speaking'], ['sorrow', 'listening'], ['neutral', 'idle']] as const) {
      rerender(<StrictMode><VRMAvatarRenderer speechSource={source()} emotion={emotion} emotionIntensity={0.5} conversationState={state} /></StrictMode>);
      runFrames(3);
      expect(frames.size).toBe(1);
      expect(container.querySelectorAll('canvas')).toHaveLength(1);
    }
    expect(live()).toHaveLength(1);
    const renders = live()[0].renders; runFrames(4); expect(live()[0].renders).toBe(renders + 4);
    // Avatar switch: the old renderer, canvas and loop are released before the new ones run.
    rerender(<StrictMode><VRMAvatarRenderer modelUrl="/models/koi-female.vrm" speechSource={source()} /></StrictMode>);
    expect(container.querySelectorAll('canvas')).toHaveLength(1);
    expect(live()).toHaveLength(1);
    expect(frames.size).toBe(1);
    runFrames(3); expect(frames.size).toBe(1);
    unmount();
    expect(frames.size).toBe(0);
    expect(live()).toHaveLength(0);
    expect(document.querySelectorAll('canvas')).toHaveLength(0);
  });
});
