const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
require.extensions['.ts'] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText, filename);
const root = path.resolve(__dirname, '..');
const { ConversationSession } = require('../src/lib/conversation/ConversationSession.ts');
const { parseChatResponse, parseRiskResult } = require('../src/lib/conversation/chatContract.ts');
const { parseCrisisInterventionDisplay, riskInterventionForDisplay } = require('../src/lib/conversation/crisisContract.ts');
const dialog = fs.readFileSync(path.join(root, 'src/components/companion/CrisisHandoffDialog.tsx'), 'utf8');
const scene = fs.readFileSync(path.join(root, 'src/components/companion/CompanionScene.tsx'), 'utf8');
const style = fs.readFileSync(path.join(root, 'src/components/companion/CompanionScene.module.css'), 'utf8');

(async () => {
  const requests = [];
  const handoff = { to: 'crisis', reason: 'synthetic fixture only' };
  const session = new ConversationSession({ send: async (request, options) => {
    requests.push(request);
    if (requests.length === 1) options.onEvent({ event: 'handoff', data: handoff });
    if (requests.length === 2) options.onEvent({ event: 'handoff', data: handoff });
    return parseChatResponse({ reply: 'Synthetic fixture reply', companion_state: { emotion: 'neutral', intensity: 0 }, latency_ms: 1 });
  } }, 'flow4-fixture');
  await session.send('Non-sensitive synthetic test');
  assert.equal(session.getSnapshot().serverEvents.filter((item) => item.event.event === 'handoff').length, 1);
  session.queueCrisisPath('reached_out', handoff);
  session.queueCrisisPath('misunderstanding', handoff);
  await session.send('I selected the first support path');
  assert.deepEqual({ event: requests[1].policy_event, path: requests[1].crisis_path }, { event: 'crisis_resolved', path: 'reached_out' });
  assert.equal(session.getSnapshot().serverEvents.filter((item) => item.event.event === 'handoff').length, 0, 'resolved stale handoff must not reopen');
  assert.equal(session.getSnapshot().policyPathPending, null);
  await session.send('A later ordinary turn');
  assert.equal(Object.hasOwn(requests[2], 'policy_event'), false, 'resolution policy is consumed exactly once');

  const riskSession = new ConversationSession({ send: async (_request, options) => {
    options.onEvent({ event: 'risk', data: { status: 'ok', risk_category: 'CRITICAL', crisis_score: 0.94, confidence: 'reduced', confidence_reasons: ['fixture'], modalities_used: ['text'], trigger_flags: [], model: { version: 'fixture-v1', calibrated: false } } });
    options.onEvent({ event: 'handoff', data: { to: 'crisis', reason: 'synthetic duplicate trigger' } });
    return parseChatResponse({ reply: 'Synthetic concurrent safety response.', companion_state: { emotion: 'neutral', intensity: 0 }, latency_ms: 1 });
  } }, 'risk-flow4-fixture');
  await riskSession.send('Synthetic fixture only');
  assert.equal(riskSession.getSnapshot().serverEvents.filter(({ event }) => event.event === 'risk').length, 1);
  assert.equal(riskSession.getSnapshot().serverEvents.filter(({ event }) => event.event === 'handoff').length, 1);

  assert.match(dialog, /role="alertdialog" aria-modal="true"/);
  assert.match(dialog, /event\.key === 'Escape'[\s\S]*?event\.preventDefault\(\)/);
  assert.match(dialog, /event\.shiftKey[\s\S]*?lastControl\.focus\(\)/);
  for (const pathName of ['reached_out', 'said_but_did_not', 'misunderstanding']) assert.match(dialog, new RegExp(pathName));
  assert.match(dialog, /Support details are unavailable in this chat response/);
  assert.doesNotMatch(dialog, /911|1122|helpline number/i);
  const displayFixture = { source: 'verified_fallback', items: [{ id: 'fixture-item', title: 'Synthetic fixture', body: 'Approved test content only.' }], helpline: { label: 'Fixture contact', number: '+00 000', source: 'synthetic fixture' }, confidence: 'reduced' };
  assert.deepEqual(parseCrisisInterventionDisplay(displayFixture), displayFixture);
  assert.equal(parseCrisisInterventionDisplay({ ...displayFixture, source: 'unknown' }), null);
  assert.equal(parseCrisisInterventionDisplay({ ...displayFixture, items: [{ id: 'bad', title: 'oversize', body: 'x'.repeat(1201) }] }), null);
  assert.match(scene, /interruptKey=\{handoffEventId \?\? 0\}/);
  assert.match(scene, /Your selection is saved for your next message/);
  assert.match(scene, /risk_category === 'HIGH' \|\| item\.event\.data\.risk_category === 'CRITICAL'/);
  const serverRisk = parseRiskResult({ status: 'ok', risk_category: 'HIGH', crisis_score: 0.84, confidence: 'reduced', confidence_reasons: ['fixture'], modalities_used: ['text'], trigger_flags: [], model: { version: 'fixture-v1', calibrated: false }, intervention_content: {
    source: 'fallback', language: 'en', items: [{ text: 'Synthetic supplied fixture only.', chunk_id: 'item-1', source_corpus: 'fixture', evidence_role: 'test', review_status: 'test' }],
    helpline: { name: 'Synthetic fixture', number: '000', verified: false }, trace: 'must not display',
  }, trace: 'must not retain' });
  assert.equal(serverRisk.status, 'ok'); assert.equal(serverRisk.risk_category, 'HIGH');
  assert.equal(serverRisk.intervention_content.trace, undefined);
  const riskDisplay = riskInterventionForDisplay(serverRisk);
  assert.equal(riskDisplay.source, 'backend_fallback');
  assert.equal(riskDisplay.items[0].body, 'Synthetic supplied fixture only.');
  assert.match(riskDisplay.helpline.source, /Backend marked unverified/);
  assert.equal(riskInterventionForDisplay({ status: 'unavailable' }), undefined);
  assert.equal(parseRiskResult({ status: 'unavailable', risk_category: 'LOW' }).status, 'unavailable');
  assert.equal(parseRiskResult({ status: 'ok', risk_category: 'HIGH' }), null, 'incomplete risk object must not trigger Flow 4');
  assert.match(style, /\.crisisBackdrop[\s\S]*position: fixed/);
  console.log(JSON.stringify({ passed: true, checks: [
    'one non-dismissible Flow 4 handoff surface with focus trap and three response paths',
    'support details unavailable state has no fabricated emergency number',
    'resolution queued exactly once on the next chat request; stale repeated handoff suppressed',
    'authoritative HIGH/CRITICAL risk is available to Flow 4; risk and handoff duplicate triggers are session-deduplicated',
    'handoff interrupts active exercise UI; no live risk or crisis classification used',
  ], scope: 'synthetic in-memory fixtures; no real crisis data or live backend' }, null, 2));
})().catch((error) => { console.error(error); process.exitCode = 1; });
