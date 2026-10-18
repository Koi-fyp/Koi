'use client';
import AccountPreferenceStatus from './AccountPreferenceStatus';
import { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { auth } from '@/lib/firebase';
import type { AvatarPreferenceState } from '@/hooks/useAvatarPreference';
import { saveAvatarPreference } from '@/lib/avatar/avatarPreference';
import AvatarPicker from '@/app/(authenticated)/settings/components/AvatarPicker';

/** Product actions only: never creates sessions, completes activities or issues rewards. */
export default function ConversationProductControls({ preferenceState: state, pending = false }: { preferenceState: AvatarPreferenceState; pending?: boolean }) {
  const { user } = useAuth();
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
    <p id="session-actions-status" className="sr-only">New Chat and saved completion are not available yet. Your current conversation continues.</p>
    {details && <div role="region" aria-label="Conversation completion requirements">
      <p>Completion must be explicit and saved, with a successfully persisted exchange. Leaving this screen or starting a new chat does not complete it.</p>
      <p>{pending ? 'A reply is still in progress. This conversation cannot be completed now.' : 'Completion needs the shared session to expose durable unresolved-handoff status and persisted SSE completion evidence. This integration is not connected yet.'}</p>
      <p>Eligible conversation rewards are limited to one piece per Asia/Karachi day. Crisis handoffs, failed or cancelled conversations do not qualify. No conversation reward is issued here. Saved check-ins and verified breathing activities can earn pieces in Progress.</p>
      <button type="button" disabled>Save completion (not available yet)</button>
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
