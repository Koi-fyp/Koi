param([Parameter(Mandatory=$true)][string]$ServiceAccountFile,[Parameter(Mandatory=$true)][string]$RulesEvidenceFile)
# Dot-source in a private operator/server shell. Reads local files; no cloud requests.
$ErrorActionPreference='Stop'
foreach($web5Name in @('FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST','NEXT_PUBLIC_KOI_PLATFORM_AUTH_EMULATOR_URL')) { if([Environment]::GetEnvironmentVariable($web5Name)){throw 'Emulator variables detected. Use a clean cloud shell.'} }
if($env:NEXT_PUBLIC_KOI_COMPANION_DEMO_EMULATOR -eq 'true'){throw 'Companion demo emulator flag must be absent.'}
try { $web5Credential=Get-Content -LiteralPath $ServiceAccountFile -Raw | ConvertFrom-Json } catch { throw 'Private credential file unavailable or invalid; contents omitted.' }
if($web5Credential.project_id -ne 'koi-companion-fyp' -or $web5Credential.type -ne 'service_account'){throw 'The existing Firebase project credential is required.'}
try { $web5Evidence=Get-Content -LiteralPath $RulesEvidenceFile -Raw | ConvertFrom-Json } catch { throw 'Rules evidence file unavailable or invalid; contents omitted.' }
if($web5Evidence.project -ne 'koi-companion-fyp' -or $web5Evidence.live_release_verified -ne $true){throw 'Verified live rules evidence is required.'}
if(-not $env:KOI_PLATFORM_CURSOR_SIGNING_KEY -or $env:KOI_PLATFORM_CURSOR_SIGNING_KEY.Length -lt 32){throw 'Set a persistent private cursor signing key of at least 32 characters first.'}
$env:FIREBASE_ADMIN_SDK=Get-Content -LiteralPath $ServiceAccountFile -Raw
$env:KOI_PLATFORM_MODE='reviewed-production'
$env:KOI_PLATFORM_FIREBASE_PROJECT_ID='koi-companion-fyp'
$env:NEXT_PUBLIC_KOI_PLATFORM_FIREBASE_PROJECT_ID='koi-companion-fyp'
$env:KOI_PLATFORM_RULESET_SHA256=$web5Evidence.rules_sha256
$env:KOI_PLATFORM_RULES_EVIDENCE_PATH=(Resolve-Path -LiteralPath $RulesEvidenceFile).Path
node -e "try { require('./src/lib/platform/server/admin-config.cjs').configuration(); console.log('Existing Firebase cloud configuration validated locally; no cloud writes.'); } catch { console.error('Cloud configuration remains blocked; private diagnostics omitted.'); process.exitCode=1; }"
if($LASTEXITCODE -ne 0){throw 'Cloud configuration remains blocked.'}
# Public Firebase values continue to come from the existing .env.local. No file is edited.
