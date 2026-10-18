import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
let mockUid = 'synthetic-owner';
const mockSave = jest.fn();
const mockAvailable = jest.fn();
let mockActivityStatus = 'ready';
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { uid: mockUid } }) }));
jest.mock('@/lib/firebase', () => ({ auth: { get currentUser() { return { uid: mockUid }; } } }));
jest.mock('@/lib/checkins/checkInService', () => ({ checkInAvailable: (...args: unknown[]) => mockAvailable(...args), saveCheckIn: (...args: unknown[]) => mockSave(...args) }));
jest.mock('@/hooks/useActivityData', () => ({ useActivityData: () => mockActivityStatus === 'error' ? ({owner:mockUid,status:'error'}) : ({ owner: mockUid, status: 'ready', ledger: { events: [], rewards: [], milestones: [] }, entries: [], unreadable: 0, locked: false }) }));
import Activities from '@/components/progress/ActivityAvailability';
beforeEach(() => { mockUid = 'synthetic-owner'; mockActivityStatus = 'ready'; mockAvailable.mockReset().mockResolvedValue(undefined); mockSave.mockReset().mockResolvedValue({ outcome: 'awarded' }); });
async function fill() {
  await waitFor(() => expect(screen.getByRole('button', { name: 'Save check-in' })).toBeEnabled());
  fireEvent.change(screen.getByLabelText('Mood'), { target: { value: '2' } }); fireEvent.change(screen.getByLabelText('Connection'), { target: { value: '3' } }); fireEvent.change(screen.getByLabelText('Energy'), { target: { value: '4' } });
  fireEvent.click(screen.getByRole('checkbox'));
}
it('preserves entry UUID and first save timestamp across retries; double click never saves twice', async () => {
  mockSave.mockRejectedValueOnce(new Error('synthetic blocked storage'));
  render(<Activities />); await fill();
  fireEvent.submit(screen.getByRole('button', { name: 'Save check-in' }).closest('form')!);
  await screen.findByText(/Check-in was not confirmed saved/);
  const form = screen.getByRole('button', { name: 'Save check-in' }).closest('form')!;
  fireEvent.submit(form); fireEvent.submit(form);
  await screen.findByText('Check-in saved encrypted. One puzzle piece earned.');
  expect(mockSave).toHaveBeenCalledTimes(2);
  expect(mockSave.mock.calls[1][0].entryId).toBe(mockSave.mock.calls[0][0].entryId); expect(mockSave.mock.calls[1][0].occurredAt).toBe(mockSave.mock.calls[0][0].occurredAt);
  expect(mockSave.mock.calls[1][0].ratings).toEqual({ mood: 2, connection: 3, energy: 4 });
});
it('does not carry plaintext drafts to another UID; no activity is produced by opening the page', async () => {
  const view = render(<Activities />); await fill(); expect(mockSave).not.toHaveBeenCalled();
  mockUid = 'second-owner'; view.rerender(<Activities />);
  await waitFor(() => expect(screen.getByLabelText('Mood')).toHaveValue('')); expect(screen.getByRole('checkbox')).not.toBeChecked(); expect(mockSave).not.toHaveBeenCalled();
});

it('failed ledger reads show unavailable counters rather than indefinite loading or invented zeroes',async()=>{
 mockActivityStatus='error';render(<Activities/>);
 await waitFor(()=>expect(screen.getAllByText('Unavailable', {selector:'dd'})).toHaveLength(7));
 expect(screen.getByText('Saved rating history is unavailable.')).toBeInTheDocument();
 expect(screen.queryByText(/Loading earned pieces/)).not.toBeInTheDocument();
});
it('missing crypto capability keeps the form locked with no save or insecure fallback',async()=>{
 mockAvailable.mockRejectedValue(new Error('locked'));render(<Activities/>);
 await screen.findByText('Check-in is locked. Unlock your existing account key before saving.');
 expect(screen.getByRole('button',{name:'Save check-in'})).toBeDisabled();
 expect(screen.getByLabelText('Mood')).toBeDisabled();expect(mockSave).not.toHaveBeenCalled();
});
