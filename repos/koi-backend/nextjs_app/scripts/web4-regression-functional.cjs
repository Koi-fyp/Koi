// Run unchanged earlier harnesses with WEB-4 evidence destinations, preserving old reports.
const fs = require('node:fs'), path = require('node:path'), Module = require('node:module');
require('./koi-demo-guard.cjs').guard();
const batch = process.argv[2];
if (!['1', '2', '3'].includes(batch)) throw new Error('Expected batch 1, 2 or 3');
const filename = path.join(__dirname, `web${batch}-emulator-functional.cjs`);
let source = fs.readFileSync(filename, 'utf8');
const original = `review/web-${batch}/evidence`, destination = `review/web-4/evidence/web-${batch}-regression`;
if (!source.includes(original)) throw new Error('Harness evidence path changed; review before running');
source = source.replaceAll(original, destination);
// WEB-3 made discoverable/accepting profiles a prerequisite for new applications.
// Supply that prerequisite to the old WEB-2 fixture through its real owner route.
if (batch === '2') {
  const anchor = 'const otherOrg = await ok';
  if (!source.includes(anchor)) throw new Error('WEB-2 fixture changed; review before running');
  source = source.replace(anchor, "await ok('/api/v1/professional/profile', 'PUT', { organization_id: org.id, display_name: 'Fictional regression expert', bio: 'Fictional regression practice', discoverable: true, accepting_new_patients: true, expected_revision: 0 });\n  " + anchor);
}
const harness = new Module(filename, module); harness.filename = filename; harness.paths = module.paths;
harness._compile(source, filename);
