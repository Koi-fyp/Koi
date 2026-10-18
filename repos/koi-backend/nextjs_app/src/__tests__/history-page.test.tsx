import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
const mockRead = jest.fn(), mockArchive = jest.fn(), mockAuth = jest.fn(), mockOpen = jest.fn(), mockCreate = jest.fn(), mockPush = jest.fn();
const mockFirebase = { currentUser: { uid: 'a' } };
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => mockAuth() }));
jest.mock('@/lib/firebase', () => ({ auth: mockFirebase }));
jest.mock('next/navigation', () => ({ useRouter: () => ({ push: mockPush, replace: jest.fn() }) }));
let mockSessionSnapshot = { pending: false, messages: [] as Array<{ id: string; conversationId: string; sender: 'user' | 'ai'; content: string; timestamp: Date; status: string }> };
let mockRecovery = { loading: false, error: null, completing: false, switching: false, hasQualifyingPair: false, hasUnresolvedHandoff: false };
const mockManager = {
  get uid() { return mockFirebase.currentUser.uid; },
  session: { conversationId: 'active-id', subscribe: () => () => {}, getSnapshot: () => mockSessionSnapshot },
  subscribe: () => () => {}, getSnapshot: () => mockRecovery,
  getActiveHeader: () => ({ conversationId: 'active-id', createdAt: new Date('2026-10-19T08:00:00Z'), lastActiveAt: new Date('2026-10-19T09:00:00Z') }),
};
jest.mock('@/contexts/ConversationContext', () => ({ useSharedConversation: () => mockManager,
  useOwnedConversationActions: () => ({ createOwned: (...args: unknown[]) => mockCreate(...args), openOwned: (...args: unknown[]) => mockOpen(...args) }) }));
jest.mock('@/lib/history/readHistory', () => ({ ...jest.requireActual('@/lib/history/readHistory'), readOwnedHistory: (...args: unknown[]) => mockRead(...args) }));
jest.mock('@/lib/history/readArchive', () => ({ ARCHIVE_LIST_LIMIT: 100, readArchivedConversations: (...args: unknown[]) => mockArchive(...args) }));
import History from '@/app/(authenticated)/history/page';
const retained = { truncated: false, unreadable: 0, conversations: [{ id: 'old', title: 'Synthetic retained title', createdAt: null,
  earliestRetainedAt: new Date(), lastActivityAt: new Date(), active: false, retainedRecords: 1, messages: [{ id: 'one', sender: 'user', text: '<script>synthetic text</script>', at: new Date() }] }] };
const archived = { status: 'ready', truncated: false, conversations: [
  { conversationId: 'archived-a', locked: false, title: 'Synthetic archived title', createdAt: new Date('2026-10-18T08:00:00Z'), lastActiveAt: new Date('2026-10-18T09:00:00Z'), archivedAt: new Date(), messageCount: 2,
    messages: [{ id: 'x', sender: 'user', text: 'Synthetic archived title', at: new Date() }, { id: 'y', sender: 'ai', text: 'Synthetic archived reply', at: new Date() }] },
  { conversationId: 'archived-locked', locked: true, title: '', createdAt: new Date('2026-10-17T08:00:00Z'), lastActiveAt: new Date('2026-10-17T09:00:00Z'), archivedAt: new Date(), messageCount: null, messages: [] },
] };
beforeEach(() => {
  mockRecovery = { ...mockRecovery, hasUnresolvedHandoff: false };
  mockAuth.mockReturnValue({ user: { uid: 'a' }, isLinked: false }); mockFirebase.currentUser.uid = 'a';
  mockRead.mockReset().mockResolvedValue(retained); mockArchive.mockReset().mockResolvedValue(archived);
  mockOpen.mockReset().mockResolvedValue({ conversationId: 'archived-a' }); mockCreate.mockReset().mockResolvedValue({ conversationId: 'new' }); mockPush.mockReset();
  mockSessionSnapshot = { pending: false, messages: [
    { id: 'u1', conversationId: 'active-id', sender: 'user', content: 'Synthetic active title', timestamp: new Date('2026-10-19T08:30:00Z'), status: 'completed' },
    { id: 'a1', conversationId: 'active-id', sender: 'ai', content: 'Synthetic active reply', timestamp: new Date('2026-10-19T08:31:00Z'), status: 'completed' }] };
});
it('reads a real-source view, searches in memory and keeps retained legacy groups read-only', async () => {
  render(<History />); await screen.findByText('Synthetic retained title');
  expect(screen.getByText('This retained conversation is read-only. It remains unchanged.')).toBeInTheDocument();
  const legacy = screen.getByText('Synthetic retained title').closest('li')!;
  fireEvent.click(legacy.querySelector('button')!);
  expect(screen.getByText('<script>synthetic text</script>')).toBeInTheDocument(); expect(document.querySelector('script')).toBeNull();
  fireEvent.click(screen.getByText('Optional message search'));
  fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'missing term' } });
  expect(screen.getByText('No matching retained messages.')).toBeInTheDocument(); expect(mockRead).toHaveBeenCalledTimes(1);
});
it('lists the active conversation first, then archived ones with title, date and count; locked rows cannot open', async () => {
  render(<History />); await screen.findByText('Synthetic archived title');
  const items = screen.getAllByRole('listitem');
  expect(items[0]).toHaveTextContent('Synthetic active title'); expect(items[0]).toHaveTextContent('Current conversation'); expect(items[0]).toHaveTextContent('2 messages');
  const archivedItem = screen.getByText('Synthetic archived title', { selector: 'h2' }).closest('li')!;
  expect(archivedItem).toHaveTextContent('Saved conversation'); expect(archivedItem).toHaveTextContent('2 messages');
  const lockedItem = screen.getByText('Locked conversation').closest('li')!;
  expect(lockedItem).toHaveTextContent('Saved conversation · Locked'); expect(lockedItem).toHaveTextContent('message count locked');
  expect(lockedItem.textContent).not.toMatch(/Open conversation/);
  expect(screen.getAllByRole('button', { name: 'Open conversation' })).toHaveLength(1);
  expect(screen.getByText('Continue current conversation')).toHaveAttribute('href', '/chat');
  // KOI button styling for the integration-era controls.
  expect(screen.getByRole('button', { name: 'Open conversation' })).toHaveClass('neo-btn-primary');
  expect(screen.getByText('Continue current conversation')).toHaveClass('neo-btn-primary');
  expect(screen.getByRole('button', { name: 'New Chat' })).toHaveClass('neo-btn-primary');
});
it('opening an archived conversation calls openOwned and routes to /chat; a refusal stays on the page', async () => {
  render(<History />); await screen.findByText('Synthetic archived title');
  fireEvent.click(screen.getByRole('button', { name: 'Open conversation' }));
  await waitFor(() => expect(mockPush).toHaveBeenCalledWith('/chat')); expect(mockOpen).toHaveBeenCalledWith('archived-a');
  const { ConversationSwitchError } = jest.requireActual('@/lib/conversation/PersistentConversation');
  mockOpen.mockRejectedValueOnce(new ConversationSwitchError('conflict')); mockPush.mockReset();
  fireEvent.click(screen.getByRole('button', { name: 'Open conversation' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('changed in another tab'); expect(mockPush).not.toHaveBeenCalled();
});
it('New Chat is enabled when idle and disabled with reply in progress while pending', async () => {
  const view = render(<History />); await screen.findByText('Synthetic archived title');
  fireEvent.click(screen.getByRole('button', { name: 'New Chat' }));
  await waitFor(() => expect(mockPush).toHaveBeenCalledWith('/chat')); expect(mockCreate).toHaveBeenCalledTimes(1);
  mockSessionSnapshot = { ...mockSessionSnapshot, pending: true }; view.rerender(<History />);
  expect(screen.getByRole('button', { name: 'New Chat (reply in progress)' })).toBeDisabled();
  expect(screen.getByRole('button', { name: 'Open conversation (reply in progress)' })).toBeDisabled();
});
it('hides the previous UID immediately and ignores its late result', async () => {
  const view=render(<History />); await screen.findByText('Synthetic retained title');
  mockFirebase.currentUser.uid='b';mockAuth.mockReturnValue({user:{uid:'b'},isLinked:false});mockRead.mockImplementation(()=>new Promise(()=>{}));
  view.rerender(<History />);expect(screen.queryByText('Synthetic retained title')).not.toBeInTheDocument();
  await waitFor(()=>expect(screen.getByRole('status')).toHaveTextContent('Unlocking'));
});
it('distinguishes storage error from empty data and offers explicit retry', async () => {
  mockSessionSnapshot = { pending: false, messages: [] };
  mockRead.mockRejectedValueOnce(new Error('fixture storage denied')).mockResolvedValueOnce({conversations:[],truncated:false,unreadable:0});
  mockArchive.mockResolvedValue({ status: 'ready', truncated: false, conversations: [] });
  render(<History />);await screen.findByRole('alert');expect(screen.queryByText('Empty conversation')).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('button',{name:'Retry history'}));await screen.findByText('Empty conversation');
});
it('does not report rows of listed archived conversations as unreadable', async () => {
  mockRead.mockResolvedValue({ truncated: false, unreadable: 2, conversations: [
    { id: 'archived-a', title: '', createdAt: null, earliestRetainedAt: new Date(), lastActivityAt: new Date(), active: false, retainedRecords: 2, messages: [] }] });
  render(<History />); await screen.findByText('Synthetic archived title');
  expect(screen.queryByText(/could not be unlocked or validated/)).not.toBeInTheDocument();
  mockRead.mockResolvedValue({ ...retained, unreadable: 1 });
  fireEvent.click(screen.getByRole('button', { name: 'Refresh saved history' }));
  expect(await screen.findByText(/could not be unlocked or validated/)).toBeInTheDocument();
});
it('while a safety handoff is open, only the current conversation stays reachable', async () => {
  mockRecovery = { ...mockRecovery, hasUnresolvedHandoff: true };
  render(<History />); await screen.findByText('Synthetic archived title');
  expect(screen.getByRole('button', { name: 'New Chat' })).toBeDisabled();
  expect(screen.getByRole('button', { name: 'Open conversation' })).toBeDisabled();
  expect(screen.getByText('Please finish the safety check first.')).toBeInTheDocument();
  expect(screen.getByText('Continue current conversation')).toHaveAttribute('href', '/chat');
  fireEvent.click(screen.getByRole('button', { name: 'Open conversation' })); expect(mockOpen).not.toHaveBeenCalled(); expect(mockCreate).not.toHaveBeenCalled();
});
