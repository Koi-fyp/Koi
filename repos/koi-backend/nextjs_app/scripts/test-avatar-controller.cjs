const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const THREE = require('three');
const { VRMExpressionManager, VRMExpression } = require('@pixiv/three-vrm');
// Isolated in-memory transpilation; no Jest/Firebase bootstrap and no emitted artifacts.
require.extensions['.ts'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, fileName: filename,
  }).outputText;
  module._compile(output, filename);
};
const { VRMAvatarController, MAX_EMOTION_WEIGHT } = require('../src/components/avatar/VRMAvatarController.ts');
const { AvatarCommandBridge, registerAvatarCommands } = require('../src/components/avatar/avatarCommandBridge.ts');
const checks = [];
function test(name, fn) { fn(); checks.push(name); }
function fixture(options = {}) {
  const manager = new VRMExpressionManager();
  for (const name of ['neutral', 'happy', 'angry', 'sad', 'relaxed', 'blink', 'blinkLeft', 'blinkRight', 'aa', 'ih', 'ou', 'ee', 'oh']) manager.registerExpression(new VRMExpression(name));
  const head = new THREE.Object3D(), chest = new THREE.Object3D();
  head.quaternion.setFromEuler(new THREE.Euler(0.04, -0.02, 0.01)); head.position.set(0.1, 0.3, 0.02); chest.position.y = 0.45;
  const base = { head: head.quaternion.clone(), headPosition: head.position.clone(), chest: chest.position.clone() };
  const controller = new VRMAvatarController({ expressionManager: manager, humanoid: { getNormalizedBoneNode: (name) => name === 'head' ? head : name === 'chest' ? chest : null } }, options);
  return { controller, manager, head, chest, base };
}
function step(controller, seconds, rate = 120) { for (let index = 0; index < Math.round(seconds * rate); index++) controller.update(1 / rate); }
function safe(controller) {
  const weights = Object.values(controller.getSnapshot().weights);
  assert(weights.filter((weight) => weight > 1e-8).length <= 1);
  assert(weights.every((weight) => weight >= 0 && weight <= MAX_EMOTION_WEIGHT + 1e-10));
}

test('all mappings, clamp, zero intensity and resting neutral', () => {
  const { controller, manager } = fixture();
  for (const [emotion, preset] of [['joy', 'happy'], ['angry', 'angry'], ['sorrow', 'sad'], ['fun', 'relaxed']]) {
    controller.setEmotion(emotion, 100); step(controller, 1); assert.equal(manager.getValue(preset), 0.65); safe(controller);
    controller.setEmotion(emotion, 0); step(controller, 1); assert(Object.values(controller.getSnapshot().weights).every((weight) => weight === 0));
  }
  controller.setEmotion('unexpected', NaN); step(controller, 1); assert.equal(controller.getSnapshot().emotion, 'neutral');
  controller.setEmotion('joy', -1); assert.equal(controller.getSnapshot().intensity, 0);
  controller.setEmotion('joy', Infinity); assert.equal(controller.getSnapshot().intensity, 0);
  assert.equal(manager.getValue('neutral'), 0);
});
test('continuous exclusive transitions and rapid/repeated commands', () => {
  const { controller, manager } = fixture(); controller.setEmotion('joy', 1); step(controller, 1);
  controller.setEmotion('angry', 1); assert.equal(manager.getValue('happy'), 0.65);
  controller.update(0.01); assert(manager.getValue('happy') > 0 && manager.getValue('happy') < 0.65); assert.equal(manager.getValue('angry'), 0);
  for (let index = 0; index < 300; index++) { controller.setEmotion(['joy', 'sorrow', 'fun', 'angry'][index % 4], index % 11 / 10); controller.update(0.01); safe(controller); }
  controller.setEmotion('joy', 0.7);
  for (let index = 0; index < 120; index++) { controller.setEmotion('joy', 0.7); controller.update(1 / 120); safe(controller); }
  assert(Math.abs(manager.getValue('happy') - 0.455) < 1e-12);
  controller.reset(); controller.update(0.01); assert(manager.getValue('happy') > 0); step(controller, 1); assert.equal(manager.getValue('happy'), 0);
});
test('frame-rate independent expression transition', () => {
  const a = fixture(), b = fixture(); a.controller.setEmotion('joy', 0.8); b.controller.setEmotion('joy', 0.8);
  step(a.controller, 0.2, 30); step(b.controller, 0.2, 120);
  assert(Math.abs(a.manager.getValue('happy') - b.manager.getValue('happy')) < 1e-10);
});
test('seeded variable blinks coexist with emotion and leave all mouth values untouched', () => {
  const a = fixture({ seed: 42 }), b = fixture({ seed: 42 });
  for (const name of ['aa', 'ih', 'ou', 'ee', 'oh']) a.manager.setValue(name, 0.3);
  a.controller.setEmotion('joy', 0.8); b.controller.setEmotion('joy', 0.8);
  const times = []; let closed = false;
  for (let index = 0; index < 3600; index++) {
    a.controller.update(1 / 120); b.controller.update(1 / 120);
    const snapshot = a.controller.getSnapshot(); assert.deepEqual({ ...snapshot, mouthWeights: {} }, { ...b.controller.getSnapshot(), mouthWeights: {} });
    if (snapshot.blinkWeight > 0.9 && !closed) times.push(index / 120);
    closed = snapshot.blinkWeight > 0.9;
    if (index > 120) assert.equal(a.manager.getValue('happy'), 0.52);
  }
  assert(times.length >= 4); const gaps = times.slice(1).map((value, index) => value - times[index]);
  assert(gaps.every((gap) => gap > 3)); assert(Math.max(...gaps) - Math.min(...gaps) > 0.1);
  for (const name of ['aa', 'ih', 'ou', 'ee', 'oh']) assert.equal(a.manager.getValue(name), 0.3);
  a.controller.reset(); a.controller.dispose();
  for (const name of ['aa', 'ih', 'ou', 'ee', 'oh']) assert.equal(a.manager.getValue(name), 0.3);
});
test('unsupported presets, paired blink fallback and VRM override ownership', () => {
  const f = fixture(); const sad = f.manager.getExpression('sad'); f.manager.unregisterExpression(sad);
  assert.equal(f.controller.setEmotion('sorrow', 1), false); assert.equal(f.controller.getSnapshot().emotion, 'neutral');
  f.manager.getExpression('happy').overrideBlink = 'blend'; f.manager.getExpression('happy').overrideMouth = 'block';
  f.controller.setEmotion('joy', 0.8); step(f.controller, 1);
  assert.equal(f.manager.getExpression('happy').overrideBlink, 'blend'); assert.equal(f.manager.getExpression('happy').overrideMouth, 'block');
  const manager = new VRMExpressionManager(); for (const name of ['blinkLeft', 'blinkRight']) manager.registerExpression(new VRMExpression(name));
  const controller = new VRMAvatarController({ expressionManager: manager, humanoid: { getNormalizedBoneNode: () => null } });
  let observed = false; for (let index = 0; index < 1000; index++) { controller.update(0.01); if (manager.getValue('blinkLeft') > 0.9) observed = true; assert.equal(manager.getValue('blinkLeft'), manager.getValue('blinkRight')); }
  assert(observed);
  const absent = new VRMAvatarController({ humanoid: { getNormalizedBoneNode: () => null } }); absent.update(0.01); absent.reset(); absent.dispose();
});
test('stable bone bases, subtle states, reduced motion and idempotent disposal', () => {
  const f = fixture(); const poses = [];
  for (const state of ['idle', 'listening', 'thinking', 'speaking']) {
    f.controller.setConversationState(state); step(f.controller, 2); poses.push(f.head.quaternion.toArray());
    assert(f.head.quaternion.angleTo(f.base.head) < 0.06); assert(Math.abs(f.chest.position.y - f.base.chest.y) <= 0.0015 + 1e-10);
  }
  const sameTimePoses = ['idle', 'listening', 'thinking', 'speaking'].map((state) => { const sameTime = fixture(); sameTime.controller.setConversationState(state); step(sameTime.controller, 2); return sameTime.head.quaternion.toArray(); });
  assert(sameTimePoses.every((pose, index) => sameTimePoses.slice(index + 1).every((other) => JSON.stringify(pose) !== JSON.stringify(other))));
  step(f.controller, 1000); assert(f.head.quaternion.angleTo(f.base.head) < 0.06);
  f.controller.setReducedMotion(true); step(f.controller, 1); assert.deepEqual(f.head.quaternion.toArray(), f.base.head.toArray()); assert.deepEqual(f.chest.position, f.base.chest);
  f.controller.setConversationState('invalid'); assert.equal(f.controller.getSnapshot().conversationState, 'idle');
  f.controller.dispose(); f.controller.dispose(); const before = f.controller.getSnapshot(); f.controller.update(1); assert.equal(f.controller.setEmotion('joy', 1), false); f.controller.reset(); assert.deepEqual(f.controller.getSnapshot(), before);
  assert.deepEqual(f.head.position, f.base.headPosition);
});
test('command queue, readiness, safe switching, stale references and global registration', () => {
  const bridge = new AvatarCommandBridge(), a = fixture(), b = fixture();
  bridge.setEmotion('joy', 0.7); bridge.setConversationState('listening'); assert.equal(bridge.ready, false);
  bridge.bind(a.controller, 'male'); bridge.markReady(a.controller); step(a.controller, 1); assert(Math.abs(a.manager.getValue('happy') - 0.455) < 1e-12);
  bridge.detach(a.controller); a.controller.dispose(); bridge.bind(b.controller, 'female'); bridge.markReady(a.controller); bridge.detach(a.controller); assert.equal(bridge.ready, false);
  bridge.markReady(b.controller); step(b.controller, 1); assert(Math.abs(b.manager.getValue('happy') - 0.455) < 1e-12); assert.equal(bridge.getSnapshot().generation, 2);
  const target = new EventTarget(); const events = []; target.addEventListener('AVATAR_READY', (event) => events.push(event.detail));
  const release = registerAvatarCommands(bridge, target); assert.equal(target.AvatarController.ready, true); assert.equal(target.AvatarController.bind, undefined); assert.equal(target.AvatarController.update, undefined); assert(Object.isFrozen(target.AvatarController));
  assert.throws(() => registerAvatarCommands(bridge, target), /already registered/);
  assert.throws(() => registerAvatarCommands(new AvatarCommandBridge(), target), /already registered/);
  bridge.markReady(b.controller); assert.equal(events.length, 1);
  release(); assert.equal(target.AvatarController, undefined); assert.equal(bridge.lifecycle, 'disposed'); assert.equal(bridge.setEmotion('angry', 1), false);
  bridge.markReady(b.controller); assert.equal(bridge.ready, false); assert.throws(() => registerAvatarCommands(bridge, target), /disposed/);
});
console.log(JSON.stringify({ passed: true, checks }, null, 2));
