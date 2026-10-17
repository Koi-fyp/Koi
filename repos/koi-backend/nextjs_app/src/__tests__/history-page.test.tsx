import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
const mockRead = jest.fn(), mockAuth = jest.fn();
const mockFirebase = { currentUser: { uid: 'a' } };
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => mockAuth() }));
jest.mock('@/lib/firebase', () => ({ auth: mockFirebase }));
const mockManager = { get uid() { return mockFirebase.currentUser.uid; }, session: { getSnapshot: () => ({ messages: [] }) } };
jest.mock('@/contexts/ConversationContext', () => ({ useSharedConversation: () => mockManager }));
jest.mock('@/lib/history/readHistory', () => ({ ...jest.requireActual('@/lib/history/readHistory'), readOwnedHistory: (...args: unknown[]) => mockRead(...args) }));
import History from '@/app/(authenticated)/history/page';
const data = { truncated: false, unreadable: 0, conversations: [{ id: 'old', title: 'Synthetic retained title', createdAt: null,
  earliestRetainedAt: new Date(), lastActivityAt: new Date(), active: false, retainedRecords: 1, messages: [{ id: 'one', sender: 'user', text: '<script>synthetic text</script>', at: new Date() }] }] };
beforeEach(() => { mockAuth.mockReturnValue({ user: { uid: 'a' }, isLinked: false }); mockFirebase.currentUser.uid = 'a'; mockRead.mockReset().mockResolvedValue(data); });
it('reads a real-source view, searches in memory and never implies an old conversation can be continued', async () => {
  render(<History />); await screen.findByText('Synthetic retained title');
  expect(screen.queryByText('Continue current conversation')).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: 'Read saved conversation' }));
  expect(screen.getByText('<script>synthetic text</script>')).toBeInTheDocument(); expect(document.querySelector('script')).toBeNull();
  fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'missing term' } });
  expect(screen.getByText('No matching retained messages.')).toBeInTheDocument(); expect(mockRead).toHaveBeenCalledTimes(1);
});
it('hides the previous UID immediately and ignores its late result', async () => {
  const view=render(<History />); await screen.findByText('Synthetic retained title');
  mockFirebase.currentUser.uid='b';mockAuth.mockReturnValue({user:{uid:'b'},isLinked:false});mockRead.mockImplementation(()=>new Promise(()=>{}));
  view.rerender(<History />);expect(screen.queryByText('Synthetic retained title')).not.toBeInTheDocument();
  await waitFor(()=>expect(screen.getByRole('status')).toHaveTextContent('Unlocking'));
});
it('distinguishes storage error from empty data and offers explicit retry', async () => {
  mockRead.mockRejectedValueOnce(new Error('fixture storage denied')).mockResolvedValueOnce({conversations:[],truncated:false,unreadable:0});
  render(<History />);await screen.findByRole('alert');expect(screen.queryByText('No saved conversation messages yet.')).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('button',{name:'Retry history'}));await screen.findByText('No saved conversation messages yet.');
});
