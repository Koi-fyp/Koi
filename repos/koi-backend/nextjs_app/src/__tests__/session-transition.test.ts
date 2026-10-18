import { transitionOwnedConversation, type OwnedSelection } from '@/lib/history/sessionTransition';
it('requires the joint adapter and refuses streaming transitions before calling it',async()=>{
  const current=()=>({ownerUid:'a',conversationId:'A',pending:false}),signal=new AbortController().signal,transition=jest.fn();
  expect(await transitionOwnedConversation({kind:'new'},{current,signal})).toMatchObject({status:'blocked',reason:'joint-session-adapter-required'});
  expect(await transitionOwnedConversation({kind:'new'},{current:()=>({...current(),pending:true}),signal,adapter:{transition}})).toMatchObject({reason:'reply-in-progress'});
  expect(transition).not.toHaveBeenCalled();
});
it('validates fixture A->B->A receipts; has no completion/reward/key/write dependency',async()=>{
  let selection:OwnedSelection={ownerUid:'a',conversationId:'A',pending:false};
  const transition=jest.fn(async input=>{const previousConversationId=selection.conversationId;selection={...selection,conversationId:input.kind==='new'?'B':input.conversationId};return {...selection,previousConversationId,previousCheckpointed:true as const};});
  const access={current:()=>selection,signal:new AbortController().signal,adapter:{transition}};
  expect(await transitionOwnedConversation({kind:'new'},access)).toMatchObject({status:'selected',conversationId:'B'});
  expect(await transitionOwnedConversation({kind:'resume',conversationId:'A'},access)).toMatchObject({status:'selected',conversationId:'A'});
});
it('rejects late cross-owner and invalid selection receipts, and handles failed/locked adapters without success',async()=>{
  const signal=new AbortController().signal;let owner='a';const current=()=>({ownerUid:owner,conversationId:'A',pending:false});
  expect(await transitionOwnedConversation({kind:'new'},{current,signal,adapter:{transition:async()=>{owner='b';return {ownerUid:'a',conversationId:'B',previousConversationId:'A',previousCheckpointed:true};}}})).toMatchObject({status:'blocked'});
  owner='a';expect(await transitionOwnedConversation({kind:'new'},{current,signal,adapter:{transition:async()=>({ownerUid:'a',conversationId:'A',previousConversationId:'A',previousCheckpointed:true})}})).toMatchObject({reason:'unverified-selection-receipt'});
  expect(await transitionOwnedConversation({kind:'resume',conversationId:'locked'},{current,signal,adapter:{transition:async()=>{throw Error('fixture locked');}}})).toMatchObject({reason:'transition-failed'});
});

it('does not call any adapter after cancellation or without an authenticated selection',async()=>{
  const controller=new AbortController(),transition=jest.fn();controller.abort();
  expect(await transitionOwnedConversation({kind:'new'},{current:()=>({ownerUid:'a',conversationId:'A',pending:false}),signal:controller.signal,adapter:{transition}})).toMatchObject({reason:'cancelled'});
  expect(await transitionOwnedConversation({kind:'new'},{current:()=>null,signal:new AbortController().signal,adapter:{transition}})).toMatchObject({reason:'session-unavailable'});
  expect(transition).not.toHaveBeenCalled();
});
it('keeps the current conversation unchanged and rejects invalid targets without adapter calls',async()=>{
  const transition=jest.fn(),access={current:()=>({ownerUid:'a',conversationId:'A',pending:false}),signal:new AbortController().signal,adapter:{transition}};
  expect(await transitionOwnedConversation({kind:'resume',conversationId:'A'},access)).toEqual({status:'unchanged',conversationId:'A'});
  for(const conversationId of [' ', 'x'.repeat(161)])expect(await transitionOwnedConversation({kind:'resume',conversationId},access)).toMatchObject({reason:'invalid-target'});
  expect(transition).not.toHaveBeenCalled();
});
it('never claims selection when cancellation arrives while an adapter is pending',async()=>{
  const controller=new AbortController();let selection:OwnedSelection={ownerUid:'a',conversationId:'A',pending:false};
  const transition=jest.fn(async()=>{controller.abort();selection={...selection,conversationId:'B'};return {ownerUid:'a',previousConversationId:'A',conversationId:'B',previousCheckpointed:true as const};});
  expect(await transitionOwnedConversation({kind:'new'},{current:()=>selection,signal:controller.signal,adapter:{transition}})).toMatchObject({status:'blocked',reason:'owner-changed-or-cancelled'});
  // A cancellation result is not a claim that the producer rolled back after its commit point.
  expect(selection.conversationId).toBe('B');
});
it.each(['foreign-owner','wrong-previous','missing-checkpoint','wrong-published','wrong-resume-target'])('rejects %s receipt without reporting success',async problem=>{
  const current=()=>({ownerUid:'a',conversationId:['wrong-published','wrong-resume-target'].includes(problem)?'C':'B',pending:false});
  let called=false;
  const transition=jest.fn(async()=>{called=true;return {ownerUid:problem==='foreign-owner'?'b':'a',previousConversationId:problem==='wrong-previous'?'Z':'A',conversationId:problem==='wrong-resume-target'?'C':'B',previousCheckpointed:(problem!=='missing-checkpoint') as true};});
  const result=await transitionOwnedConversation({kind:'resume',conversationId:'B'},{current:()=>called?current():{ownerUid:'a',conversationId:'A',pending:false},signal:new AbortController().signal,adapter:{transition}});
  expect(result).toMatchObject({status:'blocked',reason:'unverified-selection-receipt'});
});
