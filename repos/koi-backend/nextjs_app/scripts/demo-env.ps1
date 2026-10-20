# Dot-source from the application root. Never loads .env.local or stores passwords.
foreach ($demoCredential in @('GOOGLE_APPLICATION_CREDENTIALS','FIREBASE_ADMIN_SDK','FIREBASE_TOKEN','GOOGLE_OAUTH_ACCESS_TOKEN','GOOGLE_CREDENTIALS','FIREBASE_SERVICE_ACCOUNT','KOI_PLATFORM_RULESET_SHA256')) {
  if ([Environment]::GetEnvironmentVariable($demoCredential)) { throw "Credential environment detected. Use a clean local demo shell; refusing to override it." }
}
$demoExpected = @{ KOI_PLATFORM_MODE='emulator'; KOI_PLATFORM_FIREBASE_PROJECT_ID='demo-koi-platform-web1'; FIRESTORE_EMULATOR_HOST='127.0.0.1:5180'; FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:5199' }
foreach ($demoName in $demoExpected.Keys) {
  $demoExisting = [Environment]::GetEnvironmentVariable($demoName)
  if ($demoExisting -and $demoExisting -ne $demoExpected[$demoName]) { throw 'Conflicting platform configuration detected. Use a clean demo shell.' }
}
$env:KOI_PLATFORM_MODE='emulator'
$env:KOI_PLATFORM_FIREBASE_PROJECT_ID='demo-koi-platform-web1'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:5180'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:5199'
$env:NEXT_PUBLIC_KOI_PLATFORM_FIREBASE_PROJECT_ID='demo-koi-platform-web1'
$env:NEXT_PUBLIC_KOI_PLATFORM_AUTH_EMULATOR_URL='http://127.0.0.1:5199'
# The original companion keeps a separate anonymous identity in the same isolated
# emulator. Explicit development-only opt-in; never route demo accounts to live Auth.
$env:NEXT_PUBLIC_KOI_COMPANION_DEMO_EMULATOR='true'
$env:NEXT_PUBLIC_KOI_LOCAL_TEST_ANON='true'
$env:NEXT_PUBLIC_FIREBASE_API_KEY='demo-platform-key'
$env:NEXT_PUBLIC_FIREBASE_PROJECT_ID='demo-koi-platform-web1'
$env:NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN='demo-koi-platform-web1.firebaseapp.com'
$env:NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET='demo-koi-platform-web1.appspot.com'
$env:NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID='000000000000'
$env:NEXT_PUBLIC_FIREBASE_APP_ID='demo-koi-platform-web1'
