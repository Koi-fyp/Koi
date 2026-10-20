param([Parameter(Mandatory=$true)][string]$RunId,[Parameter(Mandatory=$true)][string]$ManifestFile)
# Run ONLY after the owner explicitly authorizes cloud provisioning.
$ErrorActionPreference='Stop'
$web5Confirmation=Read-Host 'Type koi-companion-fyp to confirm the existing project for CLOUD WRITES'
if($web5Confirmation -cne 'koi-companion-fyp'){throw 'Project confirmation did not match.'}
$web5Authorization=Read-Host 'Type PROVISION FICTIONAL KOI DEMO to authorize these new fictional records'
if($web5Authorization -cne 'PROVISION FICTIONAL KOI DEMO'){throw 'Cloud write authorization did not match.'}
try {
  foreach($web5Role in @('PSYCHOLOGIST','GENERAL','PATIENT')) {
    $web5Secret=Read-Host "Choose $web5Role fictional account password (12-128 characters)" -AsSecureString
    try { [Environment]::SetEnvironmentVariable("KOI_WEB5_${web5Role}_PASSWORD",[System.Net.NetworkCredential]::new('',$web5Secret).Password,'Process') } finally { $web5Secret.Dispose() }
  }
  $env:KOI_WEB5_CLOUD_WRITE_AUTHORIZATION='PROVISION_FICTIONAL_KOI_DEMO'
  node scripts/web5-provision.cjs --apply --run-id $RunId --confirm-project koi-companion-fyp --output $ManifestFile
  if($LASTEXITCODE -ne 0){throw 'Provisioning stopped; preserve the run ledger for inspection/resume.'}
} finally {
  foreach($web5Role in @('PSYCHOLOGIST','GENERAL','PATIENT')){[Environment]::SetEnvironmentVariable("KOI_WEB5_${web5Role}_PASSWORD",$null,'Process')}
  Remove-Item Env:\KOI_WEB5_CLOUD_WRITE_AUTHORIZATION -ErrorAction SilentlyContinue
}
