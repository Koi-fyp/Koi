import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import ModeSelector from '@/components/layout/ModeSelector';
import { InputModeProvider, useInputMode } from '@/contexts/InputModeContext';

function ModeProbe() { return <p data-testid="mode">{useInputMode().mode}</p>; }

beforeEach(() => localStorage.clear());

it('opens with keyboard/click activation and closes on Escape', () => {
  render(<ModeSelector />);
  const toggle = screen.getByRole('button', { name: 'Mode: Text' });
  fireEvent.click(toggle);
  expect(toggle).toHaveAttribute('aria-expanded', 'true');
  fireEvent.keyDown(toggle, { key: 'Escape' });
  expect(toggle).toHaveAttribute('aria-expanded', 'false');
});

it('offers every mode, shares the choice with the page and remembers it on this device', () => {
  const { unmount } = render(<InputModeProvider><ModeSelector /><ModeProbe /></InputModeProvider>);
  fireEvent.click(screen.getByRole('button', { name: 'Mode: Text' }));
  for (const name of [/^Audio/, /^Video \+ Text/, /^Video \+ Audio/]) expect(screen.getByRole('button', { name })).toBeEnabled();
  fireEvent.click(screen.getByRole('button', { name: /^Video \+ Audio/ }));
  expect(screen.getByTestId('mode')).toHaveTextContent('video-audio');
  expect(screen.getByRole('button', { name: 'Mode: Video + Audio' })).toHaveAttribute('aria-expanded', 'false');
  unmount();
  render(<InputModeProvider><ModeSelector /><ModeProbe /></InputModeProvider>);
  expect(screen.getByTestId('mode')).toHaveTextContent('video-audio');
});

it('ignores a corrupted stored mode', () => {
  localStorage.setItem('koi_input_mode', 'hologram');
  render(<InputModeProvider><ModeProbe /></InputModeProvider>);
  expect(screen.getByTestId('mode')).toHaveTextContent('text');
});
