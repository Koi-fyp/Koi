// Local full-policy test only: exact loopback emulators, no cloud credential, no AI.
const assert=require('node:assert/strict'),fs=require('node:fs');
const {randomUUID}=require('node:crypto');
const {ROOTS,sha}=require('./web5-artifacts.cjs');
function guard(){
  if(process.env.KOI_PLATFORM_FIREBASE_PROJECT_ID!=='demo-koi-web5-local'||process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:5480'||process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:5499'||!process.env.NODE_OPTIONS?.includes('web5-network-guard.cjs')||process.env.FIREBASE_ADMIN_SDK||process.env.GOOGLE_APPLICATION_CREDENTIALS)throw new Error('Isolated WEB-5 offline emulators required');
}
async function main(){
  guard();const source=process.argv[2]||'dev/web5-reference/firestore.rules', output=process.argv[3]||'review/web-5/evidence/rules-security.json';
  if(fs.existsSync(output))throw new Error('Preserve existing evidence; choose a new output');
  const id=randomUUID().slice(0,8), principals=[{role:'unauthenticated'}];
  for(const role of ['anonymous','general','patient','psychologist']){
    const response=await fetch('http://127.0.0.1:5499/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-platform-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({returnSecureToken:true,...(role==='anonymous'?{}:{email:`web5-${role}-${id}@example.invalid`,password:randomUUID()})})});
    assert.equal(response.status,200);const identity=await response.json();principals.push({role,token:identity.idToken,uid:identity.localId});
  }
  const root='http://127.0.0.1:5480/v1/projects/demo-koi-web5-local/databases/(default)/documents';let denials=0,legacy=0;
  for(const p of principals){
    const headers={'Content-Type':'application/json',...(p.token?{Authorization:`Bearer ${p.token}`}:{})};
    for(const collection of ROOTS){
      assert.equal((await fetch(`${root}/${collection}/forged`,{headers})).status,403,`${p.role} ${collection} get`);denials++;
      assert.equal((await fetch(`${root}/${collection}/forged`,{method:'PATCH',headers,body:JSON.stringify({fields:{role:{stringValue:'psychologist'},scores:{stringValue:'private canary'}}})})).status,403);denials++;
      for(const allDescendants of [false,true]){assert.equal((await fetch(`${root}:runQuery`,{method:'POST',headers,body:JSON.stringify({structuredQuery:{from:[{collectionId:collection,allDescendants}]}})})).status,403);denials++;}
    }
    if(p.uid){
      const own=`${root}/users/${p.uid}`,foreign=`${root}/users/someone_else`;
      assert.equal((await fetch(own,{method:'PATCH',headers,body:JSON.stringify({fields:{fictional:{booleanValue:true}}})})).status,200);legacy++;
      assert.equal((await fetch(own,{headers})).status,200);legacy++;
      assert.equal((await fetch(foreign,{headers})).status,403);legacy++;
      assert.equal((await fetch(foreign,{method:'PATCH',headers,body:JSON.stringify({fields:{fictional:{booleanValue:true}}})})).status,403);legacy++;
      assert.equal((await fetch(`${root}/users/${p.uid}/conversations/c1/messages/m1`,{method:'PATCH',headers,body:JSON.stringify({fields:{content:{stringValue:'not-ciphertext'}}})})).status,403);legacy++;
      for(const collection of ['conversations','mood_entries','wellness_progress','tasks']){
        assert.equal((await fetch(`${root}/${collection}/${p.uid}`,{method:'PATCH',headers,body:JSON.stringify({fields:{fictional:{booleanValue:true}}})})).status,403,`${p.role} legacy ${collection}`);legacy++;
      }
    }
  }
  const result={passed:true,source_sha256:sha(fs.readFileSync(source)),denied_roots:ROOTS,direct_denials:denials,legacy_preservation_assertions:legacy,principals:principals.map(p=>p.role),cloud_requests:0,ai_requests:0,scope:'Live published rules (captured 2026-10-20): users/{uid} owner access allowed, malformed nested message denied, legacy collections denied, all platform roots denied. Not a claim about rules other than the tested file.'};
  fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n');console.log(`PASS ${denials} platform denials and ${legacy} original-owner policy assertions`);
}
if(require.main===module)main().catch(e=>{console.error(`Local rules test failed: ${e.message.slice(0,200)}`);process.exitCode=1;});
module.exports={guard};