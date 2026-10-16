const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require('typescript');
require.extensions['.ts'] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText, filename);
const old = { env: process.env.NODE_ENV, flag: process.env.NEXT_PUBLIC_KOI_V11_FIXTURE_EVENTS };
const { parseV11FixtureEvent, INPUT_MODE_STATUS } = require('../src/lib/conversation/v11FixtureEvents.ts');
try {
  process.env.NODE_ENV = 'development'; delete process.env.NEXT_PUBLIC_KOI_V11_FIXTURE_EVENTS;
  assert.equal(parseV11FixtureEvent('risk', { risk_category: 'HIGH' }), null, 'fixture gate defaults off');
  process.env.NEXT_PUBLIC_KOI_V11_FIXTURE_EVENTS = 'true';
  assert.deepEqual(parseV11FixtureEvent('transcript', '{"synthetic":"fixture"}'), { event: 'transcript', data: { synthetic: 'fixture' } });
  assert.deepEqual(parseV11FixtureEvent('risk', { category: 'synthetic-only' }), { event: 'risk', data: { category: 'synthetic-only' } });
  assert.deepEqual(parseV11FixtureEvent('done.risk', { opaque: true }), { event: 'done.risk', data: { opaque: true } });
  assert.equal(parseV11FixtureEvent('risk', '{bad'), null);
  assert.equal(parseV11FixtureEvent('delta', {}), null);
  process.env.NODE_ENV = 'production'; assert.equal(parseV11FixtureEvent('risk', {}), null, 'cannot enable fixture parser in production');
  assert.deepEqual(Object.entries(INPUT_MODE_STATUS).map(([key, value]) => [key, value.enabled]), [
    ['text', true], ['audio', false], ['text+video', false], ['audio+video', false],
  ]);
  console.log(JSON.stringify({ passed: true, checks: ['v1.1 fixture parser defaults off and is development-only', 'candidate transcript/risk payloads stay opaque without invented schema', 'v1 union remains isolated', 'only text input is enabled; the other three allowed combinations remain unavailable'] }, null, 2));
} finally {
  if (old.env === undefined) delete process.env.NODE_ENV; else process.env.NODE_ENV = old.env;
  if (old.flag === undefined) delete process.env.NEXT_PUBLIC_KOI_V11_FIXTURE_EVENTS; else process.env.NEXT_PUBLIC_KOI_V11_FIXTURE_EVENTS = old.flag;
}
