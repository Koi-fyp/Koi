/** @jest-environment jsdom */
import React from 'react';
import { render, waitFor } from '@testing-library/react';
const mockAuthInstance = { currentUser: null };
let configuredAuth: typeof mockAuthInstance | null = null;
let configurationError: Error | null = new Error('Firebase is not configured for this test.');
const mockOnAuthStateChanged = jest.fn();

jest.doMock('@/lib/firebase', () => ({
  get auth() { return configuredAuth; },
  get firebaseConfigurationError() { return configurationError; },
}));
jest.doMock('firebase/auth', () => ({
  onAuthStateChanged: (...args: unknown[]) => mockOnAuthStateChanged(...args),
  signInWithCustomToken: jest.fn(),
  signOut: jest.fn(),
}));
const { AuthProvider, useAuth } = require('@/contexts/AuthContext') as typeof import('@/contexts/AuthContext');

function Tester() {
  const context = useAuth();
  return <div><span data-testid="loading">{String(context.loading)}</span><span data-testid="error">{context.error?.message ?? ''}</span></div>;
}

describe('AuthContext basic', () => {
  it('renders without crashing', async () => {
    configuredAuth = null;
    configurationError = new Error('Firebase is not configured for this test.');
    mockOnAuthStateChanged.mockReset();
    const { getByTestId } = render(<AuthProvider><Tester /></AuthProvider>);
    await waitFor(() => expect(getByTestId('loading')).toHaveTextContent('false'));
    expect(getByTestId('error')).toHaveTextContent(/not configured/i);
    expect(mockOnAuthStateChanged).not.toHaveBeenCalled();
  });

  it('registers the modular auth listener and unsubscribes on unmount when configured', async () => {
    const unsubscribe = jest.fn();
    configuredAuth = mockAuthInstance;
    configurationError = null;
    mockOnAuthStateChanged.mockReset().mockImplementation((_auth, callback) => {
      callback(null);
      return unsubscribe;
    });

    const view = render(<AuthProvider><Tester /></AuthProvider>);
    await waitFor(() => expect(mockOnAuthStateChanged).toHaveBeenCalledTimes(1));
    expect(mockOnAuthStateChanged.mock.calls[0][0]).toBe(mockAuthInstance);
    expect(view.getByTestId('error')).toBeEmptyDOMElement();

    view.unmount();
    expect(unsubscribe).toHaveBeenCalledTimes(1);
  });
});
