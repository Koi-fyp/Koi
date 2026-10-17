const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require('typescript');
const THREE = require('three');
const { VRMExpressionManager, VRMExpression } = require('@pixiv/three-vrm');
require.extensions['.ts'] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, fileName: filename,
}).outputText, filename);
const { ConversationSession } = require('../src/lib/conversation/ConversationSession.ts');
const { parseChatResponse } = require('../src/lib/conversation/chatContract.ts');
const { VRMAvatarController } = require('../src/components/avatar/VRMAvatarController.ts');
const { AvatarCommandBridge } = require('../src/components/avatar/avatarCommandBridge.ts');

(async () => {
  const expressions = new VRMExpressionManager();
  for (const name of ['happy', 'angry', 'sad', 'relaxed']) expressions.registerExpression(new VRMExpression(name));
  const controller = new VRMAvatarController({ expressionManager: expressions, humanoid: { getNormalizedBoneNode: () => new THREE.Object3D() } });
  const bridge = new AvatarCommandBridge(); bridge.bind(controller, 'fixture'); bridge.markReady(controller);
  let emit, resolve, reject;
  const session = new ConversationSession({ send: (_request, options) => {
    emit = options.onEvent;
    return new Promise((ok, fail) => {
      resolve = ok; reject = fail;
      options.signal.addEventListener('abort', () => fail(new Error('Synthetic cancellation')), { once: true });
    });
  } }, 'avatar-session-fixture');
  const release = session.subscribe(() => {
    const snapshot = session.getSnapshot();
    bridge.setEmotion(snapshot.companion.emotion, snapshot.companion.intensity);
    bridge.setConversationState(snapshot.conversationState);
  });
  const settle = () => { for (let i = 0; i < 100; i++) controller.update(0.01); };
  const weights = () => bridge.getSnapshot().animation.weights;
  let sending = session.send('Synthetic local test');
  for (const [emotion, preset] of Object.entries({ joy: 'happy', angry: 'angry', sorrow: 'sad', fun: 'relaxed' })) {
    emit({ event: 'companion_state', data: { emotion, intensity: 0.6 } });
    assert(session.getSnapshot().pending); settle();
    assert(Math.abs(weights()[preset] - 0.39) < 1e-10);
    assert(Object.values(weights()).filter(w => w > 0).length === 1);
  }
  for (let i = 0; i < 100; i++) emit({ event: 'companion_state', data: { emotion: ['joy', 'sorrow', 'angry', 'fun'][i % 4], intensity: (i % 11) / 10 } });
  settle(); assert.equal(bridge.getSnapshot().animation.emotion, 'fun');
  session.cancel(); await sending; settle();
  assert(Object.values(weights()).every(w => w === 0));
  emit({ event: 'companion_state', data: { emotion: 'joy', intensity: 1 } }); settle();
  assert(Object.values(weights()).every(w => w === 0)); // Stale event cannot revive a cancelled reply.
  sending = session.send('Missing presentation metadata fixture');
  resolve(parseChatResponse({ reply: 'Synthetic reply', latency_ms: 1 })); await sending; settle();
  assert.equal(bridge.getSnapshot().animation.emotion, 'neutral');
  assert(Object.values(weights()).every(w => w === 0));
  sending = session.send('Failure fixture');
  emit({ event: 'companion_state', data: { emotion: 'joy', intensity: 1 } }); settle();
  reject(new Error('Synthetic failure')); await sending; settle();
  assert.equal(bridge.getSnapshot().animation.emotion, 'neutral');
  release(); session.dispose(); bridge.dispose(); controller.dispose();
  console.log(JSON.stringify({ passed: true, checks: ['pre-completion session metadata drives controller weights', 'all four mappings and intensities', 'latest of 100 rapid updates wins', 'cancellation neutralizes and rejects stale events', 'missing metadata and failed request return neutral', 'disposal'], scope: 'deterministic local session/controller fixtures; no network, no rendered model, no live Modal evidence' }, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
