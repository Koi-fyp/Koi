/** Web-side consumer seam only. No production adapter is approved or installed. */
export type OwnedSelection = { ownerUid: string; conversationId: string; pending: boolean };
export type SessionTransition = { kind: 'new' } | { kind: 'resume'; conversationId: string };
export interface SessionTransitionReceipt {
  ownerUid: string; previousConversationId: string; conversationId: string; previousCheckpointed: true;
}
export interface ApprovedSessionTransitionAdapter {
  /** Joint P0 owner must implement atomic checkpoint/archive/select and publish the new active session. */
  transition(input: SessionTransition & { ownerUid: string; expectedConversationId: string; signal: AbortSignal }): Promise<SessionTransitionReceipt>;
}
export async function transitionOwnedConversation(action: SessionTransition, access: {
  current: () => OwnedSelection | null; signal: AbortSignal; adapter?: ApprovedSessionTransitionAdapter;
}) {
  const blocked = (reason: string) => ({ status:'blocked' as const, reason });
  const original = access.current();
  if (access.signal.aborted) return blocked('cancelled');
  if (!original?.ownerUid || !original.conversationId) return blocked('session-unavailable');
  if (original.pending) return blocked('reply-in-progress');
  if (!access.adapter) return blocked('joint-session-adapter-required');
  if (action.kind === 'resume' && (!action.conversationId.trim() || action.conversationId.length > 160)) return blocked('invalid-target');
  if (action.kind === 'resume' && action.conversationId === original.conversationId) return {status:'unchanged' as const,conversationId:original.conversationId};
  try {
    const receipt = await access.adapter.transition({...action,ownerUid:original.ownerUid,expectedConversationId:original.conversationId,signal:access.signal});
    const current = access.current();
    if (access.signal.aborted || current?.ownerUid !== original.ownerUid) return blocked('owner-changed-or-cancelled');
    if (receipt.ownerUid !== original.ownerUid || receipt.previousConversationId !== original.conversationId || receipt.previousCheckpointed !== true
      || !receipt.conversationId || receipt.conversationId === original.conversationId || receipt.conversationId !== current.conversationId
      || (action.kind === 'resume' && receipt.conversationId !== action.conversationId)) return blocked('unverified-selection-receipt');
    return {status:'selected' as const,conversationId:receipt.conversationId};
  } catch { return blocked('transition-failed'); }
}
