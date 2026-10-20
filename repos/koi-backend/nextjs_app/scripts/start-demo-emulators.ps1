param([switch]$Fresh)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/demo-env.ps1"
$demoRoot = (Resolve-Path "$PSScriptRoot/..").Path
if ((Get-Location).Path -ne $demoRoot) { throw 'Run this script from nextjs_app.' }
node scripts/koi-demo-preflight.cjs
if ($LASTEXITCODE -ne 0) { throw 'Demo guards failed.' }
$demoSnapshot = Join-Path $demoRoot '.local/koi-demo/export'
$demoArguments = @('--yes','--package','firebase-tools@15.34.0','firebase','emulators:start','--only','auth,firestore','--project','demo-koi-platform-web1','--config','dev/platform-emulator/firebase.json')
if (-not $Fresh) {
  $demoArguments += "--export-on-exit=$demoSnapshot"
  if (Test-Path -LiteralPath (Join-Path $demoSnapshot 'firebase-export-metadata.json')) { $demoArguments += "--import=$demoSnapshot" }
}
# Fresh is a non-deleting, disposable session. It neither imports nor overwrites snapshots.
# The npm PowerShell shim reparses its invocation text and mishandles splatted
# arguments on some npm versions. Invoke the native Windows shim directly.
& npx.cmd @demoArguments
if ($LASTEXITCODE -ne 0) { throw "Demo emulators exited with code $LASTEXITCODE." }
