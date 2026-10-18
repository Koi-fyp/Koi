import { preferenceSyncFailure } from '@/lib/preferences/syncFailure';
it('separates access denial from service failure and does not echo potentially sensitive SDK messages',()=>{
  expect(preferenceSyncFailure({code:'permission-denied',message:'synthetic sensitive payload'})).toMatch(/was denied/);
  expect(preferenceSyncFailure({code:'unavailable'})).toMatch(/service is unavailable/);
  expect(preferenceSyncFailure({code:'unauthenticated'})).toMatch(/could not authenticate/);
  expect(preferenceSyncFailure(new Error('synthetic sensitive payload'))).not.toContain('synthetic sensitive payload');
  expect(preferenceSyncFailure({code:'unrecognized'})).toMatch(/cause has not been verified/);
});
