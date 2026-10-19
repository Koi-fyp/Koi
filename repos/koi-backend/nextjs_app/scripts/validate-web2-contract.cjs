const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { validate } = require('next/dist/compiled/schema-utils3');
const root = path.join(__dirname, '..', 'contracts', 'v0.5.1');
const read = file => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));
const schema = read('contracts.schema.json'), base = require('../contracts/v0.5.0/contracts.schema.json'), api = read('openapi.json'), fixtures = read('fixtures.json');
for (const [name, value] of Object.entries(base.definitions)) assert.deepEqual(schema.definitions[name], value, `Frozen definition drift: ${name}`);
const walk = (value, visit) => { if (!value || typeof value !== 'object') return; visit(value); Object.values(value).forEach(v => walk(v, visit)); };
walk(schema, node => { if (node.$ref) assert(schema.definitions[node.$ref.split('/').pop()], `Unresolved ${node.$ref}`); });
const ids = new Set(); for (const methods of Object.values(api.paths)) for (const op of Object.values(methods)) { assert(!ids.has(op.operationId)); ids.add(op.operationId); assert(op['x-required-capability']); }
function check(name, value) { validate({ $schema: schema.$schema, definitions: schema.definitions, type: 'object', properties: { value: { $ref: `#/definitions/${name}` } }, required: ['value'], additionalProperties: false }, { value }); }
for (const sample of fixtures.valid) check(sample.schema, sample.value);
for (const sample of fixtures.invalid) assert.throws(() => check(sample.schema, sample.value), undefined, sample.name);
const seen = new Set();
function boundary(name) {
  assert(!/^(Professional|ValidatedScore|Review|AIJob|SubmissionWorkspace)/.test(name)); if (seen.has(name)) return; seen.add(name);
  walk(schema.definitions[name], node => { if (node.$ref) boundary(node.$ref.split('/').pop()); if (node.properties) for (const key of Object.keys(node.properties)) assert(!/^(scores?|validated_scores|interpretation|evaluation|evaluation_id|job_id|job_status|feedback|review_status|conclusion|trend)$/.test(key), `${name}.${key}`); });
}
['PatientAssignmentListDTO', 'PatientAssignmentDetailDTO', 'PatientSubmitAckDTO', 'AutosaveAckDTO', 'CapabilitiesDTO', 'NotificationListDTO', 'ErrorDTO'].forEach(boundary);
if (fs.existsSync(path.join(root, 'freeze-manifest.json'))) for (const [file, digest] of Object.entries(read('freeze-manifest.json').sha256)) assert.equal(createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex'), digest, file);
process.stdout.write(`WEB-2 contracts PASS: ${Object.keys(schema.definitions).length} definitions; ${ids.size} operations; ${fixtures.valid.length} valid / ${fixtures.invalid.length} rejected fixtures; ${seen.size} patient-reachable definitions; original 0.5.0 definitions unchanged.\n`);
