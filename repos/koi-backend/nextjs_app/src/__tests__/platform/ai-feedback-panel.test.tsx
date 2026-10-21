import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import AiFeedbackPanel, { resetAiFeedbackSession } from '@/components/professional/AiFeedbackPanel';
import { FeedbackProviders } from '@/components/ui/feedback';
import { isAiFeedbackRequest } from '@/lib/platform/ai-feedback';
import type { ProfessionalApi } from '@/lib/platform/client';

let request: jest.Mock, api: ProfessionalApi;
beforeEach(() => { resetAiFeedbackSession(); request = jest.fn(async () => ({ evaluation_id: 'evaluation', rating: 4, tags: [], created_at: 'now', psychologist_uid: 'psy' })); api = { request: request as any, dispose: jest.fn() }; });

it('sends rating, tags and comment to the new route, then thanks and stays disabled for this session', async () => {
  const view = render(<AiFeedbackPanel api={api} evaluationId="evaluation" onError={jest.fn()} />, { wrapper: FeedbackProviders });
  const sendButton = screen.getByRole('button', { name: 'Send feedback' }); expect(sendButton).toBeDisabled();
  fireEvent.click(screen.getByRole('radio', { name: '4' }));
  fireEvent.click(screen.getByRole('checkbox', { name: 'Accurate' })); fireEvent.click(screen.getByRole('checkbox', { name: 'Helpful follow-ups' }));
  fireEvent.change(screen.getByRole('textbox', { name: 'AI feedback comment' }), { target: { value: '  Clear follow-up questions.  ' } });
  fireEvent.click(sendButton);
  expect(await screen.findByText('Sent')).toBeInTheDocument();
  expect(screen.getByText('Thanks, feedback recorded')).toBeInTheDocument();
  expect(request).toHaveBeenCalledWith('/api/v1/professional/evaluations/evaluation/ai-feedback', 'POST', { rating: 4, tags: ['Accurate', 'Helpful follow-ups'], comment: 'Clear follow-up questions.' });
  expect(screen.getByRole('radio', { name: '4' })).toBeDisabled();
  view.unmount(); render(<AiFeedbackPanel api={api} evaluationId="evaluation" onError={jest.fn()} />);
  expect(screen.getByText('Thanks, feedback recorded')).toBeInTheDocument(); expect(screen.getByRole('button', { name: 'Send feedback' })).toBeDisabled();
});
it('limits the comment to 500 characters and keeps entries on failure', async () => {
  request.mockRejectedValueOnce(new Error('offline'));
  render(<AiFeedbackPanel api={api} evaluationId="other" onError={jest.fn()} />, { wrapper: FeedbackProviders });
  fireEvent.click(screen.getByRole('radio', { name: '2' }));
  fireEvent.change(screen.getByRole('textbox', { name: 'AI feedback comment' }), { target: { value: 'x'.repeat(501) } });
  expect(screen.getByText('501 / 500 characters')).toBeInTheDocument(); expect(screen.getByRole('button', { name: 'Send feedback' })).toBeDisabled();
  fireEvent.change(screen.getByRole('textbox', { name: 'AI feedback comment' }), { target: { value: 'Too generic overall' } });
  fireEvent.click(screen.getByRole('button', { name: 'Send feedback' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('Feedback was not recorded');
  expect(screen.getByRole('textbox', { name: 'AI feedback comment' })).toHaveValue('Too generic overall'); expect(screen.getByRole('button', { name: 'Send feedback' })).toBeEnabled();
});
it('validates the request shape shared with the route', () => {
  expect(isAiFeedbackRequest({ rating: 5, tags: [] })).toBe(true);
  expect(isAiFeedbackRequest({ rating: 5, tags: ['Unsafe wording'], comment: 'ok' })).toBe(true);
  for (const bad of [null, [], { rating: 5 }, { rating: 0, tags: [] }, { rating: 5, tags: ['x'] }, { rating: 5, tags: [], extra: 1 }, { rating: 5, tags: [], comment: 'x'.repeat(501) }]) expect(isAiFeedbackRequest(bad)).toBe(false);
});
