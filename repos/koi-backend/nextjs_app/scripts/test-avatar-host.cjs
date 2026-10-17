const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const THREE = require('three');
const { VRMExpressionManager, VRMExpression } = require('@pixiv/three-vrm');

// TypeScript modules are transpiled in memory; this test writes no artifacts.
require.extensions['.ts'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, fileName: filename,
  }).outputText;
  module._compile(output, filename);
};

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const { VRMAvatarController } = require('../src/components/avatar/VRMAvatarController.ts');
const { AvatarCommandBridge, registerAvatarCommands } = require('../src/components/avatar/avatarCommandBridge.ts');
const checks = [];
function test(name, run) { run(); checks.push(name); }
function controller() {
  const manager = new VRMExpressionManager();
  for (const name of ['neutral', 'happy', 'angry', 'sad', 'relaxed', 'blink', 'aa', 'ih', 'ou', 'ee', 'oh']) {
    manager.registerExpression(new VRMExpression(name));
  }
  return { manager, value: new VRMAvatarController({ expressionManager: manager, humanoid: { getNormalizedBoneNode: () => null } }) };
}

test('renderer-only route is allowlisted and has no auth/chat/media/service imports', () => {
  const page = read('src/app/avatar-host/page.tsx');
  const host = read('src/components/avatar/AvatarWebViewHost.tsx');
  const layout = read('src/components/providers/AppAuthBoundary.tsx');
  const rootLayout = read('src/app/layout.tsx');
  assert.match(page, /searchParams\?\.model === 'female' \? 'female' : 'male'/);
  assert.match(host, /'\/models\/koi-male\.vrm'/);
  assert.match(host, /'\/models\/koi-female\.vrm'/);
  assert.match(host, /<VRMAvatarRenderer/);
  assert.match(host, /showStatus=\{false\}/);
  assert.doesNotMatch(host, /Companion model|Avatar ready|Loading avatar|<select|<option/);
  assert.doesNotMatch(`${page}\n${host}`, /firebase|useChat|conversationService|crisis|MicrophoneCapture|voice-api|SpeechPlayback|getUserMedia/i);
  assert.match(layout, /pathname === '\/avatar-host'/);
  assert.match(rootLayout, /AppAuthBoundary/);
  assert.doesNotMatch(rootLayout, /AuthProvider/);
});

test('only avatar-host skips Firebase; ordinary authenticated routes retain the existing auth guard', () => {
  const boundary = read('src/components/providers/AppAuthBoundary.tsx');
  const authApplication = read('src/components/providers/AuthenticatedApplication.tsx');
  const authenticatedLayout = read('src/app/(authenticated)/layout.tsx');
  assert.match(boundary, /pathname === '\/avatar-host' \|\| pathname === '\/avatar-host\/'/);
  assert.doesNotMatch(boundary, /pathname\.startsWith|pathname\.includes/);
  assert.match(boundary, /if \(isPresentationOnlyHost\) return/);
  assert.match(boundary, /isPresentationOnlyHost\s*\?\s*<>\{children\}<\/ >|isPresentationOnlyHost\s*\?\s*<>\{children\}<\/>/);
  assert.match(boundary, /: <AuthenticatedApplication>\{children\}<\/AuthenticatedApplication>/);
  assert.match(authApplication, /import \{ AuthProvider \} from '@\/contexts\/AuthContext'/);
  assert.match(authApplication, /<AuthProvider>\{children\}<\/AuthProvider>/);
  assert.match(authenticatedLayout, /const \{ user, loading \} = useAuth\(\)/);
  assert.match(authenticatedLayout, /if \(!loading && !user\)/);
});

test('native readiness is sent once per active ready generation; stale generations cannot signal', () => {
  const bridge = new AvatarCommandBridge();
  const target = new EventTarget();
  target.messages = [];
  target.KoiBridge = { postMessage: (message) => target.messages.push(message) };
  const unregister = registerAvatarCommands(bridge, target, { notifyKoiBridgeOnReady: true });
  const facade = target.AvatarController;
  assert.equal(facade.ready, false);
  assert.deepEqual(Object.keys(facade).sort(), ['getSnapshot', 'lifecycle', 'ready', 'reset', 'setConversationState', 'setEmotion'].sort());
  assert.equal('setMouthCue' in facade, false);
  assert.equal(facade.setEmotion('joy', 0.7), true); // Queued before a model exists.
  facade.setConversationState('listening');
  const first = controller();
  bridge.bind(first.value, '/models/koi-male.vrm');
  first.value.update(0.2);
  bridge.markReady(first.value);
  bridge.markReady(first.value);
  assert.deepEqual(target.messages, ['AVATAR_READY']);
  assert.equal(facade.getSnapshot().animation.conversationState, 'listening');
  assert(Math.abs(first.manager.getValue('happy')) > 0);

  bridge.detach(first.value);
  first.value.dispose();
  const second = controller();
  bridge.bind(second.value, '/models/koi-female.vrm');
  bridge.markReady(first.value); // Stale renderer completion is ignored.
  assert.deepEqual(target.messages, ['AVATAR_READY']);
  bridge.markReady(second.value);
  bridge.markReady(second.value);
  assert.deepEqual(target.messages, ['AVATAR_READY', 'AVATAR_READY']);
  assert.equal(facade.getSnapshot().modelUrl, '/models/koi-female.vrm');
  unregister();
  second.value.dispose();
  assert.equal(target.AvatarController, undefined);
  assert.equal(facade.setEmotion('angry', 1), false);
  checks.push('facade disposal makes retained references inert');
});

test('repeated bridge registration clears the facade and emits one ready token per mount', () => {
  const target = new EventTarget();
  const messages = [];
  target.KoiBridge = { postMessage: (message) => messages.push(message) };
  for (let index = 0; index < 8; index++) {
    const bridge = new AvatarCommandBridge();
    const unregister = registerAvatarCommands(bridge, target, { notifyKoiBridgeOnReady: true });
    const model = controller();
    bridge.bind(model.value, '/models/koi-male.vrm');
    bridge.markReady(model.value);
    unregister();
    model.value.dispose();
    assert.equal(target.AvatarController, undefined);
  }
  assert.deepEqual(messages, Array(8).fill('AVATAR_READY'));
});

test('short viewport host and existing renderer retain one animation loop', () => {
  const css = read('src/components/avatar/AvatarWebViewHost.module.css');
  const renderer = read('src/components/avatar/VRMAvatarRenderer.tsx');
  const globalCss = read('src/app/globals.css');
  const fontsBoundary = read('src/components/providers/AppAuthBoundary.tsx');
  assert.match(css, /height:\s*100dvh/);
  assert.match(css, /min-height:\s*0/);
  assert.match(css, /env\(safe-area-inset-top\)/);
  assert.match(css, /font-family:\s*system-ui/);
  assert.doesNotMatch(globalCss, /fonts\.googleapis\.com/);
  assert.match(fontsBoundary, /APP_FONT_STYLESHEET/);
  assert.match(renderer, /showStatus = true/);
  assert.match(renderer, /showStatus && state !== 'ready'/);
  assert.equal((renderer.match(/requestAnimationFrame\(tick\)/g) ?? []).length, 1);
  assert.match(renderer, /forceContextLoss\(\)/);
  assert.match(renderer, /cancelAnimationFrame\(frame\)/);
});

console.log(JSON.stringify({ passed: true, checks }, null, 2));
