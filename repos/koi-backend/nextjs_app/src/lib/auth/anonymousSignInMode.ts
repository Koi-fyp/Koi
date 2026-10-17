/**
 * Development-only switch for using Firebase's client anonymous provider.
 * The server custom-token path remains the default in every other mode.
 */
export function isLocalTestAnonymousSignInEnabled(
  flag: string | undefined = process.env.NEXT_PUBLIC_KOI_LOCAL_TEST_ANON,
  nodeEnv: string | undefined = process.env.NODE_ENV,
): boolean {
  return flag === 'true' && nodeEnv === 'development';
}
