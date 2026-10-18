const mockRead=jest.fn(),mockWrite=jest.fn();
let mockOwner='a';
jest.mock('dexie',()=>jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
jest.mock('@/lib/firebase',()=>({auth:{get currentUser(){return mockOwner?{uid:mockOwner}:null;}}}));
jest.mock('@/lib/preferences/accountPreferenceSync.proposed',()=>({readOwnedAccountPreferences:(...args:unknown[])=>mockRead(...args),writeOwnedAccountPreferences:(...args:unknown[])=>mockWrite(...args)}));
import {db} from '@/lib/db';
import {loadUserPreferences,saveUserPreferences,type UserPreferences} from '@/lib/preferences/userPreferences';
import {syncAccountPreferences,accountSyncStatus} from '@/lib/preferences/preferenceSync';
beforeEach(async()=>{mockOwner='a';await db.users.clear();mockRead.mockReset().mockResolvedValue({status:'server-read',preferences:{companion:'aisha',avatar:'female_human',language:'en'}});mockWrite.mockReset().mockResolvedValue({status:'server-acknowledged'});});
it('hydrates only allowlisted account fields without touching unrelated local fields',async()=>{
 await db.users.add({uid:'a',createdAt:'preserved'});await syncAccountPreferences('a');expect(await loadUserPreferences('a')).toMatchObject({companion:'aisha',language:'en',createdAt:'preserved'});expect(mockWrite).not.toHaveBeenCalled();
});
it('persists a local offline edit and flushes it without overwriting with older server data',async()=>{
 Object.defineProperty(navigator,'onLine',{configurable:true,value:false});
 await saveUserPreferences('a',{companion:'raza',avatar:'male_human',language:'ur'});await syncAccountPreferences('a');expect(accountSyncStatus('a')).toBe('offline');
 Object.defineProperty(navigator,'onLine',{configurable:true,value:true});await syncAccountPreferences('a');expect(mockWrite).toHaveBeenCalledWith('a',{companion:'raza',avatar:'male_human',language:'ur'},expect.anything());expect((await loadUserPreferences('a'))?.accountSync?.pending).toEqual({});expect((await loadUserPreferences('a'))?.language).toBe('ur');
});
it('keeps pending changes on permission denial and exposes truthful retry state',async()=>{
 mockWrite.mockRejectedValue({reason:'permission-denied'});await saveUserPreferences('a',{language:'ur'});await syncAccountPreferences('a');expect(accountSyncStatus('a')).toBe('permission-denied');expect((await loadUserPreferences('a'))?.accountSync?.pending.language).toBe('ur');
});
it('ignores late reads after UID switch and never writes another account',async()=>{
 mockRead.mockImplementation(async()=>{mockOwner='b';return {status:'server-read',preferences:{language:'ur'}};});await syncAccountPreferences('a');expect(await loadUserPreferences('a')).toBeNull();expect(await loadUserPreferences('b')).toBeNull();expect(mockWrite).not.toHaveBeenCalled();
});
it('preserves a newer edit made while an earlier revision is awaiting acknowledgement',async()=>{
 await db.users.add({uid:'a',accountSync:{pending:{language:'en'},revision:1,initialized:true}} as UserPreferences);
 let first=true;mockWrite.mockImplementation(async()=>{if(first){first=false;await saveUserPreferences('a',{language:'ur'});}});
 await syncAccountPreferences('a');expect(mockWrite).toHaveBeenCalledTimes(2);expect((await loadUserPreferences('a'))?.language).toBe('ur');expect((await loadUserPreferences('a'))?.accountSync?.pending).toEqual({});
});
it('legacy fox remains fox on first account synchronization',async()=>{
 await db.users.add({uid:'a',avatar:'fox'});await syncAccountPreferences('a');expect(mockWrite).toHaveBeenCalledWith('a',{avatar:'fox',companion:'koi'},expect.anything());
});

it('does not apply a stale read after another tab acknowledges a newer local revision',async()=>{
 await db.users.add({uid:'a',language:'ur',accountSync:{pending:{},revision:1,initialized:true}} as UserPreferences);
 mockRead.mockImplementation(async()=>{const local=await loadUserPreferences('a');await db.users.update(local!.id!,{language:'ur',accountSync:{pending:{},revision:2,initialized:true}} as Partial<UserPreferences>);return {status:'server-read',preferences:{language:'en'}};});
 await syncAccountPreferences('a');expect((await loadUserPreferences('a'))?.language).toBe('ur');expect(mockWrite).not.toHaveBeenCalled();
});
it('canonically hydrates legacy fox without substituting a human or issuing a cloud rewrite',async()=>{
 mockRead.mockResolvedValue({status:'server-read',preferences:{avatar:'fox'}});await syncAccountPreferences('a');expect(await loadUserPreferences('a')).toMatchObject({avatar:'fox',companion:'koi'});expect(mockWrite).not.toHaveBeenCalled();
});
