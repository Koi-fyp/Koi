import { webcrypto, createHash } from 'crypto';
import { TextEncoder } from 'util';
jest.mock('@/lib/firebase', () => ({ auth: null }));
import { conversationCompletionEligible, conversationCompletionId, type ConversationCompletionEvidence } from '@/lib/activities/conversationCompletion';
const evidence: ConversationCompletionEvidence = { ownerUid: 'synthetic-owner', conversationId: 'conversation-a', pending: false, lastPersistedMessageId: 'assistant-a', persistedExchanges: 1, turnState: 'done-persisted', handoffState: 'resolved-or-absent' };
it.each(['submitted', 'partial', 'failed', 'cancelled', 'done-unpersisted'] as const)('rejects unproven turn status: %s', turnState => {
  expect(conversationCompletionEligible(evidence.ownerUid, { ...evidence, turnState }, true)).toBe(false);
});
it('requires explicit completion, a persisted exchange, stable owner, no pending stream and acknowledged handoff state', () => {
  expect(conversationCompletionEligible(evidence.ownerUid, evidence, false)).toBe(false);
  for (const patch of [{ pending: true }, { persistedExchanges: 0 }, { lastPersistedMessageId: null }, { ownerUid: 'foreign' }, { handoffState: 'unresolved' as const }, { handoffState: 'unknown' as const }]) expect(conversationCompletionEligible(evidence.ownerUid, { ...evidence, ...patch }, true)).toBe(false);
  expect(conversationCompletionEligible(evidence.ownerUid, evidence, true)).toBe(true);
  // Resolved prior handoff is eligible; numeric risk/done.handoff:null are not accepted inputs.
});
it('uses exact deterministic completion identity; retry is stable and only a new persisted exchange changes it', async () => {
  Object.defineProperty(globalThis.crypto, 'subtle', { configurable: true, value: webcrypto.subtle }); Object.assign(globalThis, { TextEncoder });
  const expected = createHash('sha256').update('koi:conv:v1:synthetic-owner:conversation-a:assistant-a').digest('hex');
  expect(await conversationCompletionId(evidence.ownerUid, evidence.conversationId, 'assistant-a')).toBe(expected);
  expect(await conversationCompletionId(evidence.ownerUid, evidence.conversationId, 'assistant-a')).toBe(expected);
  expect(await conversationCompletionId(evidence.ownerUid, evidence.conversationId, 'assistant-b')).not.toBe(expected);
});
