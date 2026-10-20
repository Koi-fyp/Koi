const fs = require('node:fs');
const { ROOTS } = require('../../../../scripts/web5-artifacts.cjs');
function validateEvidence(evidence, project, digest, now = Date.now()) {
  if (project !== 'koi-companion-fyp' || evidence?.project !== project || evidence?.live_release_verified !== true || evidence.rules_sha256 !== digest || evidence.rules_tests?.source_sha256 !== digest || evidence.rules_tests?.passed !== true || ROOTS.some(c => !evidence.rules_tests.denied_roots?.includes(c)) || !String(evidence.ruleset_name).startsWith(`projects/${project}/rulesets/`)) throw new Error('Verified live platform-denial evidence is required');
  const age = now - Date.parse(evidence.verified_at);
  if (!Number.isFinite(age) || age < -300000 || age > 86400000) throw new Error('Rules evidence must be refreshed within 24 hours');
  return evidence;
}
function readEvidence(file, project, digest) {
  if (!file) throw new Error('KOI_PLATFORM_RULES_EVIDENCE_PATH is required');
  return validateEvidence(JSON.parse(fs.readFileSync(file, 'utf8')), project, digest);
}
module.exports = { validateEvidence, readEvidence };
