const mockApp={},mockDoc=jest.fn(),mockGet=jest.fn(),mockSet=jest.fn();
let mockOwner:string|null='synthetic-a';
jest.mock('@/lib/firebase',()=>({auth:{app:mockApp,get currentUser(){return mockOwner?{uid:mockOwner}:null;}},firestore:{app:mockApp}}));
jest.mock('firebase/firestore',()=>({doc:(...args:unknown[])=>mockDoc(...args),getDocFromServer:(...args:unknown[])=>mockGet(...args),setDoc:(...args:unknown[])=>mockSet(...args)}));
import {readOwnedAccountPreferences,writeOwnedAccountPreferences} from '@/lib/preferences/accountPreferenceSync.proposed';
const signal=()=>new AbortController().signal;
beforeEach(()=>{mockOwner='synthetic-a';mockDoc.mockReset().mockImplementation((_db,collection,uid)=>`${collection}/${uid}`);mockGet.mockReset();mockSet.mockReset().mockResolvedValue(undefined);});
it('writes only owner profile leaves using existing merge path and acknowledges only SDK receipt',async()=>{
  const fields={companion:'aisha' as const,avatar:'female_human' as const,language:'ur' as const};
  expect(await writeOwnedAccountPreferences('synthetic-a',fields,signal())).toMatchObject({status:'server-acknowledged',ownerUid:'synthetic-a'});
  expect(mockSet).toHaveBeenCalledWith('users/synthetic-a',{profile:fields},{merge:true});
  expect(mockGet).not.toHaveBeenCalled();
});
it('permits a language-only patch and preserves legacy fox on reads without writing',async()=>{
  await writeOwnedAccountPreferences('synthetic-a',{language:'en'},signal());
  mockGet.mockResolvedValue({exists:()=>true,data:()=>({profile:{avatar:'fox',unrelated:'synthetic excluded'},public_crypto_metadata:{salt:'excluded'}})});
  expect(await readOwnedAccountPreferences('synthetic-a',signal())).toEqual({status:'server-read',ownerUid:'synthetic-a',preferences:{avatar:'fox'}});
  expect(mockSet).toHaveBeenCalledTimes(1);
});
it.each([null,'synthetic-b'])('refuses missing/foreign auth before network: %s',async owner=>{
  mockOwner=owner;await expect(writeOwnedAccountPreferences('synthetic-a',{language:'ur'},signal())).rejects.toMatchObject({reason:'owner-changed'});expect(mockSet).not.toHaveBeenCalled();
});
it('rejects aborted calls without network and late owner changes without showing current-account success',async()=>{
  const controller=new AbortController();controller.abort();await expect(readOwnedAccountPreferences('synthetic-a',controller.signal)).rejects.toMatchObject({reason:'cancelled'});expect(mockGet).not.toHaveBeenCalled();
  mockSet.mockImplementation(async()=>{mockOwner='synthetic-b';});await expect(writeOwnedAccountPreferences('synthetic-a',{language:'ur'},signal())).rejects.toMatchObject({reason:'owner-changed'});
});
it('rejects an owner that cannot be mapped to one document path segment',async()=>{
  mockOwner='synthetic/invalid';await expect(writeOwnedAccountPreferences(mockOwner,{language:'ur'},signal())).rejects.toMatchObject({reason:'configuration'});expect(mockDoc).not.toHaveBeenCalled();
});
it.each([{companion:'aisha',avatar:'male_human'},{avatar:'fox'},{language:'unsupported'},{notificationTime:'25:99'},{},{onboarding_complete:true}])('rejects invalid/extra fields before writing',async fields=>{
  await expect(writeOwnedAccountPreferences('synthetic-a',fields as never,signal())).rejects.toMatchObject({reason:'invalid-profile'});expect(mockSet).not.toHaveBeenCalled();
});
it('does not turn permission failures into success or expose arbitrary SDK text',async()=>{
  mockSet.mockRejectedValue({code:'permission-denied',message:'synthetic sensitive content'});
  await expect(writeOwnedAccountPreferences('synthetic-a',{language:'ur'},signal())).rejects.toMatchObject({reason:'permission-denied',message:'Account preference sync failed: permission-denied.'});
});
it('reads only exact owner document from server and never returns unrelated document fields',async()=>{
  mockGet.mockResolvedValue({exists:()=>true,data:()=>({profile:{companion:'raza',avatar:'male_human',language:'ur'},unrelated:'not returned'})});
  expect(await readOwnedAccountPreferences('synthetic-a',signal())).toMatchObject({preferences:{companion:'raza',avatar:'male_human',language:'ur'}});expect(mockGet).toHaveBeenCalledWith('users/synthetic-a');expect(mockSet).not.toHaveBeenCalled();
});
it('handles missing document/profile separately from malformed remote choices',async()=>{
  mockGet.mockResolvedValueOnce({exists:()=>false});expect(await readOwnedAccountPreferences('synthetic-a',signal())).toMatchObject({status:'missing'});
  mockGet.mockResolvedValueOnce({exists:()=>true,data:()=>({})});expect(await readOwnedAccountPreferences('synthetic-a',signal())).toMatchObject({status:'no-profile'});
  mockGet.mockResolvedValueOnce({exists:()=>true,data:()=>({profile:{companion:'koi',avatar:'male_human'}})});await expect(readOwnedAccountPreferences('synthetic-a',signal())).rejects.toMatchObject({reason:'invalid-profile'});
});
