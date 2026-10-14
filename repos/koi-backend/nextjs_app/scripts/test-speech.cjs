const assert = require('node:assert/strict'), fs = require('node:fs'), ts = require('typescript');
require.extensions['.ts'] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, fileName: filename }).outputText, filename);
const { parseMouthCues, mouthAt, MOUTH_PRESETS } = require('../src/lib/speech/mouthCues.ts');
const { SpeechPlayback } = require('../src/lib/speech/SpeechPlayback.ts');
const { VRMAvatarController } = require('../src/components/avatar/VRMAvatarController.ts');
const { VRMExpressionManager, VRMExpression } = require('@pixiv/three-vrm');
const checks = [], test = (name, fn) => { fn(); checks.push(name); };
const cues = parseMouthCues([{ start: 0, end: 1, value: 'D' }, { start: 1, end: 2, value: 'F' }, { start: 2, end: 3, value: 'A' }, { start: 3, end: 4, value: 'bad' }]);
test('finite ordered second-based cues, unknown/closed values, half-open boundaries and gaps', () => {
  assert.equal(cues[3].value, 'X');
  for (const invalid of [[{ start: -1, end: 1, value: 'D' }], [{ start: 0, end: Infinity, value: 'D' }], [{ start: 0, end: 1, value: 'D' }, { start: .5, end: 2, value: 'E' }], [{}]]) assert.throws(() => parseMouthCues(invalid));
  assert.equal(mouthAt({ active: true, time: .5, cues }).preset, 'aa');
  assert.equal(mouthAt({ active: true, time: 1, cues }).preset, 'ou');
  assert.equal(mouthAt({ active: true, time: 2.5, cues }).weight, 0);
  assert.equal(mouthAt({ active: true, time: NaN, cues }).weight, 0);
});
test('actual source clock controls weight, backward seeks and pause; emotion/blink ownership preserved', () => {
  const manager = new VRMExpressionManager(); for (const name of ['happy', 'angry', 'sad', 'relaxed', 'neutral', 'blink', ...MOUTH_PRESETS]) manager.registerExpression(new VRMExpression(name));
  const avatar = new VRMAvatarController({ expressionManager: manager, humanoid: { getNormalizedBoneNode: () => null } });
  let time = .5, active = true; avatar.setSpeechSource({ getFrame: () => ({ time, active, cues }) });
  for (const emotion of ['neutral', 'joy', 'angry', 'sorrow', 'fun']) {
    avatar.setEmotion(emotion, .7); for (let i = 0; i < 100; i++) avatar.update(.01);
    assert.equal(manager.getValue('aa'), .7); // time unchanged despite one second of avatar updates
    time = 1.5; avatar.update(.01); assert.equal(manager.getValue('ou'), .7); assert.equal(manager.getValue('aa'), 0);
    time = .5; avatar.update(.01); assert.equal(manager.getValue('aa'), .7);
  }
  let blink = false; for (let i = 0; i < 800; i++) { avatar.update(.01); blink ||= manager.getValue('blink') > .5; } assert(blink);
  active = false; avatar.update(.01); assert(MOUTH_PRESETS.every(name => manager.getValue(name) === 0));
  active = true; avatar.update(.01); avatar.setSpeechSource(undefined); assert(MOUTH_PRESETS.every(name => manager.getValue(name) === 0)); avatar.dispose();
});
class FakeAudio extends EventTarget {
  src = ''; currentTime = 0; duration = 4; paused = true; ended = false; seeking = false; listeners = 0; pending = [];
  addEventListener(...args) { super.addEventListener(...args); this.listeners++; }
  removeEventListener(...args) { super.removeEventListener(...args); this.listeners--; }
  load() {} removeAttribute() { this.src = ''; }
  pause() { this.paused = true; this.dispatchEvent(new Event('pause')); }
  play() { this.paused = false; return new Promise((resolve, reject) => this.pending.push({ resolve, reject })); }
}
(async () => {
  global.window = { location: new URL('http://127.0.0.1:3001/speech-lab') };
  const audio = new FakeAudio(), player = new SpeechPlayback(() => audio);
  assert.throws(() => player.load({ audioUrl: 'https://external.invalid/sample.wav', mouthCues: cues }));
  player.load({ audioUrl: '/speech-fixture/speech-sample.wav', mouthCues: cues });
  const old = player.play(); player.stop(); const fresh = player.play(); audio.pending[0].resolve(); await old; assert.equal(player.getSnapshot().state, 'loading');
  audio.pending[1].resolve(); await fresh; audio.currentTime = .5; assert(player.getFrame().active);
  player.pause(); assert(!player.getFrame().active); assert.equal(audio.currentTime, .5);
  const resumed = player.play(); audio.pending[2].resolve(); await resumed; assert(player.getFrame().active);
  player.seek(2); assert.equal(player.getFrame().time, 2);
  audio.ended = true; audio.dispatchEvent(new Event('ended')); assert.equal(player.getSnapshot().state, 'ended'); assert(!player.getFrame().active);
  audio.ended = false; const rejected = player.play(); audio.pending[3].reject(new Error('autoplay')); await rejected; assert.equal(player.getSnapshot().state, 'error');
  const listeners = audio.listeners; assert(listeners > 0); player.dispose(); assert.equal(audio.listeners, 0); assert.equal(audio.src, ''); assert.equal(player.getSnapshot().state, 'disposed'); assert(!player.getFrame().active); player.dispose(); await player.play();
  checks.push('single audio lifecycle, explicit play, pause/resume/seek/end/failure, rapid stale promises, same-origin guard and disposal');
  console.log(JSON.stringify({ passed: true, checks, scope: 'pure/controller and fake-media lifecycle tests; real audio checked separately' }, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
