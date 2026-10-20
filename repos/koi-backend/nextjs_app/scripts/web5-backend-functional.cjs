// Actual local Auth + Firestore + Next HTTP integration. No browser, companion,
// crisis, worker, provider, health check or GPU route is used.
const assert=require('node:assert/strict'),fs=require('node:fs');
const {randomUUID}=require('node:crypto');
const {guard}=require('./web5-rules-security.cjs');
const {provision,identities,hash}=require('./web5-provision-core.cjs');
async function main(){
  guard();const output='review/web-5/evidence/backend-functional.json';if(fs.existsSync(output))throw new Error('Preserve completed test evidence');
  const {auth,db,config}=require('../src/lib/platform/server/admin-config.cjs').getPlatformAdmin();
  assert.equal(config.project,'demo-koi-web5-local');
  const {CommunityService,firestoreStore}=require('./web5-load-platform.cjs').loadPlatform();
  const suffix=randomUUID().replaceAll('-','').slice(0,10),operator=`web5_operator_${suffix}`;
  await auth.createUser({uid:operator,displayName:'Fictional offline operator'});
  const password=randomUUID()+'-Fixture',secrets={psychologist:password,general:password,patient:password};
  const options={auth,store:firestoreStore(db),serviceFactory:store=>new CommunityService(store,config.cursorKey),actorUid:operator,serviceIdentity:'restricted-offline-fixture@koi-companion-fyp.iam.gserviceaccount.com',passwords:secrets};
  const checks=[],pass=name=>{checks.push(name);console.log('PASS '+name);};
  const a=await provision({...options,runId:`exam_a_${suffix}`}),b=await provision({...options,runId:`exam_b_${suffix}`});
  const replay=await provision({...options,runId:a.run_id});assert.deepEqual(replay,a);
  const rows=(await db.collection('demo_provision_records').where('run_id','==',a.run_id).get()).docs;
  assert(rows.length>30);for(const row of rows){const record=row.data(),value=(await db.doc(record.path).get()).data();assert.equal(hash(value),record.content_sha256);}
  pass('Actual restricted provisioning services, immutable fixture/review records, complete ledger and idempotent replay');
  const tokens={};
  for(const [key,identity] of Object.entries({pro:a.identities.psychologist,patient:a.identities.patient,general:a.identities.general,other:b.identities.patient,otherPro:b.identities.psychologist})){
    const response=await fetch('http://127.0.0.1:5499/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-platform-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:identity.email,password,returnSecureToken:true})});assert.equal(response.status,200);tokens[key]=(await response.json()).idToken;
  }
  const anonResponse=await fetch('http://127.0.0.1:5499/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-platform-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({returnSecureToken:true})});const anon=await anonResponse.json();tokens.anonymous=anon.idToken;
  const api=async(path,role='patient',method='GET',body,key=randomUUID())=>{
    assert(path.startsWith('/api/v1/')&&!/^\/api\/v1\/(chat|crisis|ai)(?:\/|$)/.test(path));
    const response=await fetch('http://127.0.0.1:3207'+path,{method,headers:{Authorization:`Bearer ${tokens[role]}`,'Content-Type':'application/json','Idempotency-Key':key},...(body?{body:JSON.stringify(body)}:{})});return{status:response.status,data:await response.json()};
  };
  const caps=await api('/api/v1/me/capabilities','pro');assert.equal(caps.status,200);assert(caps.data.capabilities.professional_workspace);
  assert.equal((await api('/api/v1/experts','general')).status,200);assert.equal((await api('/api/v1/experts','anonymous')).status,403);
  // isAnonymous=false, a password provider or users/{uid}.role never grants registration.
  const unregistered=await auth.createUser({uid:`web5_unregistered_${suffix}`,email:`web5-unregistered-${suffix}@example.invalid`,password});
  const signIn=await fetch('http://127.0.0.1:5499/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-platform-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:unregistered.email,password,returnSecureToken:true})});tokens.unregistered=(await signIn.json()).idToken;
  await db.collection('users').doc(unregistered.uid).create({role:'psychologist',verified:true,general_access:true});
  assert.equal((await api('/api/v1/experts','unregistered')).status,403);
  assert.equal((await api('/api/v1/me/capabilities','unregistered')).data.account_state,'unregistered');
  pass('Real ID-token validation, authoritative capabilities, anonymous/password-only directory denial and ignored profile role spoofing');
  const privatePaths=[`/api/v1/professional/evaluations/${a.evaluation_id}`,`/api/v1/professional/submissions/${a.submission_id}`,`/api/v1/professional/submissions/${a.submission_id}/workspace`,`/api/v1/professional/analytics?organization_id=${a.organization_id}`,`/api/v1/professional/submissions?organization_id=${a.organization_id}`,`/api/v1/professional/evaluations/${a.evaluation_id}/reviews`,`/api/v1/professional/evaluations/${a.evaluation_id}/review-decisions`];
  for(const role of ['patient','general','anonymous'])for(const path of privatePaths)assert.equal((await api(path,role)).status,403,role+' '+path);
  assert.equal((await api(`/api/v1/patient/assignments/${a.assignments.open}`,'other')).status,404);
  assert.equal((await api(`/api/v1/professional/submissions/${a.submission_id}/workspace`,'otherPro')).status,404);
  pass('Patient/General/anonymous professional-result denial and cross-patient/cross-organization isolation');
  let detail=await api(`/api/v1/patient/assignments/${a.assignments.open}`);assert.equal(detail.status,200);
  const attempt=detail.data.attempt,answers=[{question_id:'reflection',type:'short_text',value:'Fictional offline HTTP response'},{question_id:'picture',type:'image_single_choice',value:'shape_1'}];
  assert.equal((await api(`/api/v1/patient/attempts/${attempt.id}`,'patient','PATCH',{expected_revision:attempt.revision,answers,version_id:'forged'})).status,422);
  assert.equal((await api(`/api/v1/patient/attempts/${attempt.id}`,'patient','PATCH',{expected_revision:attempt.revision,answers})).status,200);
  assert.equal((await api(`/api/v1/patient/attempts/${attempt.id}`,'patient','PATCH',{expected_revision:attempt.revision,answers})).status,409);
  detail=await api(`/api/v1/patient/assignments/${a.assignments.open}`);assert.deepEqual(detail.data.attempt.answers,answers);
  const before=(await db.collection('ai_jobs').where('job.organization_id','==',a.organization_id).get()).size;
  const submissions=await Promise.all([api(`/api/v1/patient/attempts/${attempt.id}/submit`,'patient','POST',{expected_revision:detail.data.attempt.revision}),api(`/api/v1/patient/attempts/${attempt.id}/submit`,'patient','POST',{expected_revision:detail.data.attempt.revision})]);
  for(const response of submissions){assert.equal(response.status,200);assert.deepEqual(Object.keys(response.data).sort(),['assignment_id','attempt_id','status','submitted_at']);}
  assert.deepEqual(submissions[0].data,submissions[1].data);
  assert.equal((await db.collection('ai_jobs').where('job.organization_id','==',a.organization_id).get()).size,before+1);
  assert.equal((await api(`/api/v1/patient/attempts/${attempt.id}`,'patient','PATCH',{expected_revision:detail.data.attempt.revision,answers})).status,409);
  pass('Pinned schemas, revision autosave/resume, multi-device atomic duplicate submission, immutable answers and one queued job without inference');
  const recursive=value=>{if(value&&typeof value==='object')for(const[k,v]of Object.entries(value)){assert(!/^(evaluation|evaluations|score|scores|validated_scores|interpretation|review|reviews|job|job_status|trend|feedback)$/.test(k),'Patient result leak: '+k);recursive(v);}};
  for(const path of ['/api/v1/patient/assignments',`/api/v1/patient/assignments/${a.assignments.open}`,'/api/v1/notifications'])recursive((await api(path)).data);
  const thread=await api('/api/v1/messages','patient','POST',{relationship_id:a.relationship_id,body:'Fictional human-only examiner message'});assert.equal(thread.status,201);
  assert.equal((await api(`/api/v1/relationships/${a.relationship_id}/messages`,'other')).status,404);
  const appointment=await api('/api/v1/appointments','patient','POST',{relationship_id:a.relationship_id});assert.equal(appointment.status,201);
  const proposal=await api(`/api/v1/appointments/${appointment.data.id}/transition`,'pro','POST',{expected_revision:1,to_state:'proposed',starts_at:new Date(Date.now()+86400000).toISOString(),ends_at:new Date(Date.now()+90000000).toISOString()});assert.equal(proposal.status,200);
  assert.equal((await api(`/api/v1/appointments/${appointment.data.id}/transition`,'patient','POST',{expected_revision:2,to_state:'confirmed'})).status,200);
  assert.equal((await api('/api/v1/notifications')).status,200);assert.equal((await api(`/api/v1/professional/analytics?organization_id=${a.organization_id}`,'pro')).status,200);
  pass('Safe patient DTO traversal, human messages, appointment transitions, in-app notifications and actual-data professional analytics');
  assert.equal((await api(`/api/v1/professional/patient-relationships/${a.relationship_id}/close`,'pro','POST',{expected_revision:1})).status,200);
  assert.equal((await api(`/api/v1/patient/assignments/${a.assignments.open}`)).status,403);
  assert.equal((await api(`/api/v1/relationships/${a.relationship_id}/messages`)).status,403);
  await auth.revokeRefreshTokens(unregistered.uid);await auth.updateUser(unregistered.uid,{disabled:true});assert.equal((await api('/api/v1/me/capabilities','unregistered')).status,401);
  pass('Relationship revocation and disabled identity deny subsequent real HTTP access');
  fs.writeFileSync(output,JSON.stringify({passed:true,checks,real:['Auth emulator','Firestore transactions and complete policy','Next production HTTP routes'],live_firebase_writes:0,companion_requests:0,crisis_requests:0,paid_provider_requests:0,ai_jobs:'Queued only; no worker invoked',fixture_ledger_records:rows.length},null,2)+'\n');
}
main().catch(e=>{console.error(`Offline backend integration failed: ${e.message.slice(0,400)}`);process.exitCode=1;});
