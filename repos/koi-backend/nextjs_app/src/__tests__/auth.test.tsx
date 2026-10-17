/** @jest-environment jsdom */
import React from 'react';
import { fireEvent, render, waitFor } from '@testing-library/react';
const mockAuthInstance = { currentUser: null, app: { options: { projectId: 'koi-companion-fyp' } } };
let configuredAuth: typeof mockAuthInstance | null = null;
let configurationError: Error | null = new Error('Firebase is not configured for this test.');
let localAnonymousMode = false;
const mockOnAuthStateChanged = jest.fn();
const mockClientAnonymousSignIn = jest.fn();
const mockCustomTokenSignIn = jest.fn();
const mockFirebaseSignOut = jest.fn();

jest.doMock('@/lib/firebase', () => ({
  get auth() { return configuredAuth; },
  get firebaseConfigurationError() { return configurationError; },
}));
jest.doMock('@/lib/auth/anonymousSignInMode', () => ({
  isLocalTestAnonymousSignInEnabled: () => localAnonymousMode,
}));
jest.doMock('firebase/auth', () => ({
  onAuthStateChanged: (...args: unknown[]) => mockOnAuthStateChanged(...args),
  signInAnonymously: (...args: unknown[]) => mockClientAnonymousSignIn(...args),
  signInWithCustomToken: (...args: unknown[]) => mockCustomTokenSignIn(...args),
  signOut: (...args: unknown[]) => mockFirebaseSignOut(...args),
}));
const { AuthProvider, useAuth } = require('@/contexts/AuthContext') as typeof import('@/contexts/AuthContext');
const { isLocalTestAnonymousSignInEnabled } = jest.requireActual('@/lib/auth/anonymousSignInMode') as typeof import('@/lib/auth/anonymousSignInMode');

function Tester() {
  const context = useAuth();
  return <div>
    <span data-testid="loading">{String(context.loading)}</span>
    <span data-testid="error">{context.error?.message ?? ''}</span>
    <button onClick={() => void context.signInAnonymously()}>sign in</button>
    <button onClick={() => void context.signOut()}>sign out</button>
  </div>;
}

beforeEach(() => {
  configuredAuth = mockAuthInstance;
  configurationError = null;
  localAnonymousMode = false;
  mockClientAnonymousSignIn.mockReset().mockResolvedValue({ user: { uid: 'genuine-sdk-user' } });
  mockCustomTokenSignIn.mockReset().mockResolvedValue(undefined);
  mockFirebaseSignOut.mockReset().mockResolvedValue(undefined);
  mockOnAuthStateChanged.mockReset().mockImplementation((_auth, callback) => {
    callback(null);
    return jest.fn();
  });
  global.fetch = jest.fn().mockResolvedValue({ ok: true, json: async () => ({ token: 'custom-token' }) }) as typeof fetch;
});

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

  it('uses Firebase client anonymous sign-in only when the dev mode is explicitly enabled', async () => {
    localAnonymousMode = true;
    const view = render(<AuthProvider><Tester /></AuthProvider>);
    fireEvent.click(view.getByRole('button', { name: 'sign in' }));
    await waitFor(() => expect(mockClientAnonymousSignIn).toHaveBeenCalledWith(mockAuthInstance));
    expect(global.fetch).not.toHaveBeenCalled();
    expect(mockCustomTokenSignIn).not.toHaveBeenCalled();
  });

  it('keeps the existing API custom-token flow when local mode is disabled', async () => {
    const view = render(<AuthProvider><Tester /></AuthProvider>);
    fireEvent.click(view.getByRole('button', { name: 'sign in' }));
    await waitFor(() => expect(mockCustomTokenSignIn).toHaveBeenCalledWith(mockAuthInstance, 'custom-token'));
    expect(global.fetch).toHaveBeenCalledWith('/api/auth/anonymous', { method: 'POST' });
    expect(mockClientAnonymousSignIn).not.toHaveBeenCalled();
  });

  it('rejects local mode if the initialized Auth belongs to another Firebase project', async () => {
    localAnonymousMode = true;
    mockAuthInstance.app.options.projectId = 'unexpected-project';
    const view = render(<AuthProvider><Tester /></AuthProvider>);
    fireEvent.click(view.getByRole('button', { name: 'sign in' }));
    await waitFor(() => expect(view.getByTestId('error')).toHaveTextContent(/requires the koi-companion-fyp/i));
    expect(mockClientAnonymousSignIn).not.toHaveBeenCalled();
    expect(global.fetch).not.toHaveBeenCalled();
    mockAuthInstance.app.options.projectId = 'koi-companion-fyp';
  });

  it('reports a disabled Firebase Anonymous provider without falling back to custom tokens', async () => {
    localAnonymousMode = true;
    mockClientAnonymousSignIn.mockRejectedValueOnce(Object.assign(new Error('provider disabled'), { code: 'auth/operation-not-allowed' }));
    const view = render(<AuthProvider><Tester /></AuthProvider>);
    fireEvent.click(view.getByRole('button', { name: 'sign in' }));
    await waitFor(() => expect(mockClientAnonymousSignIn).toHaveBeenCalled());
    await waitFor(() => expect(view.getByTestId('error')).toHaveTextContent(/Anonymous sign-in is disabled/i));
    expect(mockClientAnonymousSignIn).toHaveBeenCalledWith(mockAuthInstance);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('requires an initialized Auth instance and reports missing configuration', async () => {
    configuredAuth = null;
    configurationError = new Error('Firebase client configuration is missing.');
    localAnonymousMode = true;
    const view = render(<AuthProvider><Tester /></AuthProvider>);
    fireEvent.click(view.getByRole('button', { name: 'sign in' }));
    await waitFor(() => expect(view.getByTestId('error')).toHaveTextContent(/configuration is missing/i));
    expect(mockClientAnonymousSignIn).not.toHaveBeenCalled();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('signs out through Firebase and the local flag cannot activate outside development', async () => {
    expect(isLocalTestAnonymousSignInEnabled('true', 'production')).toBe(false);
    expect(isLocalTestAnonymousSignInEnabled('true', 'test')).toBe(false);
    expect(isLocalTestAnonymousSignInEnabled('false', 'development')).toBe(false);
    expect(isLocalTestAnonymousSignInEnabled('true', 'development')).toBe(true);

    const view = render(<AuthProvider><Tester /></AuthProvider>);
    fireEvent.click(view.getByRole('button', { name: 'sign out' }));
    await waitFor(() => expect(mockFirebaseSignOut).toHaveBeenCalledWith(mockAuthInstance));
  });
});
