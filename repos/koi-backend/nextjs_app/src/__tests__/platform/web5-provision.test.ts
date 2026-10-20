/** @jest-environment node */
jest.mock('server-only', () => ({}), { virtual: true });
import { MemoryPlatformStore } from '../../../test/platform-memory';
import { CommunityService } from '@/lib/platform/server/community';
const { provision, identities, trackedStore, hash }=require('../../../scripts/web5-provision-core.cjs');
const runId='exam_test_001', serviceIdentity='restricted-demo@koi-companion-fyp.iam.gserviceaccount.com';
function setup() {
  const store=new MemoryPlatformStore(), users=new Map<string,any>([['operator',{uid:'operator',disabled:false}]]);
  const absent=()=>{const e:any=new Error('absent');e.code='auth/user-not-found';throw e;};
  const auth={getUser:jest.fn(async(uid:string)=>users.get(uid)??absent()),getUserByEmail:jest.fn(async(email:string)=>[...users.values()].find(u=>u.email===email)??absent()),createUser:jest.fn(async(data:any)=>{const {password,...publicData}=data;const u={...publicData,disabled:false,providerData:[{providerId:'password'}]};users.set(u.uid,u);return u;})};
  const options={auth,store,serviceFactory:(s:any)=>new CommunityService(s,'fixture-secret-'.repeat(4)),runId,actorUid:'operator',serviceIdentity,passwords:{psychologist:'Fictional-test-password-1',general:'Fictional-test-password-2',patient:'Fictional-test-password-3'}};
  return {store,users,auth,options};
}
it('provisions through actual services, captures every created record and replays without resetting accounts',async()=>{
  const {store,auth,options}=setup(), result=await provision(options), roles=identities(runId);
  expect(result.status).toBe('complete');expect(auth.createUser).toHaveBeenCalledTimes(3);
  const service=new CommunityService(store,'fixture-secret-'.repeat(4)), patient={uid:roles.patient.uid,authTime:Date.now()/1000};
  const open=await service.patientDetail(patient,result.assignments.open);expect('attempt' in open && open.attempt.status).toBe('not_started');
  const submitted=await service.patientDetail(patient,result.assignments.submitted);expect('acknowledgement' in submitted && submitted.acknowledgement.status).toBe('submitted');
  expect(JSON.stringify(submitted)).not.toMatch(/evaluation|interpretation|validated_scores|review_revision|job/);
  await expect(service.workspace(patient,result.submission_id)).rejects.toMatchObject({status:403});
  const records=[...store.data.entries()].filter(([key])=>!key.startsWith('demo_provision_'));
  for(const [key,value] of records)expect(store.read('demo_provision_records',hash([runId,...key.split('/')]))).toMatchObject({path:key,content_sha256:hash(value),created_by_run:true});
  const count=store.data.size, writes=store.writes.length;
  expect(await provision(options)).toEqual(result);expect(store.data.size).toBe(count);expect(store.writes.length).toBe(writes);expect(auth.createUser).toHaveBeenCalledTimes(3);
});
it('refuses pre-existing identities and unowned records without overwriting them',async()=>{
  const {store,users,auth,options}=setup(), identity=identities(runId).patient;
  users.set('existing-real-user',{uid:'existing-real-user',email:identity.email});
  await expect(provision(options)).rejects.toThrow('Existing Auth identity refused');expect(auth.createUser).not.toHaveBeenCalled();expect(store.data.size).toBe(0);
  store.seed('accounts','real',{private:'original'});
  await expect(trackedStore(store,runId).transaction(async(tx:any)=>tx.set('accounts','real',{private:'changed'}))).rejects.toThrow('unowned');
  expect(store.read('accounts','real')).toEqual({private:'original'});
});
it('journals partial runs and resumes safely without re-creating Auth users',async()=>{
  const {options,auth,store}=setup();
  const original=options.serviceFactory;options.serviceFactory=(s:any)=>{const service=original(s);service.createDraft=async()=>{throw new Error('fixture interruption');};return service;};
  await expect(provision(options)).rejects.toThrow('fixture interruption');
  expect(store.read('demo_provision_runs',runId).status).toBe('started');
  options.serviceFactory=original;expect((await provision(options)).status).toBe('complete');expect(auth.createUser).toHaveBeenCalledTimes(3);
});
