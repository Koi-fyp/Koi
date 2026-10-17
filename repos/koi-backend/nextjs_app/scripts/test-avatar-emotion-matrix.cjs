const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const THREE = require('three');
const { VRMExpressionManager, VRMExpression } = require('@pixiv/three-vrm');
// Isolated in-memory transpilation; no Jest/Firebase bootstrap, no WebGL and no emitted artifacts.
require.extensions['.ts'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, fileName: filename,
  }).outputText;
  module._compile(output, filename);
};
const { VRMAvatarController, EMOTION_PRESETS, MAX_EMOTION_WEIGHT } = require('../src/components/avatar/VRMAvatarController.ts');
const { AvatarCommandBridge } = require('../src/components/avatar/avatarCommandBridge.ts');

const root = path.resolve(__dirname, '..');
const EMOTIONS = ['neutral', 'joy', 'angry', 'sorrow', 'fun'];
const INTENSITIES = [0, 0.3, 0.7, 1.0];
const PRESETS = Object.values(EMOTION_PRESETS);
const VOWELS = ['aa', 'ih', 'ou', 'ee', 'oh'];
const EPSILON = 1e-12;
const checks = [];
function test(name, fn) { fn(); checks.push(name); }

// Reads only the 12-byte GLB header, the 8-byte chunk header and the JSON chunk; binary buffers are never loaded.
function readPresetNames(file) {
  const fd = fs.openSync(path.join(root, file), 'r');
  try {
    const header = Buffer.alloc(20);
    assert.equal(fs.readSync(fd, header, 0, 20, 0), 20, `${file}: truncated GLB header`);
    assert.equal(header.readUInt32LE(0), 0x46546c67, `${file}: not binary glTF`);
    assert.equal(header.readUInt32LE(4), 2, `${file}: unsupported glTF version`);
    assert.equal(header.readUInt32LE(16), 0x4e4f534a, `${file}: first chunk is not JSON`);
    const length = header.readUInt32LE(12);
    assert(length > 0 && length + 20 <= header.readUInt32LE(8), `${file}: invalid JSON chunk length`);
    const json = Buffer.alloc(length);
    assert.equal(fs.readSync(fd, json, 0, length, 20), length, `${file}: truncated JSON chunk`);
    const expressions = JSON.parse(json.toString('utf8')).extensions?.VRMC_vrm?.expressions;
    assert(expressions?.preset, `${file}: missing VRMC_vrm expression presets`);
    return Object.keys(expressions.preset);
  } finally { fs.closeSync(fd); }
}
const MODELS = {
  male: readPresetNames('public/models/koi-male.vrm'),
  female: readPresetNames('public/models/koi-female.vrm'),
};

function rig(names) {
  const manager = new VRMExpressionManager();
  for (const name of names) manager.registerExpression(new VRMExpression(name));
  const head = new THREE.Object3D(), chest = new THREE.Object3D();
  const humanoid = { getNormalizedBoneNode: (name) => name === 'head' ? head : name === 'chest' ? chest : null };
  const controller = new VRMAvatarController({ expressionManager: manager, humanoid }, { seed: 7 });
  for (const vowel of VOWELS) if (manager.getExpression(vowel)) manager.setValue(vowel, 0.25);
  return { manager, controller };
}
function step(controller, seconds, rate = 120) { for (let index = 0; index < Math.round(seconds * rate); index++) controller.update(1 / rate); }
const SPEC_MAX_WEIGHT = 0.65; // Pinned literal so a changed controller constant fails here.
const expected = (emotion, intensity) => emotion === 'neutral' ? 0 : intensity * SPEC_MAX_WEIGHT;
function weights(manager) { return Object.fromEntries(PRESETS.map((preset) => [preset, manager.getValue(preset) ?? 0])); }
function invariant(manager, label) {
  const values = Object.values(weights(manager));
  assert(values.filter((value) => value > 0).length <= 1, `${label}: more than one emotional preset is nonzero`);
  assert(values.every((value) => value >= 0 && value <= MAX_EMOTION_WEIGHT + EPSILON), `${label}: weight out of range`);
  if (manager.getExpression('neutral')) assert.equal(manager.getValue('neutral'), 0, `${label}: neutral morph forced`);
}
function settledAt(manager, emotion, intensity, label) {
  const preset = EMOTION_PRESETS[emotion];
  for (const [name, value] of Object.entries(weights(manager))) {
    const target = name === preset ? expected(emotion, intensity) : 0;
    assert(Math.abs(value - target) <= EPSILON, `${label}: ${name}=${value}, expected ${target}`);
  }
  invariant(manager, label);
}
function vowelsUntouched(manager, label) {
  for (const vowel of VOWELS) if (manager.getExpression(vowel)) assert.equal(manager.getValue(vowel), 0.25, `${label}: ${vowel} changed`);
}
function seeded(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) >>> 0;
    let value = seed;
    value = Math.imul(value ^ value >>> 15, value | 1);
    value ^= value + Math.imul(value ^ value >>> 7, value | 61);
    return ((value ^ value >>> 14) >>> 0) / 4294967296;
  };
}

test('both real VRM files expose neutral, every mapped emotion preset, blink and vowels', () => {
  for (const [model, names] of Object.entries(MODELS)) {
    for (const name of ['neutral', ...PRESETS, 'blink', ...VOWELS]) assert(names.includes(name), `${model} lacks ${name}`);
  }
  assert.deepEqual([...MODELS.male].sort(), [...MODELS.female].sort());
  assert.equal(MAX_EMOTION_WEIGHT, SPEC_MAX_WEIGHT);
  assert.deepEqual(EMOTION_PRESETS, { joy: 'happy', angry: 'angry', sorrow: 'sad', fun: 'relaxed' });
});

test('5 emotions x {0, 0.3, 0.7, 1.0} settle to intensity x 0.65 on both real preset sets (fresh rig per cell)', () => {
  for (const [model, names] of Object.entries(MODELS)) {
    for (const emotion of EMOTIONS) {
      for (const intensity of INTENSITIES) {
        const label = `${model}/${emotion}/${intensity}`;
        const { manager, controller } = rig(names);
        assert.equal(controller.setEmotion(emotion, intensity), true, `${label}: reported unsupported`);
        step(controller, 0.38); // One full fade-in; settled exactly when the fade completes.
        settledAt(manager, emotion, intensity, label);
        const snapshot = controller.getSnapshot();
        assert.equal(snapshot.emotion, emotion, label);
        assert.equal(snapshot.intensity, emotion === 'neutral' ? 0 : intensity, label);
        assert.deepEqual(snapshot.availableEmotions, EMOTIONS, label);
        step(controller, 2); settledAt(manager, emotion, intensity, `${label} (held)`);
        vowelsUntouched(manager, label);
      }
    }
  }
});

test('chained matrix: every cell reached from the previous cell settles within 0.60 s and recovers to neutral within 0.22 s', () => {
  for (const [model, names] of Object.entries(MODELS)) {
    const { manager, controller } = rig(names);
    for (const emotion of EMOTIONS) {
      for (const intensity of INTENSITIES) {
        const label = `${model} chained ${emotion}/${intensity}`;
        controller.setEmotion(emotion, intensity);
        for (let index = 0; index < 73; index++) { controller.update(1 / 120); invariant(manager, label); } // 0.608 s
        settledAt(manager, emotion, intensity, label);
      }
    }
    for (const emotion of EMOTIONS.slice(1)) {
      controller.setEmotion(emotion, 1); step(controller, 0.61); settledAt(manager, emotion, 1, `${model} ${emotion} before recovery`);
      controller.setEmotion('neutral', 0.9); step(controller, 0.23);
      settledAt(manager, 'neutral', 0, `${model} ${emotion} -> neutral`);
      controller.setEmotion(emotion, 1); step(controller, 0.38);
      controller.setEmotion(emotion, 0); step(controller, 0.23);
      settledAt(manager, emotion, 0, `${model} ${emotion} -> intensity 0`);
    }
    vowelsUntouched(manager, `${model} chained`);
  }
});

test('emotion-to-emotion transition is exclusive and not settled early (fade out 0.22 s, fade in 0.38 s)', () => {
  const { manager, controller } = rig(MODELS.male);
  controller.setEmotion('joy', 1); step(controller, 0.38);
  controller.setEmotion('angry', 1);
  step(controller, 0.55);
  assert.equal(manager.getValue('happy'), 0);
  assert(manager.getValue('angry') > 0 && manager.getValue('angry') < 0.65 - 1e-6, 'angry settled before 0.60 s');
  step(controller, 0.06); settledAt(manager, 'angry', 1, 'joy -> angry');
});

test('rapid A -> B -> A reversal mid-fade returns without dropping to zero or leaking B', () => {
  for (const [model, names] of Object.entries(MODELS)) {
    const { manager, controller } = rig(names);
    controller.setEmotion('joy', 1); step(controller, 0.38);
    controller.setEmotion('angry', 1);
    let minimum = Infinity;
    for (let index = 0; index < 12; index++) { controller.update(1 / 120); invariant(manager, model); minimum = Math.min(minimum, manager.getValue('happy')); }
    assert.equal(manager.getValue('angry'), 0, `${model}: B leaked during leave fade`);
    controller.setEmotion('joy', 1);
    let previous = manager.getValue('happy');
    for (let index = 0; index < 46; index++) {
      controller.update(1 / 120); invariant(manager, model);
      assert(manager.getValue('happy') >= previous - EPSILON, `${model}: reversal not monotonic`); previous = manager.getValue('happy');
      minimum = Math.min(minimum, previous);
    }
    assert(minimum > 0.3, `${model}: reversal dipped to ${minimum}`);
    assert.equal(manager.getValue('angry'), 0);
    settledAt(manager, 'joy', 1, `${model} reversal`);
  }
});

test('same-emotion ramps move monotonically between levels without passing through zero', () => {
  for (const [model, names] of Object.entries(MODELS)) {
    for (const emotion of EMOTIONS.slice(1)) {
      const { manager, controller } = rig(names);
      const preset = EMOTION_PRESETS[emotion];
      controller.setEmotion(emotion, 0.3); step(controller, 0.38); settledAt(manager, emotion, 0.3, `${model}/${emotion} ramp start`);
      for (const [from, to] of [[0.3, 0.7], [0.7, 1.0], [1.0, 0.3], [0.3, 1.0], [1.0, 0.7]]) {
        const label = `${model}/${emotion} ramp ${from} -> ${to}`;
        controller.setEmotion(emotion, to);
        let previous = manager.getValue(preset);
        for (let index = 0; index < 46; index++) {
          controller.update(1 / 120); invariant(manager, label);
          const value = manager.getValue(preset);
          assert(to > from ? value >= previous - EPSILON : value <= previous + EPSILON, `${label}: not monotonic`);
          assert(value >= Math.min(from, to) * MAX_EMOTION_WEIGHT - EPSILON, `${label}: dipped below the lower level`);
          previous = value;
        }
        settledAt(manager, emotion, to, label);
      }
    }
  }
});

test('seeded 200-command sequence keeps invariants, is deterministic and settles to the last command', () => {
  const run = (names, seed) => {
    const random = seeded(seed);
    const { manager, controller } = rig(names);
    const trace = [];
    let last;
    for (let index = 0; index < 200; index++) {
      const emotion = EMOTIONS[Math.floor(random() * EMOTIONS.length)];
      const intensity = random() < 0.5 ? INTENSITIES[Math.floor(random() * INTENSITIES.length)] : random();
      controller.setEmotion(emotion, intensity); last = { emotion, intensity };
      const frames = Math.floor(random() * 6); // 0-5 frames between commands, including same-frame bursts.
      for (let frame = 0; frame < frames; frame++) { controller.update(1 / 120); invariant(manager, `seed ${seed} command ${index}`); }
      trace.push(JSON.stringify(weights(manager)));
    }
    step(controller, 0.61);
    settledAt(manager, last.emotion, last.intensity, `seed ${seed} final ${last.emotion}/${last.intensity}`);
    vowelsUntouched(manager, `seed ${seed}`);
    return trace;
  };
  for (const names of Object.values(MODELS)) {
    for (const seed of [1, 0x4b4f49, 20261018]) assert.deepEqual(run(names, seed), run(names, seed));
  }
});

test('missing-expression rigs report unsupported, fall back to neutral and keep other emotions working', () => {
  for (const [emotion, preset] of Object.entries(EMOTION_PRESETS)) {
    const { manager, controller } = rig(MODELS.female.filter((name) => name !== preset));
    assert.equal(controller.setEmotion(emotion, 1), false, `${emotion} without ${preset}`);
    assert.equal(controller.getSnapshot().emotion, 'neutral');
    assert.equal(controller.getSnapshot().intensity, 0);
    assert(!controller.getSnapshot().availableEmotions.includes(emotion));
    step(controller, 0.38); settledAt(manager, 'neutral', 0, `${emotion} missing`);
    const other = Object.keys(EMOTION_PRESETS).find((name) => name !== emotion);
    assert.equal(controller.setEmotion(other, 0.7), true);
    step(controller, 0.38); settledAt(manager, other, 0.7, `${other} with ${preset} missing`);
    assert.equal(controller.setEmotion(emotion, 0.7), false);
    step(controller, 0.23); settledAt(manager, 'neutral', 0, `${other} -> missing ${emotion} fades out`);
  }
});

test('null and absent expressionManager are inert: no throw, zero weights, only neutral supported', () => {
  for (const expressionManager of [null, undefined]) {
    const controller = new VRMAvatarController({ expressionManager, humanoid: { getNormalizedBoneNode: () => null } });
    for (const emotion of EMOTIONS) {
      for (const intensity of INTENSITIES) {
        assert.equal(controller.setEmotion(emotion, intensity), emotion === 'neutral');
        step(controller, 0.1);
        const snapshot = controller.getSnapshot();
        assert.equal(snapshot.emotion, 'neutral');
        assert(Object.values(snapshot.weights).every((value) => value === 0));
      }
    }
    assert.deepEqual(controller.getSnapshot().availableEmotions, ['neutral']);
    controller.reset(); controller.dispose(); controller.dispose();
  }
});

test('bridge pre-bind setEmotion returns true (queued), normalizes, and the bound rig decides support', () => {
  const full = rig(MODELS.male);
  const bridge = new AvatarCommandBridge();
  assert.equal(bridge.setEmotion('joy', 0.7), true);
  bridge.bind(full.controller, '/models/koi-male.vrm'); bridge.markReady(full.controller);
  step(full.controller, 0.38); settledAt(full.manager, 'joy', 0.7, 'queued joy 0.7');
  bridge.detach(full.controller); full.controller.dispose();

  const lacking = rig(MODELS.female.filter((name) => name !== 'sad'));
  assert.equal(bridge.setEmotion('sorrow', 0.7), true, 'pre-bind returns true even though the next rig lacks sad');
  bridge.bind(lacking.controller, '/models/koi-female.vrm'); bridge.markReady(lacking.controller);
  assert.equal(bridge.getSnapshot().animation.emotion, 'neutral');
  step(lacking.controller, 0.38); settledAt(lacking.manager, 'neutral', 0, 'queued sorrow on rig without sad');
  assert.equal(bridge.setEmotion('sorrow', 1), false, 'bound rig reports unsupported');
  assert.equal(bridge.setEmotion('fun', 1), true);
  bridge.detach(lacking.controller); lacking.controller.dispose();

  const normalized = rig(MODELS.male);
  assert.equal(bridge.setEmotion('unknown', 5), true);
  bridge.bind(normalized.controller, '/models/koi-male.vrm');
  step(normalized.controller, 0.38); settledAt(normalized.manager, 'neutral', 0, 'unknown pre-bind');
  assert.equal(bridge.setEmotion('angry', 5), true);
  step(normalized.controller, 0.61); settledAt(normalized.manager, 'angry', 1, 'clamped bound command');
  bridge.dispose(); normalized.controller.dispose();
  assert.equal(bridge.setEmotion('joy', 1), false, 'disposed bridge rejects commands');
});

console.log(JSON.stringify({ passed: true, models: Object.fromEntries(Object.entries(MODELS).map(([model, names]) => [model, names])), checks,
  scope: 'deterministic controller/bridge fixtures using real VRM preset names; no WebGL, no rendered pixels, no network' }, null, 2));
