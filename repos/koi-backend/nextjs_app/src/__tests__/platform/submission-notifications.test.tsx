import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import SubmissionNotifications from '@/components/professional/SubmissionNotifications';
import type { ProfessionalApi } from '@/lib/platform/client';

it('lists submission updates newest first whatever order the server returns', async () => {
  const items = [
    { id: 'n-old', event_id: 'e1', submission_id: 's-old', created_at: '2026-10-22T05:14:49Z' },
    { id: 'n-new', event_id: 'e2', submission_id: 's-new', created_at: '2026-10-22T05:32:51Z' },
  ];
  const api: ProfessionalApi = { request: jest.fn(async () => ({ items, next_cursor: null })) as any, dispose: jest.fn() };
  const onInspect = jest.fn();
  render(<SubmissionNotifications api={api} organizationId="org" onInspect={onInspect} onError={jest.fn()} />);
  const buttons = await screen.findAllByRole('button', { name: 'Open received submission' });
  fireEvent.click(buttons[0]);
  expect(onInspect).toHaveBeenCalledWith('s-new');
});
