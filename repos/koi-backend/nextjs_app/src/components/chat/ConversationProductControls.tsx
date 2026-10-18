'use client';
import AccountPreferenceStatus from './AccountPreferenceStatus';
import { useState, useSyncExternalStore } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useSharedConversation } from '@/contexts/ConversationContext';
import { saveConversationCompletion, type ConversationCompletionResult } from '@/lib/activities/conversationCompletion';
import { auth } from '@/lib/firebase';
import type { AvatarPreferenceState } from '@/hooks/useAvatarPreference';
import { saveAvatarPreference } from '@/lib/avatar/avatarPreference';
import AvatarPicker from '@/app/(authenticated)/settings/components/AvatarPicker';

const COMPLETION_MESSAGES: Record<string, string> = {
  awarded: 'Conversation completion saved. One piece was added to your board.',
  'daily-cap': 'Conversation completion saved. Today’s conversation piece was already earned, so no new piece was added.',
  'board-full': 'Conversation completion saved. Your 25-piece board is already full, so no new piece was added.',
  duplicate: 'This conversation is already saved as complete up to its latest reply.',
  busy: 'A completion is already being saved. Please wait.',
  pending: 'A reply is still in progress. Wait for it to finish before saving completion.',
  'no-pair': 'Completion needs at least one saved message and reply in this conversation.',
  'unresolved-handoff': 'A crisis support step is still open in this conversation, so it cannot be saved as complete. Choose an option in the support dialog first.',
  'owner-changed': 'Your account changed. Nothing was saved.',
  unavailable: 'Completion could not be saved right now. Nothing was recorded; please try again.',
};
const completionMessage = (result: ConversationCompletionResult) => COMPLETION_MESSAGES[result.status === 'saved' ? result.outcome : result.reason];

/** Product actions. Completion is saved only by its explicit button; nothing else here completes or rewards. */
export default function ConversationProductControls({ preferenceState: state, pending = false }: { preferenceState: AvatarPreferenceState; pending?: boolean }) {
  const { user } = useAuth();
  const manager = useSharedConversation();
  const recovery = useSyncExternalStore(manager.subscribe, manager.getSnapshot, manager.getSnapshot);
  const [completion, setCompletion] = useState<{ uid: string; message: string } | null>(null);
  const [saving, setSaving] = useState(false);
  const canComplete = !!user && !pending && !saving && !recovery.completing && !recovery.loading && !recovery.error
    && recovery.hasQualifyingPair && !recovery.hasUnresolvedHandoff;
  const saveCompletion = async () => {
    if (!user || saving) return;
    const owner = user.uid;
    setSaving(true); setCompletion(null);
    try {
      const result = await saveConversationCompletion(manager, owner);
      if (auth?.currentUser?.uid === owner) setCompletion({ uid: owner, message: completionMessage(result) });
    } finally { setSaving(false); }
  };
  const [picker, setPicker] = useState<string | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const [details, setDetails] = useState(false);
  const selected = state.status === 'ready' && state.preference.status === 'selected' ? state.preference : null;
  return <div style={{ padding: '4px 16px', fontSize: 14 }}>
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
      <button type="button" disabled title={pending ? 'Wait for the current reply. New chat creation is not connected yet.' : 'New chats are not available yet'} aria-describedby="session-actions-status" style={{ minHeight: 44, opacity: 0.5 }}>New Chat</button>
      <button type="button" onClick={() => setDetails(!details)} aria-expanded={details} style={{ minHeight: 44 }}>Complete Conversation</button>
      <button type="button" disabled={!user || state.status !== 'ready'} onClick={() => { setFailure(null); setPicker(user!.uid); }} style={{ minHeight: 44 }}>Change companion</button>
    </div>
    <p id="session-actions-status" className="sr-only">New Chat is not available yet. Your current conversation continues.</p>
    {details && <div role="region" aria-label="Conversation completion requirements">
      <p>Completion must be explicit and saved, with a successfully saved message and reply. Leaving this screen, Back, End or starting a new chat does not complete it.</p>
      <p>{pending ? 'A reply is still in progress. This conversation cannot be completed now.'
        : recovery.hasUnresolvedHandoff ? 'A crisis support step is still open in this conversation, so it cannot be completed yet.'
        : !recovery.hasQualifyingPair ? 'Send a message and wait for the reply to be saved before completing.'
        : 'This conversation can be saved as complete.'}</p>
      <p>Conversation completions can earn at most one piece per Asia/Karachi day. Open crisis handoffs, failed or cancelled replies do not qualify.</p>
      <button type="button" disabled={!canComplete} onClick={() => void saveCompletion()}>{saving ? 'Saving completion…' : 'Save completion'}</button>
      {completion?.uid === user?.uid && completion && <p role="status">{completion.message}</p>}
    </div>}
    <AccountPreferenceStatus uid={user?.uid} />
    {failure && <p role="alert">{failure}</p>}
    {picker === user?.uid && user && <AvatarPicker key={user.uid} isOpen onClose={() => setPicker(null)} currentAvatar={selected?.companion} currentName={selected?.displayName || selected?.name}
      onSave={async (companion, name) => {
        const owner = user.uid;
        if (auth?.currentUser?.uid !== owner) { setPicker(null); return false; }
        try {
          await saveAvatarPreference(owner, companion, name);
          return auth?.currentUser?.uid === owner;
        } catch { if (auth?.currentUser?.uid === owner) setFailure('Companion could not be saved. Please try again.'); return false; }
      }} />}
  </div>;
}
