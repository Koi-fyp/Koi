const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), nodeCrypto = require('node:crypto'), ts = require('typescript');
// Isolated in-memory transpilation; fake media element and injected transport, no network or audio device.
require.extensions['.ts'] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, fileName: filename }).outputText, filename);
const { parseMouthCues, mouthAt, MOUTH_PRESETS, RHUBARB_TO_VRM } = require('../src/lib/speech/mouthCues.ts');
const { SpeechPlayback } = require('../src/lib/speech/SpeechPlayback.ts');
const { SpeechTurnController } = require('../src/lib/speech/SpeechTurnController.ts');
const { VOICE_ALLOWLIST, voiceFor, companionForVoice, parseGuardedSpeech } = require('../src/lib/speech/voiceGuard.ts');
const { VRMAvatarController } = require('../src/components/avatar/VRMAvatarController.ts');
const { VRMExpressionManager, VRMExpression } = require('@pixiv/three-vrm');
global.window = { location: new URL('http://127.0.0.1:3001/chat') };
const checks = [], test = async (name, fn) => { await fn(); checks.push(name); };
const flush = async () => { for (let i = 0; i < 10; i++) await new Promise(resolve => setImmediate(resolve)); };
const fixtures = ['synthetic-cues-greeting', 'synthetic-cues-all-shapes', 'synthetic-cues-rapid'].map(name => ({ name, ...JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', `${name}.json`), 'utf8')) }));

class FakeAudio extends EventTarget {
  src = ''; currentTime = 0; duration = 4; paused = true; ended = false; seeking = false; listeners = 0; playCalls = 0; failPlay = false;
  addEventListener(...args) { super.addEventListener(...args); this.listeners++; }
  removeEventListener(...args) { super.removeEventListener(...args); this.listeners--; }
  load() {} removeAttribute(name) { if (name === 'src') this.src = ''; }
  pause() { this.paused = true; this.dispatchEvent(new Event('pause')); }
  play() { this.playCalls++; if (this.failPlay) return Promise.reject(new Error('autoplay')); this.paused = false; return Promise.resolve(); }
  end() { this.ended = true; this.paused = true; this.dispatchEvent(new Event('ended')); }
}
const urls = { created: 0, revoked: 0, live: new Set() };
URL.createObjectURL = () => { const url = `blob:test-${++urls.created}`; urls.live.add(url); return url; };
URL.revokeObjectURL = url => { urls.revoked++; urls.live.delete(url); };
const wav = Buffer.from('RIFF$\0\0\0WAVEfmt \x10\0\0\0\x01\0\x01\0"V\0\0D\xac\0\0\x02\0\x10\0data\0\0\0\0', 'latin1');
function response(generationId, voiceId, cues, overrides = {}) {
  const duration = cues.length ? cues[cues.length - 1].end : 1;
  return { generation_id: generationId, voice_id: voiceId, audio_format: 'wav_pcm_s16le_mono', sample_rate: 22050, duration_s: duration,
    audio_b64: wav.toString('base64'), audio_sha256: nodeCrypto.createHash('sha256').update(wav).digest('hex'), mouth_cues: cues, timings_ms: { synthesis: 0, cue_extraction: 0 }, ...overrides };
}
function rig() {
  const manager = new VRMExpressionManager();
  for (const name of ['happy', 'angry', 'sad', 'relaxed', 'neutral', 'blink', ...MOUTH_PRESETS]) manager.registerExpression(new VRMExpression(name));
  return { manager, avatar: new VRMAvatarController({ expressionManager: manager, humanoid: { getNormalizedBoneNode: () => null } }) };
}
const mouth = manager => Object.fromEntries(MOUTH_PRESETS.map(name => [name, manager.getValue(name)]));
const neutral = manager => MOUTH_PRESETS.every(name => manager.getValue(name) === 0);
// Server stand-in: answers with the requested voice unless told otherwise; requests can be held open.
function harness({ cues = parseMouthCues(fixtures[0].mouthCues), voiceOverride, hold = false } = {}) {
  const audio = new FakeAudio(), playback = new SpeechPlayback(() => audio), requests = [];
  const fetchSpeech = (request, signal) => new Promise((resolve, reject) => {
    const entry = { request, signal, resolve: (body = response(request.generation_id, voiceOverride ?? request.voice_id, cues)) => resolve(body), reject };
    requests.push(entry); if (!hold) entry.resolve();
  });
  let id = 0; const turn = new SpeechTurnController({ playback, fetchSpeech, newGenerationId: () => `gen-${++id}` });
  const { manager, avatar } = rig(); avatar.setSpeechSource(turn);
  return { audio, playback, turn, requests, manager, avatar };
}
// Chat-owned state the speech layer may read but must never change.
const done = Object.freeze({ type: 'done', full_text: 'Assalam o alaikum. Main yahan hoon.' });
const chat = Object.freeze({ messages: Object.freeze([Object.freeze({ role: 'assistant', text: done.full_text })]) });
const chatJson = JSON.stringify({ done, chat });

(async () => {
  await test('1a. three cue fixtures drive VRM weights from audio.currentTime: exact mapping, others zero, finite and clamped', async () => {
    for (const fixture of fixtures) {
      const cues = parseMouthCues(fixture.mouthCues), h = harness({ cues });
      await h.turn.speak({ text: done.full_text, companion: 'raza', language: 'ur' }); await flush();
      assert.equal(h.turn.getSnapshot().status, 'speaking', fixture.name);
      for (const cue of cues) {
        h.audio.currentTime = (cue.start + cue.end) / 2; h.avatar.update(1 / 60);
        const preset = RHUBARB_TO_VRM[cue.value], expected = mouthAt({ active: true, time: h.audio.currentTime, cues });
        const weights = mouth(h.manager);
        for (const name of MOUTH_PRESETS) {
          assert(Number.isFinite(weights[name]) && weights[name] >= 0 && weights[name] <= 0.7, `${fixture.name} ${name}`);
          assert.equal(weights[name], name === preset ? expected.weight : 0, `${fixture.name} ${cue.value}@${h.audio.currentTime} ${name}`);
        }
        if (preset && cue.end - cue.start >= 0.08) assert.equal(weights[preset], 0.7);
        assert.equal(h.avatar.getSnapshot().speech.cue, cue.value);
      }
      h.turn.dispose(); h.avatar.dispose();
    }
  });
  await test('1b. media clock, not a speaking flag: speaking state with paused/seeking/stalled audio is neutral; idle state with playing audio moves', async () => {
    const h = harness(); await h.turn.speak({ text: done.full_text, companion: 'raza', language: 'ur' }); await flush();
    h.audio.currentTime = 0.42; // 'D' -> aa
    h.avatar.setConversationState('idle'); h.avatar.update(1 / 60); assert.equal(h.manager.getValue('aa'), 0.7);
    h.avatar.setConversationState('speaking'); h.playback.pause(); h.avatar.update(1 / 60); assert(neutral(h.manager));
    await h.playback.play(); h.avatar.update(1 / 60); assert.equal(h.manager.getValue('aa'), 0.7);
    h.audio.seeking = true; h.avatar.update(1 / 60); assert(neutral(h.manager)); h.audio.seeking = false;
    h.audio.dispatchEvent(new Event('waiting')); h.avatar.update(1 / 60); assert(neutral(h.manager));
    h.audio.dispatchEvent(new Event('playing')); h.avatar.update(1 / 60); assert.equal(h.manager.getValue('aa'), 0.7);
    for (let i = 0; i < 120; i++) h.avatar.update(1 / 60); // 2 s of animation time, media clock unchanged
    assert.equal(h.manager.getValue('aa'), 0.7);
    h.audio.currentTime = 0.63; h.avatar.update(1 / 60); // 'C' -> ee assert.equal(h.manager.getValue('ee'), 0.7); assert.equal(h.manager.getValue('aa'), 0);
    h.turn.dispose(); h.avatar.dispose();
  });
  await test('1c. non-finite and out-of-range media times and deltas stay finite and neutral', async () => {
    const h = harness(); await h.turn.speak({ text: done.full_text, companion: 'raza', language: 'ur' }); await flush();
    for (const time of [NaN, Infinity, -Infinity, -1, 1.5, 1e9]) {
      h.audio.currentTime = time; h.avatar.update(1 / 60);
      assert(neutral(h.manager), String(time)); assert(Object.values(mouth(h.manager)).every(Number.isFinite));
    }
    h.audio.currentTime = 0.42;
    for (const delta of [NaN, Infinity, -1, 0, 1e9]) { h.avatar.update(delta); assert(Object.values(mouth(h.manager)).every(value => Number.isFinite(value) && value >= 0 && value <= 0.7)); }
    h.turn.dispose(); h.avatar.dispose();
  });
  await test('1d. natural end restores a neutral mouth, releases the blob and leaves no cues', async () => {
    const h = harness(); await h.turn.speak({ text: done.full_text, companion: 'raza', language: 'ur' }); await flush();
    h.audio.currentTime = 0.42; h.avatar.update(1 / 60); assert(!neutral(h.manager));
    h.audio.end(); assert.equal(h.turn.getSnapshot().status, 'done'); h.avatar.update(1 / 60);
    assert(neutral(h.manager)); assert.equal(h.turn.getFrame().cues.length, 0); assert.equal(urls.live.size, 0); assert.equal(h.audio.src, '');
    assert.equal(h.avatar.getSnapshot().speech.preset, null);
    h.turn.dispose(); h.avatar.dispose();
  });

  const reasons = {
    stop: h => h.turn.cancel('stop'),
    'new-turn': h => { void h.turn.speak({ text: 'Next reply.', companion: 'raza', language: 'ur' }); },
    'avatar-switch': h => h.turn.setCompanion('aisha'),
    unmount: h => h.turn.dispose(),
    logout: h => h.turn.cancel('logout'),
    'crisis-handoff': h => h.turn.cancel('crisis-handoff'),
    'exercise-stop': h => h.turn.cancel('exercise-stop'),
  };
  await test('2a. stop, new turn, avatar switch, unmount, logout, crisis handoff and urgent exercise stop cancel playing audio and cues', async () => {
    for (const [reason, cancel] of Object.entries(reasons)) {
      const h = harness({ hold: reason === 'new-turn' }); h.turn.setCompanion('raza');
      const speaking = h.turn.speak({ text: done.full_text, companion: 'raza', language: 'ur' });
      if (reason === 'new-turn') h.requests[0].resolve(); await speaking; await flush();
      h.audio.currentTime = 0.42; h.avatar.update(1 / 60); assert.equal(h.manager.getValue('aa'), 0.7, reason);
      const before = h.audio.playCalls; cancel(h); await flush(); h.avatar.update(1 / 60);
      assert(h.audio.paused, reason); assert.equal(h.audio.src, '', reason); assert.equal(urls.live.size, 0, reason);
      assert(neutral(h.manager), reason); assert(!h.turn.getFrame().active, reason); assert.equal(h.turn.getFrame().cues.length, 0, reason);
      assert.equal(h.audio.playCalls, before, reason);
      const snapshot = h.turn.getSnapshot();
      if (reason === 'new-turn') { assert.equal(snapshot.status, 'requesting'); assert.equal(h.requests.length, 2); }
      else { assert.equal(snapshot.status, 'cancelled', reason); assert.equal(snapshot.reason, reason); }
      if (reason === 'unmount') assert.equal(h.audio.listeners, 0);
      assert.equal(JSON.stringify({ done, chat }), chatJson, reason);
      h.turn.dispose(); h.avatar.dispose(); assert.equal(h.audio.listeners, 0, reason);
    }
  });
  await test('2b. every cancel path aborts an in-flight request and a late response never plays', async () => {
    for (const [reason, cancel] of Object.entries(reasons)) {
      const h = harness({ hold: true }); h.turn.setCompanion('raza');
      const speaking = h.turn.speak({ text: done.full_text, companion: 'raza', language: 'ur' }); await flush();
      const first = h.requests[0]; cancel(h); assert(first.signal.aborted, reason);
      first.resolve(); await speaking; await flush(); h.avatar.update(1 / 60);
      assert.equal(h.audio.playCalls, 0, reason); assert.equal(h.audio.src, '', reason); assert.equal(urls.live.size, 0, reason); assert(neutral(h.manager), reason);
      assert.equal(JSON.stringify({ done, chat }), chatJson, reason);
      h.turn.dispose(); h.avatar.dispose();
    }
  });
  await test('2c. after cancellation a new turn plays normally (no leaked generation or listener state)', async () => {
    const h = harness(); h.turn.setCompanion('raza');
    await h.turn.speak({ text: done.full_text, companion: 'raza', language: 'ur' }); await flush(); h.turn.cancel('crisis-handoff');
    await h.turn.speak({ text: 'Again.', companion: 'raza', language: 'ur' }); await flush();
    h.audio.currentTime = 0.42; h.avatar.update(1 / 60); assert.equal(h.manager.getValue('aa'), 0.7); assert.equal(urls.live.size, 1);
    h.turn.dispose(); h.avatar.dispose(); assert.equal(urls.live.size, 0);
  });

  await test('3a. fixed allowlist: aisha -> female voices only, raza -> male voices only, nothing else has a voice', async () => {
    assert.deepEqual(VOICE_ALLOWLIST, { aisha: { ur: 'ur_PK-aegis_female-medium', en: 'en_US-hfc_female-medium' }, raza: { ur: 'ur_PK-fasih-medium', en: 'en_US-hfc_male-medium' } });
    assert(Object.isFrozen(VOICE_ALLOWLIST) && Object.isFrozen(VOICE_ALLOWLIST.aisha) && Object.isFrozen(VOICE_ALLOWLIST.raza));
    for (const language of ['ur', 'en']) { assert.match(voiceFor('aisha', language), /female/); assert.doesNotMatch(voiceFor('raza', language), /female/); }
    for (const voice of Object.values(VOICE_ALLOWLIST.aisha)) assert.equal(companionForVoice(voice), 'aisha');
    for (const voice of Object.values(VOICE_ALLOWLIST.raza)) assert.equal(companionForVoice(voice), 'raza');
    for (const [companion, language] of [['koi', 'ur'], ['fox', 'en'], [undefined, 'ur'], ['aisha', 'ur-en'], ['raza', undefined], ['__proto__', 'ur'], ['constructor', 'en']]) assert.throws(() => voiceFor(companion, language), { code: 'voice-not-allowed' });
    assert.equal(companionForVoice('https://evil.invalid/voice.onnx'), null);
  });
  await test('3b. response guard rejects other-voice, unknown voice, missing, stale/expired, remote-URL and tampered responses', async () => {
    const cues = parseMouthCues(fixtures[0].mouthCues), expect = { companion: 'raza', language: 'ur', generationId: 'gen-9' };
    const good = response('gen-9', 'ur_PK-fasih-medium', cues);
    assert.equal((await parseGuardedSpeech(good, expect)).voiceId, 'ur_PK-fasih-medium');
    const cases = [
      ['voice-mismatch', { ...good, voice_id: 'ur_PK-aegis_female-medium' }], ['voice-mismatch', { ...good, voice_id: 'en_US-hfc_male-medium' }],
      ['voice-mismatch', { ...good, voice_id: 'https://evil.invalid/x.wav' }], ['voice-mismatch', { ...good, voice_id: undefined }],
      ['invalid', null], ['invalid', undefined], ['invalid', 'audio'],
      ['stale', { ...good, generation_id: 'gen-8' }], ['stale', { ...good, generation_id: undefined }],
      ['invalid', { ...good, audio_url: 'https://cdn.invalid/a.wav', audio_url_expires_s: 60 }], ['invalid', { ...good, audio_b64: undefined, audio_url: '/a.wav' }],
      ['invalid', { ...good, audio_sha256: 'f'.repeat(64) }], ['invalid', { ...good, duration_s: NaN }], ['invalid', { ...good, mouth_cues: [{ start: 0, end: Infinity, value: 'D' }] }],
      ['invalid', { ...good, duration_s: 0.5 }],
    ];
    for (const [code, body] of cases) await assert.rejects(parseGuardedSpeech(body, expect), { code }, JSON.stringify(body)?.slice(0, 80));
    await assert.rejects(parseGuardedSpeech({ ...good, voice_id: 'ur_PK-aegis_female-medium' }, { ...expect, companion: 'aisha', language: 'en' }), { code: 'voice-mismatch' });
  });
  await test('3c. through the controller a wrong, missing or expired response never loads or plays in any voice', async () => {
    const variants = {
      'other voice': h => h.requests[0].resolve(response(h.requests[0].request.generation_id, 'ur_PK-aegis_female-medium', parseMouthCues(fixtures[0].mouthCues))),
      missing: h => h.requests[0].resolve(null),
      expired: h => h.requests[0].resolve(response('gen-0', h.requests[0].request.voice_id, parseMouthCues(fixtures[0].mouthCues))),
      'remote url': h => h.requests[0].resolve({ ...response(h.requests[0].request.generation_id, h.requests[0].request.voice_id, parseMouthCues(fixtures[0].mouthCues)), audio_url: 'https://cdn.invalid/a.wav' }),
      'transport error': h => h.requests[0].reject(new Error('503')),
    };
    for (const [name, answer] of Object.entries(variants)) {
      const h = harness({ hold: true }); h.turn.setCompanion('raza');
      const speaking = h.turn.speak({ text: done.full_text, companion: 'raza', language: 'ur' }); await flush();
      assert.equal(h.requests[0].request.voice_id, 'ur_PK-fasih-medium');
      const created = urls.created; answer(h); await speaking; await flush(); h.avatar.update(1 / 60);
      assert.equal(h.turn.getSnapshot().status, 'failed', name); assert.equal(h.audio.playCalls, 0, name); assert.equal(urls.created, created, name); assert.equal(h.audio.src, '', name); assert(neutral(h.manager), name);
      h.turn.dispose(); h.avatar.dispose();
    }
    const h = harness(); h.turn.setCompanion('aisha');
    await h.turn.speak({ text: done.full_text, companion: 'raza', language: 'ur' }); await flush();
    assert.equal(h.requests.length, 0); assert.equal(h.turn.getSnapshot().status, 'failed');
    await h.turn.speak({ text: done.full_text, companion: 'koi', language: 'ur' }); await flush(); assert.equal(h.requests.length, 0);
    await h.turn.speak({ text: done.full_text, companion: 'aisha', language: 'en' }); await flush();
    assert.equal(h.requests[0].request.voice_id, 'en_US-hfc_female-medium'); assert.equal(h.turn.getSnapshot().status, 'speaking');
    h.turn.dispose(); h.avatar.dispose();
  });
  await test('4. speech failure is honest and retryable; done.full_text and chat state are untouched', async () => {
    const h = harness({ hold: true }); h.turn.setCompanion('raza');
    const speaking = h.turn.speak({ text: done.full_text, companion: 'raza', language: 'ur' }); await flush(); h.requests[0].reject(new Error('timeout')); await speaking;
    const failed = h.turn.getSnapshot(); assert.equal(failed.status, 'failed'); assert(failed.canRetry); assert.match(failed.error, /text above is complete/);
    assert.equal(JSON.stringify({ done, chat }), chatJson);
    const retried = h.turn.retry(); await flush(); assert.equal(h.requests[1].request.text, done.full_text); assert.notEqual(h.requests[1].request.generation_id, h.requests[0].request.generation_id);
    h.requests[1].resolve(); await retried; await flush(); assert.equal(h.turn.getSnapshot().status, 'speaking');
    h.audio.failPlay = true; h.turn.cancel('stop'); await h.turn.retry(); assert.equal(h.turn.getSnapshot().status, 'cancelled'); // retry only from failed
    const blocked = h.turn.speak({ text: done.full_text, companion: 'raza', language: 'ur' }); await flush(); h.requests[2].resolve(); await blocked; await flush();
    assert.equal(h.turn.getSnapshot().status, 'failed'); assert.equal(urls.live.size, 0); h.avatar.update(1 / 60); assert(neutral(h.manager));
    assert.equal(JSON.stringify({ done, chat }), chatJson);
    h.turn.dispose(); h.avatar.dispose();
  });
  await test('5. speech modules own no animation loop, timers or canvases; one rAF site in the avatar renderer', async () => {
    const strip = source => source.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, '');
    for (const file of fs.readdirSync(path.join(__dirname, '../src/lib/speech')).filter(name => name.endsWith('.ts'))) {
      const source = strip(fs.readFileSync(path.join(__dirname, '../src/lib/speech', file), 'utf8'));
      assert.doesNotMatch(source, /requestAnimationFrame|setInterval|createElement\(['"]canvas|WebGLRenderer/, file);
      // Mouth timing comes from the media clock; MicrophoneCapture's recording cap is the only timer.
      if (file !== 'MicrophoneCapture.ts') assert.doesNotMatch(source, /setTimeout/, file);
    }
    const sites = [];
    for (const file of fs.readdirSync(path.join(__dirname, '../src/components/avatar')).filter(name => /\.tsx?$/.test(name))) {
      const count = (strip(fs.readFileSync(path.join(__dirname, '../src/components/avatar', file), 'utf8')).match(/requestAnimationFrame\(/g) || []).length;
      if (count) sites.push([file, count]);
    }
    // Legacy 2D AvatarRenderer/AvatarAnimator keep their own loop but must stay unreachable.
    assert.deepEqual(sites, [['AvatarAnimator.ts', 1], ['VRMAvatarRenderer.tsx', 1]]);
    const importers = [];
    const walk = dir => { for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) { if (entry.name !== 'node_modules' && entry.name !== '.next') walk(full); }
      else if (/\.tsx?$/.test(entry.name) && !/[\\/]avatar[\\/](AvatarRenderer\.tsx|AvatarAnimator\.ts)$/.test(full) && /from ['"][^'"]*\/(AvatarRenderer|AvatarAnimator)['"]/.test(fs.readFileSync(full, 'utf8'))) importers.push(full);
    } };
    for (const dir of ['../src', '../dev']) walk(path.join(__dirname, dir));
    assert.deepEqual(importers, []);
  });
  console.log(JSON.stringify({ passed: true, count: checks.length, checks, scope: 'synthetic Rhubarb-shaped cue fixtures, fake media clock, injected transport; real audio and browser rendering not exercised' }, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
