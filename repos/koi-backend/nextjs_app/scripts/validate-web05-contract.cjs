// Schema and contract checks only. No API handlers, rules, auth, or providers invoked.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { validate } = require('next/dist/compiled/schema-utils3');
const root = path.join(__dirname, '..', 'contracts', 'v0.5.0');
const read = name => JSON.parse(fs.readFileSync(path.join(root, name), 'utf8'));
const schema = read('contracts.schema.json');
const api = read('openapi.json');
const fixtures = read('fixtures.json');
const definitions = schema.definitions;
const fixtureSchemas = new Map();
function fixtureSchema(name) {
  if (!fixtureSchemas.has(name)) fixtureSchemas.set(name, {
    $schema: schema.$schema, definitions, $ref: `#/definitions/${name}`,
  });
  return fixtureSchemas.get(name);
}
function checkRef(ref, file) {
  if (file === 'schema') {
    assert(ref.startsWith('#/definitions/'), `Unexpected schema reference ${ref}`);
    assert(definitions[ref.slice('#/definitions/'.length)], `Unresolved ${ref}`);
  } else if (ref.startsWith('#/components/schemas/')) {
    assert(api.components.schemas[ref.split('/').pop()], `Unresolved ${ref}`);
  } else {
    assert(ref.startsWith('./contracts.schema.json#/definitions/'), `Unexpected API reference ${ref}`);
    assert(definitions[ref.split('/').pop()], `Unresolved ${ref}`);
  }
}
function walk(value, visit) {
  if (!value || typeof value !== 'object') return;
  visit(value);
  Object.values(value).forEach(child => walk(child, visit));
}
walk(schema, value => { if (value.$ref) checkRef(value.$ref, 'schema'); });
walk(api, value => { if (value.$ref) checkRef(value.$ref, 'api'); });
// Compile every definition, even when it has no positive fixture yet.
for (const name of Object.keys(definitions)) {
  try { validate(fixtureSchema(name), null); }
  catch (error) { if (error.name !== 'ValidationError') throw error; }
}
for (const item of fixtures.valid) {
  validate(fixtureSchema(item.schema), item.value);
}
for (const item of fixtures.invalid) {
  let rejected = false;
  try { validate(fixtureSchema(item.schema), item.value); }
  catch (error) { if (error.name !== 'ValidationError') throw error; rejected = true; }
  assert(rejected, `Expected schema rejection: ${item.name}`);
}
// Follow every reachable schema, including nested DTOs: patients must never reach evaluations/jobs/reviews.
const patientRoots = ['PatientAssignmentListDTO', 'PatientAssignmentDetailDTO', 'PatientSubmitAckDTO',
  'AutosaveAckDTO', 'NotificationListDTO', 'CapabilitiesDTO', 'ErrorDTO'];
const forbidden = /^(ProfessionalEvaluationDTO|ValidatedScore|ProfessionalJob.*|AIJobRecord|ReviewRecord.*|ProfessionalAIResultDTO)$/;
const forbiddenFields = /^(score|scores|validated_scores|interpretation|evaluation|evaluation_id|job_id|job_status|feedback|review_status|conclusion|trend)$/;
const seen = new Set();
function patientBoundary(name) {
  assert(!forbidden.test(name), `Patient schema reaches ${name}`);
  if (seen.has(name)) return;
  seen.add(name);
  walk(definitions[name], node => {
    if (node.$ref) patientBoundary(node.$ref.split('/').pop());
    if (node.properties) for (const key of Object.keys(node.properties)) {
      assert(!forbiddenFields.test(key), `Patient field leak: ${name}.${key}`);
    }
  });
}
patientRoots.forEach(patientBoundary);
assert.deepEqual(Object.keys(definitions.PatientSubmitAckDTO.properties).sort(),
  ['assignment_id', 'attempt_id', 'status', 'submitted_at']);
const ids = new Set();
let operations = 0;
for (const [url, methods] of Object.entries(api.paths)) {
  assert(!url.includes('/chat') && !url.includes('/crisis'), 'Existing companion endpoints must remain separate');
  for (const [method, operation] of Object.entries(methods)) {
    operations++;
    assert(operation['x-status'] === 'proposed_not_implemented');
    assert(!ids.has(operation.operationId), 'Duplicate operation ID');
    ids.add(operation.operationId);
    assert(operation['x-required-capability'], 'Missing authorization requirement');
    if (url.startsWith('/api/v1/ai/') || /\/professional\//.test(url)) {
      assert(/verified/.test(operation['x-required-capability']), 'Clinician endpoint missing verified check');
    }
    if (['post', 'put', 'patch', 'delete'].includes(method)) {
      assert(operation.parameters.some(p => p.in === 'header' && p.name === 'Idempotency-Key' && p.required));
    }
    for (const match of url.matchAll(/\{([^}]+)\}/g)) {
      assert(operation.parameters?.some(p => p.in === 'path' && p.name === match[1] && p.required));
    }
  }
}
// If a manifest exists, the frozen bytes must still match.
const manifestPath = path.join(root, 'freeze-manifest.json');
if (fs.existsSync(manifestPath)) {
  const manifest = read('freeze-manifest.json');
  for (const [file, expected] of Object.entries(manifest.sha256)) {
    const actual = crypto.createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex');
    assert.equal(actual, expected, `Frozen file changed without manifest/version review: ${file}`);
  }
}
console.log(JSON.stringify({ passed: true, schemas: Object.keys(definitions).length, operations,
  valid_fixtures: fixtures.valid.length, rejected_fixtures: fixtures.invalid.length,
  patient_boundary_schemas: seen.size,
  scope: 'Draft-07 fixture validation, reference integrity, DTO boundary checks, API metadata and optional freeze hashes; no runtime security tests' }, null, 2));
