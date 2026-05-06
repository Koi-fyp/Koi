export type Emotion = 'happy' | 'sad' | 'anxious' | 'calm' | 'neutral';

type MorphMap = Record<string, number>;

const EMOTION_MORPHS: Record<Emotion, MorphMap> = {
  happy:   { mouthSmile: 0.8, eyeSquint: 0.3 },
  sad:     { mouthFrown: 0.6, browDown: 0.5 },
  anxious: { browInnerUp: 0.7, mouthFrown: 0.3 },
  calm:    {},
  neutral: {},
};

const EMOTION_SPHERE_COLORS: Record<Emotion, number> = {
  happy:   0xFFC107,
  sad:     0x90CAF9,
  anxious: 0xFF8A65,
  calm:    0xA5D6A7,
  neutral: 0xBCAAA4,
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyTHREE = any;

export class AvatarAnimator {
  private THREE: AnyTHREE;
  private scene: AnyTHREE;
  private camera: AnyTHREE;
  private renderer: AnyTHREE;
  private animFrameId = 0;
  private clock: AnyTHREE;

  private mesh: AnyTHREE = null;
  private morphedMesh: AnyTHREE = null;

  private currentMorphs: MorphMap = {};
  private targetMorphs: MorphMap = {};
  private morphProgress = 0;
  private morphDuration = 0.5;

  private breathPhase = 0;

  private blinkTimer = 0;
  private nextBlink = 3 + Math.random() * 3;
  private isBlinking = false;
  private blinkProgress = 0;

  private fpsFrames = 0;
  private fpsLastTime = 0;
  private lowFpsStreak = 0;
  private downgraded = false;

  constructor(THREE: AnyTHREE) {
    this.THREE = THREE;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(45, 1, 0.1, 100);
    this.camera.position.set(0, 1.6, 2);
    this.camera.lookAt(0, 1.6, 0);
    this.clock = new THREE.Clock();

    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    const ambient = new THREE.AmbientLight(0xffffff, 0.6);
    this.scene.add(ambient);
    const dir = new THREE.DirectionalLight(0xffffff, 0.8);
    dir.position.set(1, 2, 1);
    this.scene.add(dir);

    this.fpsLastTime = performance.now();
  }

  mount(container: HTMLElement): void {
    const w = container.clientWidth;
    const h = container.clientHeight;
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h);
    container.appendChild(this.renderer.domElement);
    this.buildSphere('neutral');
    this.tick();
  }

  private buildSphere(emotion: Emotion): void {
    if (this.mesh) this.scene.remove(this.mesh);
    const geo = new this.THREE.SphereGeometry(0.55, 48, 48);
    const mat = new this.THREE.MeshLambertMaterial({ color: EMOTION_SPHERE_COLORS[emotion] });
    this.mesh = new this.THREE.Mesh(geo, mat);
    this.mesh.position.set(0, 1.6, 0);
    this.scene.add(this.mesh);
  }

  loadGLB(url: string, GLTFLoader: AnyTHREE): void {
    const loader = new GLTFLoader();
    loader.load(
      url,
      (gltf: AnyTHREE) => {
        if (this.mesh) this.scene.remove(this.mesh);
        const model = gltf.scene;
        this.scene.add(model);
        model.traverse((child: AnyTHREE) => {
          if (child.isMesh && child.morphTargetInfluences) {
            this.morphedMesh = child;
          }
        });
      },
      undefined,
      () => { /* GLB load failed — sphere stays */ },
    );
  }

  setEmotion(emotion: Emotion): void {
    this.targetMorphs = { ...EMOTION_MORPHS[emotion] };
    this.morphProgress = 0;

    if (this.mesh && !this.morphedMesh) {
      this.mesh.material.color.setHex(EMOTION_SPHERE_COLORS[emotion]);
    }
  }

  private applyMorphs(delta: number): void {
    if (!this.morphedMesh) return;
    this.morphProgress = Math.min(1, this.morphProgress + delta / this.morphDuration);
    const t = this.morphProgress;

    const allKeys = new Set([
      ...Object.keys(this.currentMorphs),
      ...Object.keys(this.targetMorphs),
    ]);

    const next: MorphMap = {};
    for (const key of allKeys) {
      const from = this.currentMorphs[key] ?? 0;
      const to = this.targetMorphs[key] ?? 0;
      next[key] = from + (to - from) * t;
    }

    const dict = this.morphedMesh.morphTargetDictionary as Record<string, number>;
    const influences = this.morphedMesh.morphTargetInfluences as number[];
    for (const key of Object.keys(dict)) {
      influences[dict[key]] = next[key] ?? 0;
    }

    if (this.morphProgress >= 1) this.currentMorphs = { ...this.targetMorphs };
  }

  private applyBreathe(delta: number): void {
    if (!this.mesh && !this.morphedMesh) return;
    this.breathPhase += delta * 0.3;
    const scale = 1 + Math.sin(this.breathPhase) * 0.02;
    const target = this.morphedMesh ?? this.mesh;
    if (target) target.scale.set(1, scale, 1);
  }

  private applyBlink(delta: number): void {
    this.blinkTimer += delta;
    if (!this.isBlinking && this.blinkTimer >= this.nextBlink) {
      this.isBlinking = true;
      this.blinkProgress = 0;
      this.nextBlink = 3 + Math.random() * 3;
      this.blinkTimer = 0;
    }

    if (!this.isBlinking || !this.morphedMesh) return;

    this.blinkProgress += delta / 0.15;
    const t = Math.min(this.blinkProgress, 1);
    const val = t <= 0.5 ? t * 2 : (1 - t) * 2;

    const dict = this.morphedMesh.morphTargetDictionary as Record<string, number>;
    const influences = this.morphedMesh.morphTargetInfluences as number[];
    if ('eyeBlink' in dict) influences[dict['eyeBlink']] = val;

    if (this.blinkProgress >= 1) this.isBlinking = false;
  }

  private checkFPS(now: number): void {
    this.fpsFrames++;
    const elapsed = now - this.fpsLastTime;
    if (elapsed >= 1000) {
      const fps = (this.fpsFrames / elapsed) * 1000;
      this.fpsFrames = 0;
      this.fpsLastTime = now;
      if (fps < 30) {
        this.lowFpsStreak++;
        if (this.lowFpsStreak >= 5 && !this.downgraded) {
          this.downgraded = true;
          this.renderer.setPixelRatio(0.5);
          console.log('avatar_downgraded');
        }
      } else {
        this.lowFpsStreak = 0;
      }
    }
  }

  private tick = (): void => {
    this.animFrameId = requestAnimationFrame(this.tick);
    const delta = this.clock.getDelta();
    const now = performance.now();

    this.checkFPS(now);
    this.applyMorphs(delta);
    this.applyBreathe(delta);
    this.applyBlink(delta);

    this.renderer.render(this.scene, this.camera);
  };

  resize(w: number, h: number): void {
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h);
  }

  destroy(): void {
    cancelAnimationFrame(this.animFrameId);
    this.renderer.dispose();
    if (this.renderer.domElement.parentElement) {
      this.renderer.domElement.parentElement.removeChild(this.renderer.domElement);
    }
  }
}
