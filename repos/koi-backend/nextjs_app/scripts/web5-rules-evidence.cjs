// Local evidence assembly only. Does not deploy or write Firebase records.
const fs=require('node:fs');
const {validateEvidence}=require('../src/lib/platform/server/production-evidence.cjs');
function assemble(snapshot,tests){
  const result={project:snapshot.project,live_release_verified:snapshot.live_release_verified,ruleset_name:snapshot.ruleset_name,rules_sha256:snapshot.rules_sha256,password_provider_enabled:snapshot.password_provider_enabled,verified_at:snapshot.inspected_at,rules_tests:tests};
  return validateEvidence(result,'koi-companion-fyp',snapshot.rules_sha256);
}
if(require.main===module){try{const [snapshot,tests,destination]=process.argv.slice(2);if(!destination||fs.existsSync(destination))throw new Error('Choose a new private output');const result=assemble(JSON.parse(fs.readFileSync(snapshot,'utf8')),JSON.parse(fs.readFileSync(tests,'utf8')));fs.writeFileSync(destination,JSON.stringify(result,null,2)+'\n',{flag:'wx'});console.log('Matched live release and full-policy denial evidence. No cloud writes.');}catch{console.error('Evidence assembly refused: live source, tested hash, project or freshness did not match.');process.exitCode=1;}}
module.exports={assemble};
