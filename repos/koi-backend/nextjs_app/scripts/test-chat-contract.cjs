const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require('typescript');
const path = require('node:path');
const Module = require('node:module');
const http = require('node:http');
const resolve = Module._resolveFilename;
Module._resolveFilename = function (name, parent, ...rest) { return resolve.call(this, name.startsWith('@/') ? path.resolve(__dirname, '../src', name.slice(2)) : name, parent, ...rest); };
require('fake-indexeddb/auto');
require.extensions['.ts'] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText, filename);
const { createChatRequest, parseChatResponse, ChatError } = require('../src/lib/conversation/chatContract.ts');
const { postJsonChat, chatEndpoint, chatHealthEndpoint, probeChatHealth, DEFAULT_CHAT_TIMEOUT_MS, MAX_MODAL_REDIRECTS } = require('../src/lib/conversation/jsonChatTransport.ts');
const { SseParser } = require('../src/lib/conversation/sseParser.ts');
const { ConversationSession } = require('../src/lib/conversation/ConversationSession.ts');
const result = (emotion = 'joy', intensity = 0.7, reply = 'Scripted test response') => ({ reply, companion_state: { emotion, intensity }, latency_ms: 10 });
const encoder = new TextEncoder();
const makeStreamResponse = (text, { chunkSize = 3, contentType = 'text/event-stream; charset=utf-8', status = 200 } = {}) => {
  const bytes = encoder.encode(text);
  const body = new ReadableStream({ start(controller) { for (let i = 0; i < bytes.length; i += chunkSize) controller.enqueue(bytes.slice(i, i + chunkSize)); controller.close(); } });
  return new Response(body, { status, headers: { 'content-type': contentType } });
};
const v1Frames = [
  ['latency', { latency_ms: 12.5 }],
  ['companion_state', { emotion: 'joy', intensity: 0.7 }],
  ['delta', { text: 'Hello 👋' }],
  ['delta', { text: ' partial' }],
  ['ui_action', { name: 'stop_breathing', args: {} }],
  ['handoff', { to: 'crisis', reason: 'Synthetic fixture only' }],
  ['state', { exercise_state: 'opaque-signed-fixture' }],
  ['done', { full_text: 'Final reconciled answer', companion_state: { emotion: 'joy', intensity: 0.7 }, exercise_state: 'opaque-signed-fixture', ui_actions: [{ name: 'stop_breathing', args: {} }], handoff: { to: 'crisis', reason: 'Synthetic fixture only' }, total_generation_s: 1.2 }],
];
const wireV1 = () => ': keepalive\r\n\r\n' + v1Frames.map(([event, data], index) => {
  const json = JSON.stringify(data);
  const split = json.indexOf(':') + 1;
  const multiline = event === 'latency' ? `data: ${json.slice(0, split)}\r\ndata: ${json.slice(split)}` : `data: ${json}`;
  return `event: ${event}\r\n${multiline}${index === v1Frames.length - 1 ? '' : '\r\n\r\n'}`;
}).join('');
const checks = [];
(async () => {
  assert.deepEqual(createChatRequest(' hello ', [{ role: 'model', content: 'earlier' }]), { message: 'hello', session_history: [{ role: 'assistant', content: 'earlier' }] });
  assert.throws(() => createChatRequest(' ', [])); assert.throws(() => createChatRequest('hi', [{ role: 'system', content: 'no' }]));
  assert.deepEqual(createChatRequest('action', [], { exercise_state: 'opaque-state', client_event: 'playback_done' }), {
    message: 'action', session_history: [], exercise_state: 'opaque-state', client_event: 'playback_done',
  });
  assert.throws(() => createChatRequest('action', [], { client_event: 'camera_on' }));
  assert.throws(() => createChatRequest('action', [], { policy_event: 'crisis_resolved' }));
  for (const emotion of ['neutral', 'joy', 'angry', 'sorrow', 'fun']) assert.deepEqual(parseChatResponse(result(emotion)).companion_state, { emotion, intensity: 0.7 });
  assert.equal(parseChatResponse(result('joy', 100)).companion_state.intensity, 1); assert.equal(parseChatResponse(result('joy', -1)).companion_state.intensity, 0);
  assert.deepEqual(parseChatResponse(result('unmapped', 0.8)).companion_state, { emotion: 'neutral', intensity: 0 });
  assert.equal(parseChatResponse(result('joy', NaN)).companion_state.intensity, 0); assert.throws(() => parseChatResponse({ reply: '', latency_ms: 10 }));
  assert.throws(() => chatEndpoint(undefined), /not configured/); assert.throws(() => chatEndpoint('/relative'));
  assert.equal(chatEndpoint('https://api.example.test'), 'https://api.example.test/api/v1/chat');
  assert.throws(() => chatEndpoint('https://api.example.test/api/v1/chat'), /without \/api\/v1/);
  assert.throws(() => chatEndpoint('https://api.example.test/api/v1'), /without \/api\/v1/);
  checks.push('exact JSON shape, role normalization, all emotions/intensities and configuration validation');
  let sent; const events = [];
  const response = await postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal,
    onEvent: (event) => events.push(event),
    fetchImpl: async (url, options) => { sent = { url, body: JSON.parse(options.body), accept: options.headers.get('Accept'), redirect: options.redirect }; return makeStreamResponse(wireV1(), { chunkSize: 2 }); } });
  assert.equal(response.reply, 'Final reconciled answer'); assert.equal(response.latency_ms, 12.5); assert.equal(response.companion_state.intensity, 0.7);
  assert.equal(sent.url, 'http://localhost:8000/api/v1/chat'); assert.equal(sent.accept, 'text/event-stream'); assert.equal(sent.redirect, 'manual'); assert.deepEqual(Object.keys(sent.body), ['message', 'session_history']);
  assert.deepEqual(events.map(({ event }) => event), v1Frames.map(([event]) => event));
  assert.equal(events.find(({ event }) => event === 'state').data.exercise_state, 'opaque-signed-fixture');
  assert.equal(events.find(({ event }) => event === 'done').data.full_text, 'Final reconciled answer');
  const contractRisk = { status: 'ok', risk_category: 'HIGH', crisis_score: 0.83, confidence: 'reduced', confidence_reasons: ['reduced_modality_set'], modalities_used: ['text'], trigger_flags: ['fixture-only'], intervention_content: { source: 'fallback', language: 'en', items: [{ text: 'Synthetic fixture content only.', chunk_id: 'fixture-1', source_corpus: 'synthetic', evidence_role: 'test', review_status: 'fixture' }], helpline: { name: 'Synthetic contact', number: '000', verified: false } }, model: { version: 'fixture-v1', calibrated: false } };
  const v11TextFrames = [
    ['transcript', { text: 'fixture audio transcript', language: 'en' }],
    ['companion_state', { emotion: 'sorrow', intensity: 0.45 }],
    ['delta', { text: 'A complete synthetic reply.' }],
    ['trace', { prompt: 'must not be retained or displayed' }],
    ['risk', { ...contractRisk, trace: 'private diagnostic metadata must be dropped' }],
    ['state', { exercise_state: null, trace: ['ignored'] }],
    ['done', { full_text: 'A complete synthetic reply.', companion_state: { emotion: 'sorrow', intensity: 0.45 }, exercise_state: null, ui_actions: [], handoff: null, total_generation_s: 0.2, risk: contractRisk, trace: 'ignored' }],
  ];
  const wireFrames = (frames) => frames.map(([event, data], index) => `event: ${event}\r\ndata: ${JSON.stringify(data)}${index === frames.length - 1 ? '' : '\r\n\r\n'}`).join('');
  const v11Events = [];
  const v11Response = await postJsonChat(createChatRequest('synthetic v1.1 fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal,
    onEvent: (event) => v11Events.push(event), fetchImpl: async () => makeStreamResponse(wireFrames(v11TextFrames), { chunkSize: 1 }) });
  assert.equal(v11Response.reply, 'A complete synthetic reply.');
  assert.deepEqual(v11Events.map(({ event }) => event), ['transcript', 'companion_state', 'delta', 'risk', 'state', 'done']);
  assert.deepEqual(v11Events[0].data, { text: 'fixture audio transcript', language: 'en' });
  assert.equal(v11Events.find(({ event }) => event === 'risk').data.risk_category, 'HIGH');
  assert.equal(v11Events.find(({ event }) => event === 'risk').data.trace, undefined);
  assert.equal(v11Events.find(({ event }) => event === 'state').data.exercise_state, null);
  assert.equal(v11Events.find(({ event }) => event === 'done').data.risk.risk_category, 'HIGH');
  assert.equal(v11Events.find(({ event }) => event === 'done').data.trace, undefined);
  checks.push('v1.1 text risk/done reconciliation, null exercise state, and trace exclusion across byte-split SSE');
  const transcriptSession = new ConversationSession({ send: async (_request, options) => {
    options.onEvent({ event: 'transcript', data: { text: 'fixture ASR transcript', language: 'ur' } });
    return result('neutral', 0, 'Fixture response');
  } }, 'transcript-contract-fixture');
  await transcriptSession.send('typed text remains authoritative in this text-only client');
  assert.equal(transcriptSession.getSnapshot().messages.filter((message) => message.sender === 'user').length, 1);
  assert.equal(transcriptSession.getSnapshot().messages[0].content, 'typed text remains authoritative in this text-only client');
  assert.equal(transcriptSession.getSnapshot().serverEvents.filter(({ event }) => event.event === 'transcript').length, 1);
  checks.push('typed transcript event is validated and retained as an event without duplicating or rewriting text-only user input');
  const unavailableRiskFrames = [['risk', { status: 'unavailable', risk_category: 'LOW', trace: 'ignored' }], ['state', { exercise_state: null }], ['done', { full_text: 'Safe synthetic reply.', companion_state: { emotion: 'neutral', intensity: 0 }, exercise_state: null, ui_actions: [], handoff: null, total_generation_s: 0.1, risk: { status: 'unavailable' } }]];
  const unavailableEvents = [];
  await postJsonChat(createChatRequest('synthetic unavailable-risk fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal,
    onEvent: (event) => unavailableEvents.push(event), fetchImpl: async () => makeStreamResponse(wireFrames(unavailableRiskFrames)) });
  assert.deepEqual(unavailableEvents.find(({ event }) => event === 'risk').data, { status: 'unavailable' });
  checks.push('unavailable risk cannot be interpreted as LOW or safe; unknown event and risk metadata are dropped');
  const finalOnlyEvents = [];
  await postJsonChat(createChatRequest('synthetic done.risk fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal,
    onEvent: (event) => finalOnlyEvents.push(event), fetchImpl: async () => makeStreamResponse(wireFrames([
      ['companion_state', { emotion: 'neutral', intensity: 0 }], ['delta', { text: 'Final risk fixture.' }],
      ['state', { exercise_state: null }], ['done', { full_text: 'Final risk fixture.', companion_state: { emotion: 'neutral', intensity: 0 }, exercise_state: null, total_generation_s: 0.1, risk: contractRisk }],
    ])) });
  assert.deepEqual(finalOnlyEvents.map(({ event }) => event), ['companion_state', 'delta', 'state', 'risk', 'done']);
  assert.equal(finalOnlyEvents.find(({ event }) => event === 'risk').data.risk_category, 'HIGH');
  checks.push('done.risk without a separate risk frame is reconciled once immediately before successful completion');
  const emptyGenerationFrames = [['error', { code: 'generation_failed', detail: 'PRIVATE ENGINE DIAGNOSTIC' }], ['risk', { status: 'unavailable' }], ['state', { exercise_state: null }], ['done', { full_text: '', companion_state: { emotion: 'neutral', intensity: 0 }, exercise_state: null, ui_actions: [], handoff: null, total_generation_s: 0.1, risk: { status: 'unavailable' }, trace: 'must be excluded' }]];
  const emptyEvents = [];
  await assert.rejects(postJsonChat(createChatRequest('synthetic empty-generation fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal,
    onEvent: (event) => emptyEvents.push(event), fetchImpl: async () => makeStreamResponse(wireFrames(emptyGenerationFrames)) }), (error) => error.code === 'generation' && !error.message.includes('PRIVATE'));
  assert.deepEqual(emptyEvents.map(({ event }) => event), ['error', 'risk', 'state', 'done']);
  assert.deepEqual(emptyEvents.find(({ event }) => event === 'error').data, { code: 'generation_failed' });
  assert.equal(emptyEvents.find(({ event }) => event === 'state').data.exercise_state, null);
  await assert.rejects(postJsonChat(createChatRequest('synthetic malformed empty fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal,
    fetchImpl: async () => makeStreamResponse(wireFrames([['state', { exercise_state: null }], ['done', { full_text: '', companion_state: { emotion: 'neutral', intensity: 0 }, total_generation_s: 0.1 }]])) }), (error) => error.code === 'invalid-response');
  checks.push('no_reply/generation_failed terminal path is visible generically, never persisted as an empty success; malformed empty done rejected');
  const exerciseDeltas = [];
  const exerciseDone = await postJsonChat(createChatRequest('synthetic breathing fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal,
    onEvent: (event) => { if (event.event === 'delta') exerciseDeltas.push(event.data.text); }, fetchImpl: async () => makeStreamResponse(wireFrames([
      ['ui_action', { name: 'start_breathing', args: { inhale_s: 4, exhale_s: 6, cycles: 1, cue_audio: ['in', 'out'] } }],
      ['delta', { text: 'Breathe in.' }], ['delta', { text: 'Breathe out.' }],
      ['state', { exercise_state: 'exercise-state-fixture' }],
      ['done', { full_text: 'Breathe in.Breathe out.', companion_state: { emotion: 'neutral', intensity: 0 }, exercise_state: 'exercise-state-fixture', ui_actions: [], handoff: null, total_generation_s: 0.2 }],
    ])) });
  assert.deepEqual(exerciseDeltas, ['Breathe in.', ' Breathe out.']);
  assert.equal(exerciseDone.reply, 'Breathe in. Breathe out.');
  const ordinaryDeltas = [];
  await postJsonChat(createChatRequest('ordinary fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal,
    onEvent: (event) => { if (event.event === 'delta') ordinaryDeltas.push(event.data.text); }, fetchImpl: async () => makeStreamResponse(wireFrames([
      ['delta', { text: 'arbi' }], ['delta', { text: 'trary token chunks' }], ['state', { exercise_state: null }],
      ['done', { full_text: 'arbitrary token chunks', companion_state: { emotion: 'neutral', intensity: 0 }, exercise_state: null, total_generation_s: 0.1 }],
    ])) });
  assert.deepEqual(ordinaryDeltas, ['arbi', 'trary token chunks']);
  checks.push('sentence spacing is restored only after a validated exercise boundary; arbitrary normal token deltas remain untouched');
  const directParser = new SseParser();
  const parsed = directParser.push(encoder.encode('event: sample\ndata: one\ndata: two\n\n')); assert.deepEqual(parsed, [{ event: 'sample', data: 'one\ntwo' }]);
  assert.deepEqual(directParser.finish(), []);
  checks.push('chunked UTF-8 SSE, comments, CRLF, multiline data, unterminated final event and v1 event schema');
  for (const status of [401, 422, 502]) await assert.rejects(postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal, fetchImpl: async () => new Response('PRIVATE BODY MUST NOT SURFACE', { status }) }), (error) => error.status === status && !error.message.includes('PRIVATE'));
  await assert.rejects(postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal, fetchImpl: async () => new Response('private-json', { headers: { 'content-type': 'application/json' } }) }), (error) => error.code === 'invalid-response');
  const modalRequests = [];
  const modalServer = http.createServer(async (request, response) => {
    const chunks = []; for await (const chunk of request) chunks.push(chunk);
    modalRequests.push({ method: request.method, url: request.url, authorization: request.headers.authorization, body: Buffer.concat(chunks).toString() });
    if (request.method === 'POST') { response.writeHead(303, { location: '/api/v1/chat?modal_request=synthetic-fixture' }); response.end(); return; }
    response.writeHead(200, { 'content-type': 'text/event-stream' }); response.end(wireV1());
  });
  await new Promise((resolve) => modalServer.listen(0, '127.0.0.1', resolve));
  try {
    const port = modalServer.address().port;
    const modalSignal = new AbortController().signal;
    const modalResponse = await postJsonChat(createChatRequest('one non-sensitive fixture', []), { apiBase: `http://127.0.0.1:${port}`, headers: new Headers({ Authorization: 'Bearer test-only' }), signal: modalSignal });
    assert.equal(modalResponse.reply, 'Final reconciled answer');
    assert.equal(modalRequests.length, 2, 'the 303 result fetch must not replay the POST');
    assert.equal(modalRequests[0].method, 'POST'); assert.equal(modalRequests[0].body.includes('one non-sensitive fixture'), true);
    assert.equal(modalRequests[1].method, 'GET'); assert.equal(modalRequests[1].url, '/api/v1/chat?modal_request=synthetic-fixture');
    assert.equal(modalRequests[1].body, ''); assert.equal(modalRequests[0].authorization, 'Bearer test-only');
    assert.equal(modalRequests[1].authorization, 'Bearer test-only', 'authorization is retained only for the exact trusted origin/path');
  } finally { await new Promise((resolve) => modalServer.close(resolve)); }
  checks.push('same-origin Modal 303 fixture: one authenticated POST followed by GET of the original request result, with no POST replay');

  let untrustedCalls = 0;
  await assert.rejects(postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers({ Authorization: 'Bearer test-only' }), signal: new AbortController().signal,
    fetchImpl: async (_url, options) => { untrustedCalls++; assert.equal(options.method, 'POST'); return new Response(null, { status: 303, headers: { location: 'https://untrusted.invalid/poll' } }); } }), (error) => error.code === 'redirect');
  assert.equal(untrustedCalls, 1, 'do not send the bearer token or any follow-up request to an untrusted origin');
  await assert.rejects(postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal,
    fetchImpl: async () => ({ status: 0, type: 'opaqueredirect', headers: new Headers(), url: '' }) }), (error) => error.code === 'redirect' && /cannot safely inspect/i.test(error.message));
  let redirectCount = 0;
  await assert.rejects(postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal,
    fetchImpl: async () => { redirectCount++; return new Response(null, { status: 303, headers: { location: '/api/v1/chat?modal_request=pending' } }); } }), (error) => error.code === 'redirect' && /redirect limit/i.test(error.message));
  assert.equal(redirectCount, MAX_MODAL_REDIRECTS + 1, 'follow no more than twenty Modal result redirects');
  assert.equal(MAX_MODAL_REDIRECTS, 20); assert.equal(DEFAULT_CHAT_TIMEOUT_MS, 600_000);
  assert.equal(chatHealthEndpoint('https://api.example.test'), 'https://api.example.test/health');
  let healthRequest;
  assert.equal(await probeChatHealth('https://api.example.test', { fetchImpl: async (url, options) => {
    healthRequest = { url, method: options.method, auth: new Headers(options.headers).get('Authorization'), redirect: options.redirect };
    return new Response(JSON.stringify({ status: 'ok' }), { headers: { 'content-type': 'application/json' } });
  } }), true);
  assert.deepEqual(healthRequest, { url: 'https://api.example.test/health', method: 'GET', auth: null, redirect: 'manual' });
  const pollAbort = new AbortController(); let pollMethod; let pollSignal;
  const pendingPoll = postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: pollAbort.signal,
    fetchImpl: async (_url, options) => {
      if (options.method === 'POST') return new Response(null, { status: 303, headers: { location: '/api/v1/chat?modal_request=abort-fixture' } });
      pollMethod = options.method; pollSignal = options.signal;
      return new Promise((_resolve, reject) => options.signal.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), { once: true }));
    } });
  setTimeout(() => pollAbort.abort(), 10);
  await assert.rejects(pendingPoll, (error) => error.name === 'AbortError');
  assert.equal(pollMethod, 'GET'); assert.equal(pollSignal.aborted, true);
  checks.push('untrusted/opaque redirects fail closed; redirect loop bound, GET /health probe, timeout and abort during result polling are covered');
  await assert.rejects(postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal, fetchImpl: async () => makeStreamResponse('event: delta\ndata: {bad-json}\n\n') }), (error) => error.code === 'invalid-response');
  await assert.rejects(postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal, fetchImpl: async () => makeStreamResponse('event: latency\ndata: {"latency_ms":1}\n\n') }), (error) => error.code === 'invalid-response');
  const streamAbort = new AbortController(); let streamCancelled = false;
  const pendingResponse = new Response(new ReadableStream({ cancel() { streamCancelled = true; } }), { headers: { 'content-type': 'text/event-stream' } });
  const pendingRead = postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: streamAbort.signal, fetchImpl: async () => pendingResponse });
  setTimeout(() => streamAbort.abort(), 10); await assert.rejects(pendingRead, (error) => error.name === 'AbortError'); assert.equal(streamCancelled, true);
  const stalled = (_url, { signal }) => new Promise((_resolve, reject) => signal.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), { once: true }));
  await assert.rejects(postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal, timeoutMs: 10, fetchImpl: stalled }), (error) => error.code === 'timeout');
  const abort = new AbortController(); const cancelled = postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: abort.signal, fetchImpl: stalled }); abort.abort(); await assert.rejects(cancelled, (error) => error.name === 'AbortError');
  await assert.rejects(postJsonChat(createChatRequest('fixture', []), { apiBase: undefined, headers: new Headers(), signal: new AbortController().signal, fetchImpl: async () => { throw new Error('must not fetch'); } }), (error) => error.code === 'configuration');
  await assert.rejects(postJsonChat(createChatRequest('fixture', []), { apiBase: 'http://localhost:8000', headers: new Headers(), signal: new AbortController().signal, fetchImpl: async () => new Response('{broken', { headers: { 'content-type': 'application/json' } }) }), (error) => error.code === 'invalid-response');
  checks.push('status/content-type/schema failures, safe redirect rejection, timeout and active-reader cancellation; no real requests or credentials');
  const history = []; const adapter = { send: async (request) => { history.push(request.session_history); return result('fun', 0.4); } };
  const session = new ConversationSession(adapter, 'unit-session'); await session.send('first'); await session.send('second');
  assert.deepEqual(history.map((turns) => turns.length), [0, 2]); assert.deepEqual(history[1].map((turn) => turn.role), ['user', 'assistant']);
  assert.equal(session.getSnapshot().messages.length, 4); assert.equal(session.getSnapshot().conversationState, 'speaking'); assert.equal(session.getSnapshot().companion.intensity, 0.4);
  session.inputFocused(true); assert.equal(session.getSnapshot().conversationState, 'listening'); session.inputFocused(false); assert.equal(session.getSnapshot().conversationState, 'idle');
  const pending = []; const rapid = new ConversationSession({ send: () => new Promise((resolve) => pending.push(resolve)) }, 'rapid');
  const first = rapid.send('first'), second = rapid.send('second'); pending[1](result('joy', 0.8, 'newest')); await second; pending[0](result('angry', 1, 'stale')); await first;
  assert.equal(rapid.getSnapshot().subtitle, 'newest'); assert.equal(rapid.getSnapshot().messages.filter((message) => message.sender === 'ai').length, 1);
  const failure = new ConversationSession({ send: async () => { throw new ChatError('network', 'Offline fixture'); } }, 'failure'); await failure.send('sample');
  assert.equal(failure.getSnapshot().messages.length, 1); assert.equal(failure.getSnapshot().error, 'Offline fixture'); assert.equal(failure.getSnapshot().messages[0].status, 'failed');
  const disposed = new ConversationSession({ send: () => new Promise((resolve) => pending.push(resolve)) }, 'dispose'); const outgoing = disposed.send('pending'); disposed.dispose(); pending[2](result()); await outgoing;
  assert.equal(disposed.getSnapshot().pending, false); assert.equal(disposed.getSnapshot().messages.filter((message) => message.sender === 'ai').length, 0);
  checks.push('sequential history, latest-request wins, failures, input states and disposal');
  let callbackA, callbackB; const callbackPromises = [];
  const callbackSession = new ConversationSession({ send: (_request, options) => { callbackPromises.push(new Promise((resolve) => callbackPromises.push(resolve))); if (!callbackA) callbackA = options.onEvent; else callbackB = options.onEvent; return callbackPromises.at(-1); } }, 'event-guard');
  const eventFirst = callbackSession.send('first'), eventSecond = callbackSession.send('second');
  callbackA({ event: 'companion_state', data: { emotion: 'angry', intensity: 1 } });
  callbackB({ event: 'companion_state', data: { emotion: 'fun', intensity: 0.4 } });
  callbackB({ event: 'delta', data: { text: 'early' } });
  assert.deepEqual(callbackSession.getSnapshot().companion, { emotion: 'fun', intensity: 0.4 });
  assert.equal(callbackSession.getSnapshot().subtitle, 'early');
  const stableAssistantId = callbackSession.getSnapshot().messages.find((message) => message.sender === 'ai').id;
  assert.equal(callbackSession.getSnapshot().messages.find((message) => message.id === stableAssistantId).content, 'early');
  callbackB({ event: 'done', data: { full_text: 'canonical final', companion_state: { emotion: 'fun', intensity: 0.4 } } });
  assert.equal(callbackSession.getSnapshot().messages.find((message) => message.id === stableAssistantId).content, 'canonical final');
  callbackPromises[2](result('fun', 0.4, 'canonical final')); await eventSecond; callbackPromises[0](result('angry', 1, 'stale')); await eventFirst;
  assert.equal(callbackSession.getSnapshot().subtitle, 'canonical final');
  assert.equal(callbackSession.getSnapshot().messages.filter((message) => message.sender === 'ai').length, 1);
  assert.equal(callbackSession.getSnapshot().messages.find((message) => message.id === stableAssistantId).status, 'completed');
  checks.push('session event passthrough applies early state/delta and rejects stale-turn callbacks');
  let partialEvent;
  const partialFailure = new ConversationSession({ send: async (_request, options) => { options.onEvent({ event: 'delta', data: { text: 'partial only' } }); throw new ChatError('network', 'fixture failure'); } }, 'partial-failure');
  await partialFailure.send('fixture'); partialEvent = partialFailure.getSnapshot();
  assert.equal(partialEvent.messages.filter((message) => message.sender === 'ai').length, 0);
  assert.equal(partialEvent.messages[0].status, 'failed'); assert.equal(partialEvent.subtitle, '');
  let cancelCallback, resolveCancelled;
  const cancelSession = new ConversationSession({ send: (_request, options) => { cancelCallback = options.onEvent; return new Promise((resolve) => { resolveCancelled = resolve; }); } }, 'partial-cancel');
  const cancelPending = cancelSession.send('fixture'); cancelCallback({ event: 'delta', data: { text: 'do not retain' } }); cancelSession.cancel();
  cancelCallback({ event: 'companion_state', data: { emotion: 'angry', intensity: 1 } });
  assert.equal(cancelSession.getSnapshot().messages.filter((message) => message.sender === 'ai').length, 0);
  assert.equal(cancelSession.getSnapshot().subtitle, ''); assert.deepEqual(cancelSession.getSnapshot().companion, { emotion: 'neutral', intensity: 0 });
  resolveCancelled(result()); await cancelPending;
  checks.push('partial stream error/cancel removes the provisional bubble and resets transient avatar state');
  const activityRequests = [];
  const activitySession = new ConversationSession({ send: async (request, options) => {
    activityRequests.push(request);
    if (activityRequests.length === 1) options.onEvent({ event: 'state', data: { exercise_state: 'opaque-signed-state-from-fixture' } });
    return result('neutral', 0, `activity ${activityRequests.length}`);
  } }, 'activity-session');
  await activitySession.send('I want an activity');
  assert.equal(activityRequests[0].exercise_state, null, 'no active exercise is sent as explicit null');
  assert.equal(activitySession.getSnapshot().exerciseState, 'opaque-signed-state-from-fixture');
  activitySession.queueClientEvent('playback_done');
  await activitySession.send('I am ready to continue');
  assert.equal(activityRequests[1].exercise_state, 'opaque-signed-state-from-fixture');
  assert.equal(activityRequests[1].client_event, 'playback_done');
  assert.equal(activitySession.getSnapshot().clientEventPending, null);
  await activitySession.send('Another turn');
  assert.equal(activityRequests[2].client_event, undefined);
  assert.equal(activityRequests[2].exercise_state, 'opaque-signed-state-from-fixture');
  const clearStateRequests = [];
  let clearStateTurn = 0;
  const clearStateSession = new ConversationSession({ send: async (request, options) => {
    clearStateRequests.push(request); clearStateTurn++;
    options.onEvent({ event: 'state', data: { exercise_state: clearStateTurn === 1 ? 'state-to-clear' : null } });
    return result('neutral', 0, `state fixture ${clearStateTurn}`);
  } }, 'clear-state-session');
  await clearStateSession.send('state start'); await clearStateSession.send('state finish');
  assert.equal(clearStateSession.getSnapshot().exerciseState, null);
  await clearStateSession.send('after state');
  assert.equal(clearStateRequests[2].exercise_state, null);
  checks.push('explicit null state clears a prior opaque token and the next request sends null');
  const newConversation = new ConversationSession({ send: async () => result() }, 'fresh-activity-session');
  assert.equal(newConversation.getSnapshot().exerciseState, null);
  checks.push('opaque signed state round-trips unchanged; queued client event is consumed once; fresh session resets');
  const { singleFlight } = require('../src/lib/conversation/singleFlight.ts');
  let lookups = 0, finishLookup; const lookup = singleFlight(() => { lookups++; return new Promise((resolve) => { finishLookup = resolve; }); });
  const lookupA = lookup('fixture-key'), lookupB = lookup('fixture-key'); assert.equal(lookupA, lookupB); finishLookup('fixture-result'); await lookupA; lookup('fixture-key'); assert.equal(lookups, 2); finishLookup('fixture-result');
  checks.push('only concurrent context lookups are shared; settled values are not retained');
  const { createMockChatAdapter } = require('../dev/avatar-sandbox/app/mock-chat/mockChatAdapter.ts');
  const oldEnvironment = process.env.NODE_ENV;
  process.env.NODE_ENV = 'production'; assert.throws(() => createMockChatAdapter(), /development-only/);
  process.env.NODE_ENV = 'development'; const mock = createMockChatAdapter();
  const options = { signal: new AbortController().signal, userMessageId: 'fixture-user-message', assistantMessageId: 'fixture-assistant-message' };
  assert.equal((await mock.send(createChatRequest('Sample joy', []), options)).companion_state.emotion, 'joy');
  await assert.rejects(mock.send(createChatRequest('Sample failure', []), options), /simulation/);
  await assert.rejects(mock.send(createChatRequest('arbitrary private text is disallowed', []), options), /scripted/);
  if (oldEnvironment === undefined) delete process.env.NODE_ENV; else process.env.NODE_ENV = oldEnvironment;
  const { sendMessage } = require('../src/lib/conversation/conversationService.ts');
  const { auth } = require('../src/lib/firebase.ts'); assert(!auth?.currentUser, 'This credential-free guard test requires no active authenticated session.');
  await assert.rejects(sendMessage('unconfigured-local-session', 'fixture-session', 'fixture', [], { isLinked: false }, options), (error) => error.code === 'authentication');
  checks.push('actual mock adapter refuses production/arbitrary text; actual real service rejects unauthenticated calls without fake tokens');
  const companionPage = fs.readFileSync(path.resolve(__dirname, '../src/app/(authenticated)/companion-scene/page.tsx'), 'utf8');
  const companionScene = fs.readFileSync(path.resolve(__dirname, '../src/components/companion/CompanionScene.tsx'), 'utf8');
  const avatarPreference = fs.readFileSync(path.resolve(__dirname, '../src/lib/avatar/avatarPreference.ts'), 'utf8');
  const chatPage = fs.readFileSync(path.resolve(__dirname, '../src/app/(authenticated)/chat/page.tsx'), 'utf8');
  const serviceSource = fs.readFileSync(path.resolve(__dirname, '../src/lib/conversation/conversationService.ts'), 'utf8');
  const sessionSource = fs.readFileSync(path.resolve(__dirname, '../src/lib/conversation/ConversationSession.ts'), 'utf8');
  const useSessionSource = fs.readFileSync(path.resolve(__dirname, '../src/hooks/useConversationSession.ts'), 'utf8');
  assert.match(companionPage, /emotion=\{chat\.currentEmotion\} emotionIntensity=\{chat\.currentIntensity\} conversationState=\{chat\.conversationState\}/);
  assert.match(companionScene, /VRMAvatarRenderer modelUrl=\{modelUrl\} emotion=\{emotion\} emotionIntensity=\{emotionIntensity\} conversationState=\{conversationState\}/);
  assert.match(companionPage, /subtitleUpdating=\{chat\.pending\}/);
  assert.match(companionPage, /useAvatarPreference\(user\?\.uid, authLoading\)/);
  assert.match(companionPage, /Your saved Koi fox choice is preserved/);
  assert.match(chatPage, /useAvatarPreference\(user\?\.uid, authLoading\)/);
  assert.match(avatarPreference, /imageSrc: '\/Female\.png', modelUrl: '\/models\/koi-female\.vrm'/);
  assert.match(avatarPreference, /imageSrc: '\/Male\.png', modelUrl: '\/models\/koi-male\.vrm'/);
  assert.match(avatarPreference, /imageSrc: null, modelUrl: null/);
  assert.match(fs.readFileSync(path.resolve(__dirname, '../src/lib/db.ts'), 'utf8'), /avatar\?: 'female_human' \| 'male_human' \| 'fox'/);
  assert.match(sessionSource, /abort\.signal\.aborted \|\| version !== this\.version \|\| !this\.active \|\| this\.disposed/);
  assert.match(serviceSource, /const response = await postJsonChat[\s\S]*?await saveMessage\(\{ id: options\.assistantMessageId/);
  assert.match(sessionSource, /exercise_state: this\.snapshot\.exerciseState/);
  assert.match(useSessionSource, /new ConversationSession\(/);
  assert.equal((useSessionSource.match(/new ConversationSession\(/g) ?? []).length, 1);
  assert.doesNotMatch(`${serviceSource}\n${companionPage}`, /\/api\/v1\/crisis/);
  checks.push('authenticated companion route forwards live emotion/intensity/state props into the existing VRM renderer');
  checks.push('one production session/service, stale-event guards, success-only assistant persistence and no crisis endpoint call');
  console.log(JSON.stringify({ passed: true, checks, scope: 'Stage A pure/in-memory tests only; no Firebase tokens or live backend' }, null, 2));
})().catch((error) => { console.error(error); process.exitCode = 1; });
