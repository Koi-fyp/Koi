/* REVIEW TEST: local Firestore emulator only. Does not deploy or connect to a live project. */
const {test,before,after}=require('node:test');
const fs=require('node:fs'),path=require('node:path');
const host=process.env.FIRESTORE_EMULATOR_HOST;
if(!host||!/^127\.0\.0\.1:\d+$/.test(host)){
  process.stderr.write('NOT RUN: set FIRESTORE_EMULATOR_HOST to the reviewed local emulator on 127.0.0.1.\n');process.exit(2);
}
let rules,sdk;
try{rules=require('@firebase/rules-unit-testing');sdk=require('firebase/firestore');}
catch{process.stderr.write('NOT RUN: reviewed rules-unit-testing dependency is not installed.\n');process.exit(2);}
const [address,port]=host.split(':');let environment;
const proposal=process.argv.includes('--proposal');
const rulesFile=proposal?path.resolve(__dirname,'firestore.user-preferences.proposed.rules'):path.resolve(__dirname,'../../firestore.rules');
before(async()=>{environment=await rules.initializeTestEnvironment({projectId:'demo-koi-preference-review',firestore:{host:address,port:Number(port),rules:fs.readFileSync(rulesFile,'utf8')}});});
after(async()=>{await environment?.cleanup();});
const fields={profile:{companion:'aisha',avatar:'female_human',language:'ur',notificationTime:'20:00'},onboarding_complete:true};
test('current local rule: authenticated anonymous owner can create and merge own onboarding profile',async()=>{
  const db=environment.authenticatedContext('synthetic-owner',{firebase:{sign_in_provider:'anonymous'}}).firestore();
  await rules.assertSucceeds(sdk.setDoc(sdk.doc(db,'users','synthetic-owner'),fields,{merge:true}));
  await rules.assertSucceeds(sdk.getDoc(sdk.doc(db,'users','synthetic-owner')));
  await rules.assertSucceeds(sdk.setDoc(sdk.doc(db,'users','synthetic-owner'),{profile:{language:'en'}},{merge:true}));
});
test('current local rule: guest and foreign UID cannot write or read another owner document',async()=>{
  const guest=environment.unauthenticatedContext().firestore(),other=environment.authenticatedContext('synthetic-other').firestore();
  for(const db of [guest,other]){
    await rules.assertFails(sdk.getDoc(sdk.doc(db,'users','synthetic-owner')));
    await rules.assertFails(sdk.setDoc(sdk.doc(db,'users','synthetic-owner'),fields,{merge:true}));
  }
});
test('current local rule: collection-wide user listing is not an owner-scoped document read',async()=>{
  const db=environment.authenticatedContext('synthetic-owner').firestore();await rules.assertFails(sdk.getDocs(sdk.collection(db,'users')));
});
test('proposal: owner crypto salt metadata merge is allowed but privileged fields, document delete and other collections stay denied',{skip:!proposal},async()=>{
  const db=environment.authenticatedContext('synthetic-owner').firestore();
  await rules.assertSucceeds(sdk.setDoc(sdk.doc(db,'users','synthetic-owner'),{public_crypto_metadata:{salt:'synthetic-public-salt'}},{merge:true}));
  await rules.assertFails(sdk.setDoc(sdk.doc(db,'users','synthetic-owner'),{admin:true},{merge:true}));
  await rules.assertFails(sdk.setDoc(sdk.doc(db,'users','synthetic-owner'),{profile:{role:'admin'}},{merge:true}));
  await rules.assertFails(sdk.deleteDoc(sdk.doc(db,'users','synthetic-owner')));
  await rules.assertFails(sdk.setDoc(sdk.doc(db,'mood_entries','synthetic-owner','entries','one'),{rating:5}));
});
