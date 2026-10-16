'use client';
import type { SpeechTimeline } from '../../lib/speech/mouthCues';

import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { type VRM, VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm';
import { VRMAvatarController, type KoiEmotion, type ConversationState } from './VRMAvatarController';
import { AvatarCommandBridge, registerAvatarCommands } from './avatarCommandBridge';

export interface VRMAvatarRendererProps {
  modelUrl?: string;
  minHeight?: number;
  maxPixelRatio?: number;
  emotion?: KoiEmotion;
  emotionIntensity?: number;
  conversationState?: ConversationState;
  exposeController?: boolean;
  notifyKoiBridgeOnReady?: boolean;
  animationSeed?: number;
  onLoadError?: () => void;
  speechSource?: SpeechTimeline;
  onReady?: () => void;
}
type LoadState = 'loading' | 'ready' | 'error';

// Owns only the model resources. This also handles a parse completing after unmount.
function disposeModel(model: THREE.Object3D) {
  const bitmaps = new Set<ImageBitmap>();
  model.traverse((object) => {
    if (!(object instanceof THREE.Mesh)) return;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    for (const material of materials) {
      for (const value of Object.values(material)) {
        if (value instanceof THREE.Texture && typeof ImageBitmap !== 'undefined' && value.image instanceof ImageBitmap) {
          bitmaps.add(value.image);
        }
      }
    }
  });
  VRMUtils.deepDispose(model);
  bitmaps.forEach((bitmap) => bitmap.close());
}

export default function VRMAvatarRenderer({ modelUrl = '/models/koi-male.vrm', minHeight = 240, maxPixelRatio = 2, emotion = 'neutral', emotionIntensity = 0, conversationState = 'idle', exposeController = false, notifyKoiBridgeOnReady = false, animationSeed = 0x4b4f49, onLoadError, speechSource, onReady }: VRMAvatarRendererProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<LoadState>('loading');
  const [error, setError] = useState('');
  const [attempt, setAttempt] = useState(0);

  const speechRef = useRef(speechSource); speechRef.current = speechSource;
  const readyRef = useRef(onReady); readyRef.current = onReady;
  const loadErrorRef = useRef(onLoadError);
  loadErrorRef.current = onLoadError;
  const commandsRef = useRef<AvatarCommandBridge | null>(null);
  const initialCommands = useRef({ emotion, emotionIntensity, conversationState });
  initialCommands.current = { emotion, emotionIntensity, conversationState };
  useEffect(() => {
    const bridge = new AvatarCommandBridge();
    commandsRef.current = bridge;
    bridge.setEmotion(initialCommands.current.emotion, initialCommands.current.emotionIntensity);
    bridge.setConversationState(initialCommands.current.conversationState);
    const unregister = exposeController ? registerAvatarCommands(bridge, window, { notifyKoiBridgeOnReady }) : undefined;
    return () => { unregister?.(); bridge.dispose(); if (commandsRef.current === bridge) commandsRef.current = null; };
  }, [exposeController, notifyKoiBridgeOnReady]);
  useEffect(() => { commandsRef.current?.setEmotion(emotion, emotionIntensity); }, [emotion, emotionIntensity]);
  useEffect(() => { commandsRef.current?.setConversationState(conversationState); }, [conversationState]);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    let disposed = false;
    let renderer: THREE.WebGLRenderer | undefined;
    let observer: ResizeObserver | undefined;
    let vrm: VRM | undefined;
    let controller: VRMAvatarController | undefined;
    const commands = commandsRef.current;
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const motionChanged = () => controller?.setReducedMotion(reducedMotion.matches);
    reducedMotion.addEventListener('change', motionChanged);
    let frame = 0;
    let model: THREE.Object3D | undefined;
    let readyReported = false;
    const abort = new AbortController();
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(30, 1, 0.01, 30);
    const clock = new THREE.Clock();
    let target = new THREE.Vector3(0, 1.35, 0);
    let frameHeight = 0.9;
    let frameWidth = 0.8;
    setState('loading');
    setError('');

    const fail = (cause: unknown) => {
      if (disposed) return;
      cancelAnimationFrame(frame);
      if (controller) { commands?.detach(controller); controller.dispose(); }
      setError(cause instanceof Error ? cause.message : 'Unable to render this model.');
      setState('error');
      loadErrorRef.current?.();
    };
    const resize = () => {
      if (!renderer || disposed) return;
      const width = Math.max(1, container.clientWidth);
      const height = Math.max(1, container.clientHeight);
      camera.aspect = width / height;
      const tangent = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
      const distance = Math.max(frameHeight / (2 * tangent), frameWidth / (2 * tangent * camera.aspect)) * 1.12;
      camera.position.set(target.x, target.y, target.z + distance);
      camera.lookAt(target);
      camera.updateProjectionMatrix();
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, Math.max(1, maxPixelRatio)));
      renderer.setSize(width, height, false);
    };
    const tick = () => {
      if (disposed || !renderer) return;
      try {
        const delta = Math.min(clock.getDelta(), 0.05);
        controller?.setSpeechSource(speechRef.current);
        controller?.update(delta);
        vrm?.update(delta);
        renderer.render(scene, camera);
        if (vrm && controller && !readyReported) {
          readyReported = true;
          setState('ready');
          commands?.markReady(controller);
          readyRef.current?.();
        }
        frame = requestAnimationFrame(tick);
      } catch (cause) { fail(cause); }
    };
    const contextLost = (event: Event) => {
      event.preventDefault();
      fail(new Error('The graphics context was lost. Retry to reload the avatar.'));
    };

    try {
      renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
      renderer.outputColorSpace = THREE.SRGBColorSpace;
      renderer.toneMapping = THREE.ACESFilmicToneMapping;
      renderer.domElement.style.cssText = 'display:block;width:100%;height:100%;';
      renderer.domElement.setAttribute('aria-label', 'KOI 3D avatar');
      renderer.domElement.addEventListener('webglcontextlost', contextLost);
      container.appendChild(renderer.domElement);
      scene.add(new THREE.HemisphereLight(0xffffff, 0xc7a68b, 0.8));
      const key = new THREE.DirectionalLight(0xffffff, Math.PI * 0.65);
      key.position.set(1, 2, 3);
      scene.add(key);
      const fill = new THREE.DirectionalLight(0xd9e7ff, 0.35);
      fill.position.set(-2, 1, 1);
      scene.add(fill);
      observer = new ResizeObserver(resize);
      observer.observe(container);
      window.addEventListener('resize', resize);
      resize();
      tick();

      void (async () => {
        // Fetch can be cancelled. GLTF parsing cannot; its late result is disposed below.
        const response = await fetch(modelUrl, { signal: abort.signal });
        if (!response.ok) throw new Error(`Model request failed (${response.status}).`);
        const bytes = await response.arrayBuffer();
        if (disposed) return;
        if (bytes.byteLength < 12 || new DataView(bytes).getUint32(0, true) !== 0x46546c67) {
          throw new Error('The model response is not a binary glTF/VRM file.');
        }
        const loader = new GLTFLoader();
        loader.register((parser) => new VRMLoaderPlugin(parser));
        const resourcePath = new URL('.', new URL(modelUrl, window.location.href)).href;
        const gltf = await loader.parseAsync(bytes, resourcePath);
        if (disposed) { disposeModel(gltf.scene); return; }
        model = gltf.scene;
        const loaded = gltf.userData.vrm as VRM | undefined;
        if (!loaded) throw new Error('The file does not contain a supported VRM avatar.');
        vrm = loaded;
        VRMUtils.rotateVRM0(vrm); // VRM 0.x normalization; supplied VRM 1.0 stays unchanged.
        // Static relaxed pose, not an emotion or animation controller.
        vrm.humanoid.setNormalizedPose({
          leftUpperArm: { rotation: new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, -1.1)).toArray() },
          rightUpperArm: { rotation: new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, 1.1)).toArray() },
        });
        vrm.update(0);
        const bounds = new THREE.Box3().setFromObject(vrm.scene);
        const originalHeight = bounds.getSize(new THREE.Vector3()).y;
        if (!Number.isFinite(originalHeight) || originalHeight <= 0) throw new Error('The model has invalid bounds.');
        vrm.scene.scale.multiplyScalar(1.7 / originalHeight);
        vrm.scene.updateMatrixWorld(true);
        bounds.setFromObject(vrm.scene);
        vrm.scene.position.y -= bounds.min.y;
        scene.add(vrm.scene);
        vrm.scene.traverse((object) => { object.frustumCulled = false; });
        vrm.update(0);
        scene.updateMatrixWorld(true);
        bounds.setFromObject(vrm.scene);
        const head = vrm.humanoid.getNormalizedBoneNode('head');
        const leftShoulder = vrm.humanoid.getNormalizedBoneNode('leftUpperArm');
        const rightShoulder = vrm.humanoid.getNormalizedBoneNode('rightUpperArm');
        if (!head) throw new Error('The model is missing its humanoid head bone.');
        const headPosition = head.getWorldPosition(new THREE.Vector3());
        const top = bounds.max.y + 0.07;
        const bottom = headPosition.y - 0.4;
        target = new THREE.Vector3(headPosition.x, (top + bottom) / 2, headPosition.z);
        frameHeight = top - bottom;
        frameWidth = leftShoulder && rightShoulder
          ? leftShoulder.getWorldPosition(new THREE.Vector3()).distanceTo(rightShoulder.getWorldPosition(new THREE.Vector3())) + 0.35
          : 0.8;
        resize();
        controller = new VRMAvatarController(vrm, { seed: animationSeed, reducedMotion: reducedMotion.matches });
        commands?.bind(controller, modelUrl);
      })().catch(fail);
    } catch (cause) { fail(cause); }

    return () => {
      disposed = true;
      abort.abort();
      cancelAnimationFrame(frame);
      observer?.disconnect();
      reducedMotion.removeEventListener('change', motionChanged);
      if (controller) { commands?.detach(controller); controller.dispose(); }
      window.removeEventListener('resize', resize);
      if (model) { scene.remove(model); disposeModel(model); }
      if (renderer) {
        renderer.domElement.removeEventListener('webglcontextlost', contextLost);
        renderer.renderLists.dispose();
        renderer.dispose();
        renderer.forceContextLoss();
        renderer.domElement.remove();
      }
      scene.clear();
    };
  }, [modelUrl, attempt, maxPixelRatio, exposeController, animationSeed]);

  return (
    <div data-avatar-state={state} style={{ position: 'relative', width: '100%', height: '100%', minHeight,
      background: 'radial-gradient(ellipse at 50% 40%, #fff7ed 0%, #ffe5d9 65%, #ffd9bb 100%)' }}>
      <div ref={containerRef} style={{ width: '100%', height: '100%' }} />
      {state !== 'ready' && (
        <div role={state === 'error' ? 'alert' : 'status'} aria-live="polite"
          style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
            alignItems: 'center', justifyContent: 'center', padding: 24, textAlign: 'center', gap: 12,
            fontFamily: 'var(--font-body, system-ui)', background: '#ffe5d9' }}>
          <strong>{state === 'error' ? 'Avatar unavailable' : 'Loading your KOI avatar...'}</strong>
          {state === 'error' && <><span>{error}</span><button type="button" onClick={() => setAttempt((value) => value + 1)}
            style={{ padding: '10px 20px', border: '2px solid #171717', borderRadius: 12,
              background: 'var(--neo-yellow, #ffd100)', cursor: 'pointer', fontWeight: 700 }}>Retry</button></>}
        </div>
      )}
    </div>
  );
}
