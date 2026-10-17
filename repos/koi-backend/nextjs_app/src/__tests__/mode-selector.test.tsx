import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import ModeSelector from '@/components/layout/ModeSelector';

it('opens with keyboard/click activation and keeps media modes disabled', () => {
  render(<ModeSelector />);
  const toggle = screen.getByRole('button', { name: 'Mode: Text' });
  fireEvent.click(toggle);
  expect(toggle).toHaveAttribute('aria-expanded', 'true');
  expect(screen.getByRole('button', { name: /^Audio LOCKED$/ })).toBeDisabled();
  expect(screen.getByRole('button', { name: /Video \+ Text/ })).toBeDisabled();
  expect(screen.getByRole('button', { name: /Video \+ Audio/ })).toBeDisabled();
  fireEvent.keyDown(toggle, { key: 'Escape' });
  expect(toggle).toHaveAttribute('aria-expanded', 'false');
});
