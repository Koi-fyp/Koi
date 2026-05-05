/** @jest-environment jsdom */
import React from 'react';
import { render, waitFor } from '@testing-library/react';
import { AuthProvider, useAuth } from '@/contexts/AuthContext';

function Tester() {
  const auth = useAuth();
  return (
    <div>
      <span data-testid="loading">{String(auth.loading)}</span>
    </div>
  );
}

describe('AuthContext basic', () => {
  it('renders without crashing', async () => {
    const { getByTestId } = render(
      <AuthProvider>
        <Tester />
      </AuthProvider>
    );
    await waitFor(() => expect(getByTestId('loading')).toBeTruthy());
  });
});
