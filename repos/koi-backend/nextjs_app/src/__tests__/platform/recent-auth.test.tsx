jest.mock('firebase/auth', () => ({ EmailAuthProvider: { credential: jest.fn(() => 'credential') }, reauthenticateWithCredential: jest.fn().mockResolvedValue(undefined) }));
import React, { useState } from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { reauthenticateWithCredential } from 'firebase/auth';
import { useRecentAuthentication } from '@/components/professional/RecentAuthentication';

beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function () { this.setAttribute('open', ''); };
  HTMLDialogElement.prototype.close = function () { this.removeAttribute('open'); };
});
beforeEach(() => jest.clearAllMocks());
const user = (fresh = false) => ({ uid: 'clinician_a', email: 'synthetic@example.invalid', getIdTokenResult: jest.fn().mockResolvedValue({ claims: { auth_time: Date.now() / 1000 - (fresh ? 0 : 301) } }) } as any);
function Harness({ account }: { account: any }) {
  const recent = useRecentAuthentication(account.uid, () => account);
  const [draft, setDraft] = useState('Unsaved text'), [result, setResult] = useState('');
  return <><input aria-label="Draft text" value={draft} onChange={e => setDraft(e.target.value)} /><button onClick={() => void recent.beforeMutation().then(() => setResult('confirmed'), e => setResult(e.code))}>Save</button><p role="status">{result}</p>{recent.dialog}</>;
}
it('reauthenticates the same account before a write without discarding unsaved edits', async () => {
  const account = user(); render(<Harness account={account} />); fireEvent.click(screen.getByRole('button', { name: 'Save' }));
  await screen.findByRole('dialog', { name: 'Confirm your sign-in' }); expect(screen.getByRole('textbox', { name: 'Draft text' })).toHaveValue('Unsaved text');
  fireEvent.change(screen.getByLabelText('Confirm password'), { target: { value: 'synthetic-only' } }); fireEvent.click(screen.getByRole('button', { name: 'Continue' }));
  await screen.findByText('confirmed'); expect(reauthenticateWithCredential).toHaveBeenCalledWith(account, 'credential'); expect(screen.getByRole('textbox', { name: 'Draft text' })).toHaveValue('Unsaved text');
});
it('cancels before dispatching a write and keeps unsaved edits', async () => {
  render(<Harness account={user()} />); fireEvent.click(screen.getByRole('button', { name: 'Save' })); await screen.findByRole('dialog');
  fireEvent.click(screen.getByRole('button', { name: 'Cancel' })); await screen.findByText('reauth_cancelled'); expect(screen.getByRole('textbox', { name: 'Draft text' })).toHaveValue('Unsaved text');
});
it('does not prompt for a recent sign-in', async () => {
  render(<Harness account={user(true)} />); fireEvent.click(screen.getByRole('button', { name: 'Save' })); await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('confirmed')); expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
});
