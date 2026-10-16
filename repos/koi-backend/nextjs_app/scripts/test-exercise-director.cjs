const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
require.extensions['.ts'] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, fileName: filename,
}).outputText, filename);

const { BreathingClock, getBreathingFrame, parseBreathingPattern } = require('../src/lib/conversation/exerciseContract.ts');
const root = path.resolve(__dirname, '..');
const component = fs.readFileSync(path.join(root, 'src/components/companion/ExerciseDirector.tsx'), 'utf8');
const css = fs.readFileSync(path.join(root, 'src/components/companion/CompanionScene.module.css'), 'utf8');
const checks = [];

const pattern = parseBreathingPattern({ inhale_s: 4, exhale_s: 6, cycles: 2, cue_audio: ['Breathe in', 'Breathe out'] });
assert.deepEqual(pattern, { inhale_s: 4, exhale_s: 6, cycles: 2, cue_audio: ['Breathe in', 'Breathe out'] });
assert.equal(parseBreathingPattern({ inhale_s: 4, exhale_s: 6, cycles: 2 }), null);
assert.deepEqual(parseBreathingPattern({ inhale_s: 90, exhale_s: 0.5, cycles: 80, cue_audio: [' one ', ' two '] }), {
  inhale_s: 12, exhale_s: 1, cycles: 12, cue_audio: ['one', 'two'],
});
assert.deepEqual(getBreathingFrame(pattern, 0), { phase: 'inhale', cycle: 1, phaseProgress: 0, overallProgress: 0, complete: false });
assert.equal(getBreathingFrame(pattern, 4).phase, 'exhale');
assert.equal(getBreathingFrame(pattern, 10).cycle, 2);
assert.equal(getBreathingFrame(pattern, 20).complete, true);
checks.push('validated server timings/cues, upper bounds, elapsed-time phases, cycles and completion');

// Injected timestamps act as a deterministic fake clock for pause/resume behavior.
const clock = new BreathingClock();
clock.start(1_000);
assert.equal(clock.elapsedAt(3_500), 2.5);
clock.pause(3_500);
assert.equal(clock.elapsedAt(20_000), 2.5);
clock.resume(20_000);
assert.equal(clock.elapsedAt(21_000), 3.5);
clock.pause(21_000);
clock.resume(25_000);
assert.equal(clock.elapsedAt(25_500), 4);
clock.stop();
assert.equal(clock.elapsedAt(30_000), 0);
assert.equal(clock.isRunning(), false);
checks.push('fake-clock pause/resume/stop retains elapsed time without frame-delta accumulation');

assert.match(component, /name === 'stop_breathing'[\s\S]*?setBreathing\(null\)[\s\S]*?playback_stopped/);
assert.match(component, /name === 'pause_breathing'[\s\S]*?action: 'pause'/);
assert.match(component, /onComplete=\{\(\) => \{ activeBreathing\.current = false; onQueueClientEvent\('playback_done'\); \}\}/);
assert.match(component, /aria-valuenow=\{Math\.round\(frame\.overallProgress \* 100\)\}/);
assert.match(component, /KOI decides whether an activity can start/);
assert.match(css, /prefers-reduced-motion: reduce/);
checks.push('urgent stop/pause, exactly-once completion queue, accessible progress and reduced-motion affordance');

console.log(JSON.stringify({ passed: true, checks }, null, 2));
