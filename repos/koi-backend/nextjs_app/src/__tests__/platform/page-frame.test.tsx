import React, { useState } from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { FeedbackProviders, SNACKBAR_MS, useConfirm, useConfirmedAction, useSnackbar } from '@/components/ui/feedback';
import ScrollButtons, { scrollButtonState } from '@/components/ui/ScrollButtons';

function Asker() {
  const confirm = useConfirm(); const [result, setResult] = useState('none');
  return <><button onClick={async () => setResult(String(await confirm({ title: 'Publish this revision?', description: 'Published versions cannot be edited.', confirmLabel: 'Publish' })))}>Ask</button><output aria-label="result">{result}</output></>;
}
const ask = () => { const opener = screen.getByRole('button', { name: 'Ask' }); opener.focus(); fireEvent.click(opener); return screen.findByRole('alertdialog', { name: 'Publish this revision?' }); };
const flushFrames = () => act(async () => { await new Promise(resolve => requestAnimationFrame(() => resolve(null))); });

describe('themed confirmation dialog', () => {
  it('is modal, labelled and described, and resolves true only on Confirm', async () => {
    render(<FeedbackProviders><Asker /></FeedbackProviders>);
    const dialog = await ask();
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(dialog).toHaveAccessibleDescription('Published versions cannot be edited.');
    fireEvent.click(screen.getByRole('button', { name: 'Publish' }));
    expect(await screen.findByText('true')).toBeInTheDocument();
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
  });
  it('closes without acting on Cancel and on Escape, restoring focus to the opener', async () => {
    render(<FeedbackProviders><Asker /></FeedbackProviders>);
    await ask(); fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(await screen.findByText('false')).toBeInTheDocument();
    await flushFrames(); expect(screen.getByRole('button', { name: 'Ask' })).toHaveFocus();
    const dialog = await ask(); fireEvent.keyDown(dialog, { key: 'Escape' });
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument(); expect(screen.getByLabelText('result')).toHaveTextContent('false');
    await flushFrames(); expect(screen.getByRole('button', { name: 'Ask' })).toHaveFocus();
  });
  it('traps keyboard focus inside the dialog', async () => {
    render(<FeedbackProviders><Asker /></FeedbackProviders>);
    const dialog = await ask();
    const cancel = screen.getByRole('button', { name: 'Cancel' }), publish = screen.getByRole('button', { name: 'Publish' });
    expect(cancel).toHaveFocus();
    fireEvent.keyDown(dialog, { key: 'Tab', shiftKey: true }); expect(publish).toHaveFocus();
    fireEvent.keyDown(dialog, { key: 'Tab' }); expect(cancel).toHaveFocus();
  });
  it('refuses to act when no provider is mounted', async () => {
    render(<Asker />); fireEvent.click(screen.getByRole('button', { name: 'Ask' }));
    expect(await screen.findByText('false')).toBeInTheDocument();
  });
});

describe('snackbars', () => {
  afterEach(() => jest.useRealTimers());
  function Notifier() { const snackbar = useSnackbar(); return <><button onClick={() => snackbar.success('Revision published')}>ok</button><button onClick={() => snackbar.error('Action failed')}>fail</button></>; }
  it('announces politely with success and error variants and auto-dismisses after 4 s', () => {
    jest.useFakeTimers();
    render(<FeedbackProviders><Notifier /></FeedbackProviders>);
    fireEvent.click(screen.getByRole('button', { name: 'ok' })); fireEvent.click(screen.getByRole('button', { name: 'fail' }));
    const success = screen.getByText('Revision published').closest('.koi-snackbar')!;
    expect(success).toHaveAttribute('data-variant', 'success'); expect(screen.getByText('Action failed').closest('.koi-snackbar')).toHaveAttribute('data-variant', 'error');
    expect(success.parentElement).toHaveAttribute('aria-live', 'polite');
    act(() => { jest.advanceTimersByTime(SNACKBAR_MS - 1); }); expect(screen.getByText('Revision published')).toBeInTheDocument();
    act(() => { jest.advanceTimersByTime(1); }); expect(screen.queryByText('Revision published')).not.toBeInTheDocument();
  });
  it('confirmed actions run once, then report success; a cancelled dialog runs nothing', async () => {
    const action = jest.fn(async () => {});
    function Action() { const confirmed = useConfirmedAction(); return <button onClick={() => void confirmed({ title: 'Assign?', success: 'Assignments created' }, fn => fn(), action)}>Assign</button>; }
    render(<FeedbackProviders><Action /></FeedbackProviders>);
    fireEvent.click(screen.getByRole('button', { name: 'Assign' })); fireEvent.click(await screen.findByRole('button', { name: 'Cancel' }));
    expect(action).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Assign' })); fireEvent.click(await screen.findByRole('button', { name: 'Confirm' }));
    expect(await screen.findByText('Assignments created')).toBeInTheDocument(); expect(action).toHaveBeenCalledTimes(1);
  });
});

describe('scroll buttons', () => {
  it('shows each button only when useful', () => {
    expect(scrollButtonState(0, 800, 900)).toEqual({ top: false, bottom: false });
    expect(scrollButtonState(301, 800, 1200)).toEqual({ top: true, bottom: false });
    expect(scrollButtonState(0, 800, 1201)).toEqual({ top: false, bottom: true });
    expect(scrollButtonState(300, 800, 3000)).toEqual({ top: false, bottom: true });
  });
  it('renders labelled buttons that scroll smoothly, or instantly with reduced motion', () => {
    const scrollTo = jest.fn(); Object.defineProperty(window, 'scrollTo', { configurable: true, value: scrollTo });
    Object.defineProperty(document.documentElement, 'scrollHeight', { configurable: true, value: 5000 });
    Object.defineProperty(window, 'scrollY', { configurable: true, value: 1000 });
    const { unmount } = render(<ScrollButtons />);
    fireEvent.click(screen.getByRole('button', { name: 'Back to top' })); expect(scrollTo).toHaveBeenLastCalledWith({ top: 0, behavior: 'smooth' });
    fireEvent.click(screen.getByRole('button', { name: 'Scroll to bottom' })); expect(scrollTo).toHaveBeenLastCalledWith({ top: 5000, behavior: 'smooth' });
    unmount();
    Object.defineProperty(window, 'matchMedia', { configurable: true, value: (query: string) => ({ matches: query.includes('reduce'), addEventListener() {}, removeEventListener() {} }) });
    render(<ScrollButtons />); fireEvent.click(screen.getByRole('button', { name: 'Back to top' }));
    expect(scrollTo).toHaveBeenLastCalledWith({ top: 0, behavior: 'auto' });
    Object.defineProperty(window, 'scrollY', { configurable: true, value: 0 });
    Object.defineProperty(document.documentElement, 'scrollHeight', { configurable: true, value: 0 });
  });
});
