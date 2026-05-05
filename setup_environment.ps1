#Requires -Version 5.1
<#
.SYNOPSIS
    KOI Development Environment Setup Script — Windows

.DESCRIPTION
    Automated one-shot setup for the KOI AI companion development environment.
    Installs: Flutter SDK, Node.js 20 LTS (via NVM-Windows), Android SDK hints,
              Git/SSH keys, and VS Code extensions.

    Safe to run multiple times (idempotent — checks before installing).
    Rolls back components installed by *this run* if a later step fails.

.PARAMETER InstallAndroid
    Attempt to auto-install Android command-line tools (requires internet).

.PARAMETER SkipVSCode
    Skip VS Code extension installation.

.PARAMETER Help
    Show this help message.

.EXAMPLE
    .\setup_environment.ps1
    .\setup_environment.ps1 -InstallAndroid
    .\setup_environment.ps1 -SkipVSCode

.NOTES
    Version   : 1.0.0
    Run as    : Regular user (NOT Administrator). UAC prompts appear as needed.
    Exit codes: 0 = success, 1 = failure
#>

[CmdletBinding()]
param(
    [switch]$InstallAndroid,
    [switch]$SkipVSCode,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# CONSTANTS
# =============================================================================
$Script:VERSION           = '1.0.0'
$Script:LOG_FILE          = Join-Path $PWD 'setup.log'
$Script:FLUTTER_MIN_MAJ   = 3
$Script:FLUTTER_MIN_MIN   = 19
$Script:NODE_REQUIRED     = 20
$Script:ANDROID_API       = 34

# Track what this run installed for rollback
$Script:InstalledComponents = [System.Collections.Generic.List[string]]::new()

# =============================================================================
# ANSI COLORS  (Win10+ supports VT sequences in ConHost and Windows Terminal)
# =============================================================================
function Enable-AnsiColors {
    try {
        $kernel32 = Add-Type -MemberDefinition @'
            [DllImport("kernel32.dll", SetLastError=true)]
            public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
            [DllImport("kernel32.dll", SetLastError=true)]
            public static extern IntPtr GetStdHandle(int nStdHandle);
            [DllImport("kernel32.dll", SetLastError=true)]
            public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
'@ -Name 'Kernel32' -Namespace 'Win32' -PassThru
        $handle = [Win32.Kernel32]::GetStdHandle(-11)
        $mode   = 0
        [void][Win32.Kernel32]::GetConsoleMode($handle, [ref]$mode)
        [void][Win32.Kernel32]::SetConsoleMode($handle, $mode -bor 4)
    }
    catch { }  # Silently ignore — colours just won't render in older hosts
}

Enable-AnsiColors
$Script:RED    = "`e[0;31m"
$Script:GREEN  = "`e[0;32m"
$Script:YELLOW = "`e[1;33m"
$Script:BLUE   = "`e[0;34m"
$Script:NC     = "`e[0m"

# =============================================================================
# LOGGING
# =============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')]
        [string]$Level = 'INFO'
    )

    $ts      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "[$ts] [$Level] $Message"
    Add-Content -Path $Script:LOG_FILE -Value $logLine -Encoding UTF8

    switch ($Level) {
        'ERROR'   { Write-Host "$($Script:RED)[ERROR]$($Script:NC) $Message" }
        'WARN'    { Write-Host "$($Script:YELLOW)[WARN]$($Script:NC)  $Message" }
        'SUCCESS' { Write-Host "$($Script:GREEN)[OK]$($Script:NC)    $Message" }
        default   { Write-Host "$($Script:BLUE)[INFO]$($Script:NC)  $Message" }
    }
}

function Write-Section {
    param([string]$Title)
    $sep = '=' * 50
    Write-Log $sep
    Write-Log "  $Title"
    Write-Log $sep
}

function Write-Warn  { param([string]$M) Write-Log $M 'WARN'    }
function Write-OK    { param([string]$M) Write-Log $M 'SUCCESS' }
function Write-Fail  {
    param([string]$M)
    Write-Log $M 'ERROR'
    Invoke-Rollback
    exit 1
}

# =============================================================================
# ROLLBACK
# =============================================================================

function Invoke-Rollback {
    if ($Script:InstalledComponents.Count -eq 0) { return }

    Write-Warn "Rolling back: $($Script:InstalledComponents -join ', ')"

    foreach ($component in $Script:InstalledComponents) {
        switch ($component) {
            'flutter' {
                $p = "$env:USERPROFILE\flutter"
                if (Test-Path $p) {
                    Write-Warn "Removing Flutter from $p..."
                    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            'nvm-windows' {
                $p = "$env:APPDATA\nvm"
                if (Test-Path $p) {
                    Write-Warn "Removing NVM for Windows from $p..."
                    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    Write-Warn "Rollback complete. Check setup.log for details."
}

# =============================================================================
# UTILITIES
# =============================================================================

function Test-CommandExists {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Compare-VersionGe {
    param([int]$Maj1, [int]$Min1, [int]$Maj2, [int]$Min2)
    if ($Maj1 -gt $Maj2) { return $true }
    if ($Maj1 -eq $Maj2 -and $Min1 -ge $Min2) { return $true }
    return $false
}

function Add-ToUserPath {
    param([string]$NewPath)
    $current = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($current -notlike "*$NewPath*") {
        [System.Environment]::SetEnvironmentVariable('PATH', "$current;$NewPath", 'User')
        $env:PATH = "$env:PATH;$NewPath"
        Write-Log "PATH updated: added $NewPath"
    }
}

function Invoke-Download {
    param([string]$Url, [string]$Destination)
    Write-Log "Downloading: $Url"
    try {
        $prev = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        $ProgressPreference = $prev
    }
    catch {
        Write-Fail "Download failed ($Url): $_"
    }
}

function Refresh-Path {
    $machine = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = "$machine;$user"
}

function Get-BestPackageManager {
    foreach ($tool in 'winget', 'choco', 'scoop') {
        if (Test-CommandExists $tool) { return $tool }
    }
    return $null
}

# =============================================================================
# FLUTTER
# =============================================================================

function Test-Flutter {
    Write-Log "Checking Flutter SDK..."

    # Also check the default install location
    $defaultFlutter = "$env:USERPROFILE\flutter\bin\flutter.bat"
    if (-not (Test-CommandExists 'flutter') -and (Test-Path $defaultFlutter)) {
        Add-ToUserPath "$env:USERPROFILE\flutter\bin"
    }

    if (-not (Test-CommandExists 'flutter')) {
        Write-Warn "Flutter not found in PATH"
        return $false
    }

    try {
        $out = flutter --version 2>$null | Select-Object -First 1
        if ($out -match 'Flutter (\d+)\.(\d+)') {
            $maj = [int]$Matches[1]
            $min = [int]$Matches[2]
            if (Compare-VersionGe $maj $min $Script:FLUTTER_MIN_MAJ $Script:FLUTTER_MIN_MIN) {
                Write-OK "Flutter $maj.$min found (>= $($Script:FLUTTER_MIN_MAJ).$($Script:FLUTTER_MIN_MIN))"
                return $true
            }
            Write-Warn "Flutter $maj.$min < required $($Script:FLUTTER_MIN_MAJ).$($Script:FLUTTER_MIN_MIN)"
        }
    }
    catch { Write-Warn "Error reading Flutter version: $_" }

    return $false
}

function Install-Flutter {
    Write-Log "Installing Flutter SDK..."

    $flutterDir = "$env:USERPROFILE\flutter"

    # Try winget first (fastest, no temp file)
    $pm = Get-BestPackageManager
    if ($pm -eq 'winget') {
        Write-Log "Attempting Flutter install via winget..."
        try {
            winget install Google.Flutter `
                --accept-package-agreements `
                --accept-source-agreements `
                --silent 2>$null
            Refresh-Path
            if (Test-Flutter) {
                $Script:InstalledComponents.Add('flutter')
                return
            }
        }
        catch { Write-Warn "winget install failed — falling back to manual download" }
    }

    # Manual download fallback
    $zipDest = "$env:TEMP\flutter_windows_latest.zip"
    $flutterUrl = 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_latest.zip'

    Invoke-Download $flutterUrl $zipDest

    Write-Log "Extracting Flutter to $env:USERPROFILE..."
    try {
        Expand-Archive -Path $zipDest -DestinationPath $env:USERPROFILE -Force
        Remove-Item $zipDest -Force
    }
    catch { Write-Fail "Flutter extraction failed: $_" }

    Add-ToUserPath "$flutterDir\bin"
    $env:PATH = "$flutterDir\bin;$env:PATH"

    # Disable telemetry
    flutter config --no-analytics 2>$null

    $Script:InstalledComponents.Add('flutter')
    Write-OK "Flutter installed. Restart terminal to use 'flutter' command."
}

# =============================================================================
# NODE.JS  (via NVM-Windows)
# =============================================================================

function Update-NvmPath {
    $nvmHome = "$env:APPDATA\nvm"
    if (Test-Path $nvmHome) {
        $env:NVM_HOME    = $nvmHome
        $env:NVM_SYMLINK = "$env:ProgramFiles\nodejs"
        $env:PATH        = "$nvmHome;$env:NVM_SYMLINK;$env:PATH"
    }
}

function Test-Node {
    Write-Log "Checking Node.js..."
    Update-NvmPath

    if (-not (Test-CommandExists 'node')) {
        Write-Warn "Node.js not found in PATH"
        return $false
    }

    try {
        $ver = node --version 2>$null
        if ($ver -match 'v(\d+)') {
            $maj = [int]$Matches[1]
            if ($maj -eq $Script:NODE_REQUIRED) {
                Write-OK "Node.js $ver found (exactly v$($Script:NODE_REQUIRED).x)"
                return $true
            }
            Write-Warn "Node.js $ver found but v$($Script:NODE_REQUIRED).x required"
        }
    }
    catch { Write-Warn "Error reading Node.js version: $_" }

    return $false
}

function Install-Node {
    Write-Log "Installing Node.js v$($Script:NODE_REQUIRED) LTS..."

    $nvmExe = "$env:APPDATA\nvm\nvm.exe"

    if (-not (Test-Path $nvmExe)) {
        Write-Log "Installing NVM for Windows..."

        $nvmInstallerUrl = 'https://github.com/coreybutler/nvm-windows/releases/latest/download/nvm-setup.exe'
        $nvmInstaller    = "$env:TEMP\nvm-setup.exe"

        Invoke-Download $nvmInstallerUrl $nvmInstaller

        Write-Log "Running NVM installer (a UAC prompt may appear)..."
        try {
            $proc = Start-Process -FilePath $nvmInstaller -ArgumentList '/S' -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                Write-Fail "NVM installer exited with code $($proc.ExitCode)"
            }
        }
        catch { Write-Fail "NVM installation failed: $_" }
        finally { Remove-Item $nvmInstaller -Force -ErrorAction SilentlyContinue }

        $Script:InstalledComponents.Add('nvm-windows')
        Refresh-Path
        Update-NvmPath
    }

    if (-not (Test-Path $nvmExe)) {
        Write-Fail "NVM executable not found after install. Restart terminal and re-run."
    }

    Write-Log "Installing Node.js v$($Script:NODE_REQUIRED)..."
    & $nvmExe install $Script:NODE_REQUIRED
    & $nvmExe use $Script:NODE_REQUIRED

    Refresh-Path
    Update-NvmPath
    Write-OK "Node.js v$($Script:NODE_REQUIRED) installed via NVM"
}

# =============================================================================
# ANDROID SDK
# =============================================================================

function Find-AndroidSdkRoot {
    $candidates = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        "$env:LOCALAPPDATA\Android\Sdk",
        "$env:USERPROFILE\AppData\Local\Android\Sdk"
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

function Test-AndroidSdk {
    Write-Log "Checking Android SDK..."

    $sdkRoot = Find-AndroidSdkRoot
    if (-not $sdkRoot) {
        Write-Warn "ANDROID_HOME not set and SDK not found in common locations"
        return $false
    }

    $env:ANDROID_HOME     = $sdkRoot
    $env:ANDROID_SDK_ROOT = $sdkRoot

    $apiPath = Join-Path $sdkRoot "platforms\android-$($Script:ANDROID_API)"
    if (Test-Path $apiPath) {
        Write-OK "Android SDK at $sdkRoot with API $($Script:ANDROID_API)"
        return $true
    }

    Write-Warn "Android SDK at $sdkRoot but API $($Script:ANDROID_API) not installed"
    return $false
}

function Install-AndroidSdk {
    Write-Log "Configuring Android SDK..."

    $sdkRoot = Find-AndroidSdkRoot
    if (-not $sdkRoot) {
        $sdkRoot = "$env:LOCALAPPDATA\Android\Sdk"
    }

    $cmdlineToolsDir = Join-Path $sdkRoot 'cmdline-tools\latest'
    $sdkManagerExe  = Join-Path $cmdlineToolsDir 'bin\sdkmanager.bat'

    if (-not (Test-Path $sdkManagerExe)) {
        Write-Log "Downloading Android command-line tools..."
        $toolsUrl  = 'https://dl.google.com/android/repository/commandlinetools-win-latest.zip'
        $toolsZip  = "$env:TEMP\cmdline_tools.zip"

        Invoke-Download $toolsUrl $toolsZip

        New-Item -ItemType Directory -Path (Join-Path $sdkRoot 'cmdline-tools') -Force | Out-Null
        Expand-Archive -Path $toolsZip -DestinationPath (Join-Path $sdkRoot 'cmdline-tools') -Force
        Remove-Item $toolsZip -Force

        # Rename extracted folder to 'latest'
        $extracted = Join-Path $sdkRoot 'cmdline-tools\cmdline-tools'
        if ((Test-Path $extracted) -and (-not (Test-Path $cmdlineToolsDir))) {
            Rename-Item $extracted $cmdlineToolsDir
        }
    }

    if (-not (Test-Path $sdkManagerExe)) {
        Write-Warn "sdkmanager not found. Install Android Studio and run:"
        Write-Warn "  sdkmanager 'platforms;android-$($Script:ANDROID_API)' 'build-tools;34.0.0' 'platform-tools'"
        Write-Warn "Android Studio: https://developer.android.com/studio"
        return
    }

    Write-Log "Accepting SDK licenses..."
    'y' * 10 | & $sdkManagerExe --licenses 2>$null

    Write-Log "Installing API $($Script:ANDROID_API) + build-tools + platform-tools..."
    & $sdkManagerExe `
        "platforms;android-$($Script:ANDROID_API)" `
        'build-tools;34.0.0' `
        'platform-tools'

    [System.Environment]::SetEnvironmentVariable('ANDROID_HOME',     $sdkRoot, 'User')
    [System.Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $sdkRoot, 'User')
    $env:ANDROID_HOME     = $sdkRoot
    $env:ANDROID_SDK_ROOT = $sdkRoot

    Write-OK "Android SDK API $($Script:ANDROID_API) installed"
}

# =============================================================================
# GIT SSH
# =============================================================================

function Test-GitSsh {
    Write-Log "Checking Git SSH configuration..."

    if (-not (Test-CommandExists 'git')) {
        Write-Warn "Git not found in PATH"
        return $false
    }

    $sshDir  = "$env:USERPROFILE\.ssh"
    $hasKey  = @('id_ed25519','id_rsa','id_ecdsa') |
               Where-Object { Test-Path (Join-Path $sshDir $_) } |
               Select-Object -First 1

    if (-not $hasKey) {
        Write-Warn "No SSH keys found in $sshDir"
        return $false
    }

    try {
        $result = & ssh -T git@github.com `
                        -o StrictHostKeyChecking=no `
                        -o ConnectTimeout=10 2>&1
        if ($result -match 'successfully authenticated') {
            Write-OK "Git SSH to github.com confirmed"
            return $true
        }
    }
    catch { }

    Write-Warn "SSH keys exist but GitHub auth failed"
    return $false
}

function Setup-GitSsh {
    Write-Log "Setting up Git SSH..."

    # Install Git if missing
    if (-not (Test-CommandExists 'git')) {
        $pm = Get-BestPackageManager
        if ($pm -eq 'winget') {
            winget install Git.Git --accept-package-agreements --accept-source-agreements --silent
            Refresh-Path
        }
        else {
            Write-Fail "Git not found. Install from https://git-scm.com and re-run."
        }
    }

    $sshDir  = "$env:USERPROFILE\.ssh"
    $keyFile = Join-Path $sshDir 'id_ed25519'

    if (-not (Test-Path $keyFile)) {
        Write-Log "Generating ED25519 SSH key..."
        if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }

        $gitEmail = (git config --global user.email 2>$null)
        if (-not $gitEmail) { $gitEmail = 'koi-dev@example.com' }

        & ssh-keygen -t ed25519 -C $gitEmail -f $keyFile -N '""'
        Write-OK "SSH key generated: $keyFile"
    }

    # Start the built-in OpenSSH agent service (Windows 10+)
    $svc = Get-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.StartType -eq 'Disabled') {
            Set-Service -Name 'ssh-agent' -StartupType Manual
        }
        if ($svc.Status -ne 'Running') {
            Start-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue
        }
    }

    & ssh-add $keyFile 2>$null

    Write-Warn "============================================================"
    Write-Warn "ACTION REQUIRED: Add your SSH key to GitHub"
    Write-Warn "============================================================"
    Write-Warn "1. Copy this key:"
    Write-Host ""
    Get-Content "$keyFile.pub"
    Write-Host ""
    Write-Warn "2. Open https://github.com/settings/keys"
    Write-Warn "3. Click 'New SSH key', paste the key above, save."
    Write-Warn "============================================================"
}

# =============================================================================
# VS CODE EXTENSIONS
# =============================================================================

function Test-VsCodeExtensions {
    Write-Log "Checking VS Code extensions..."

    if (-not (Test-CommandExists 'code')) {
        Write-Warn "VS Code CLI ('code') not in PATH"
        return $false
    }

    $required = @(
        'dart-code.dart-code'
        'dart-code.flutter'
        'dbaeumer.vscode-eslint'
        'esbenp.prettier-vscode'
        'eamodio.gitlens'
        'jsayol.firebase-explorer'
    )

    $installed = (code --list-extensions 2>$null) | ForEach-Object { $_.ToLower() }
    $missing   = $required | Where-Object { $_ -notin $installed }

    if ($missing.Count -eq 0) {
        Write-OK "All required VS Code extensions installed"
        return $true
    }

    Write-Warn "$($missing.Count) extensions missing"
    return $false
}

function Install-VsCodeExtensions {
    Write-Log "Installing VS Code extensions..."

    if (-not (Test-CommandExists 'code')) {
        Write-Warn "VS Code CLI not found — install extensions from .vscode/extensions.json"
        return
    }

    $extensions = @(
        'dart-code.dart-code'
        'dart-code.flutter'
        'dbaeumer.vscode-eslint'
        'esbenp.prettier-vscode'
        'eamodio.gitlens'
        'jsayol.firebase-explorer'
        'ms-vscode.vscode-typescript-next'
        'bradlc.vscode-tailwindcss'
    )

    foreach ($ext in $extensions) {
        Write-Log "Installing: $ext"
        code --install-extension $ext --force 2>$null
        Write-OK "  $ext"
    }
}

# =============================================================================
# ENVIRONMENT REPORT
# =============================================================================

function New-EnvironmentReport {
    Write-Log "Generating environment report..."

    $reportFile = Join-Path $PWD 'environment_report.md'
    $timestamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $osVersion  = [System.Environment]::OSVersion.Version

    $flutterVer = if (Test-CommandExists 'flutter') {
        (flutter --version 2>$null | Select-String 'Flutter (\d+\.\d+\.\d+)' |
         ForEach-Object { $_.Matches[0].Groups[1].Value }) ?? 'Unknown'
    } else { 'Not installed' }

    $nodeVer   = if (Test-CommandExists 'node') { node --version 2>$null } else { 'Not installed' }
    $gitVer    = if (Test-CommandExists 'git')  { git --version 2>$null  } else { 'Not installed' }

    $nodeMajor = if ($nodeVer -match 'v(\d+)') { [int]$Matches[1] } else { 0 }

    $sdkRoot       = Find-AndroidSdkRoot
    $androidStatus = if ($sdkRoot -and (Test-Path (Join-Path $sdkRoot "platforms\android-$($Script:ANDROID_API)"))) {
        "✓ API $($Script:ANDROID_API) @ $sdkRoot"
    } else { "✗ Not configured" }

    $flutterStatus = if ($flutterVer -ne 'Not installed') { '✓' } else { '✗' }
    $nodeStatus    = if ($nodeMajor -eq $Script:NODE_REQUIRED) { '✓' } else { '✗' }
    $gitStatus     = if ($gitVer -ne 'Not installed') { '✓' } else { '✗' }

    $flutterDoctor = if (Test-CommandExists 'flutter') {
        flutter doctor 2>&1 | Out-String
    } else { 'Flutter not available' }

    $report = @"
# KOI Development Environment Report

**Generated:** $timestamp
**OS:** Windows $osVersion
**Script version:** $($Script:VERSION)

## Component Status

| Component | Required | Installed | Status |
|-----------|----------|-----------|--------|
| Flutter | >= $($Script:FLUTTER_MIN_MAJ).$($Script:FLUTTER_MIN_MIN) | $flutterVer | $flutterStatus |
| Node.js | = $($Script:NODE_REQUIRED).x LTS | $nodeVer | $nodeStatus |
| Git | Latest | $gitVer | $gitStatus |
| Android SDK | API $($Script:ANDROID_API) | $androidStatus | |

## Flutter Doctor Output

``````
$flutterDoctor
``````

## Environment Variables

| Variable | Value |
|----------|-------|
| ANDROID_HOME | $($env:ANDROID_HOME ?? 'Not set') |
| ANDROID_SDK_ROOT | $($env:ANDROID_SDK_ROOT ?? 'Not set') |
| NVM_HOME | $($env:NVM_HOME ?? 'Not set') |

## Next Steps

1. **Restart PowerShell** to apply PATH changes
2. Run ``.\validate_environment.sh`` (via Git Bash) or the PowerShell equivalent
3. Run ``.\test\test_environment_setup.sh`` for automated tests
4. If SSH was prompted, add your public key to GitHub

---
*Generated by KOI setup_environment.ps1 v$($Script:VERSION)*
"@

    Set-Content -Path $reportFile -Value $report -Encoding UTF8
    Write-OK "Environment report written to $reportFile"
}

# =============================================================================
# MAIN
# =============================================================================

function Main {
    if ($Help) {
        Get-Help $MyInvocation.MyCommand.Path -Detailed
        exit 0
    }

    # Ensure log is writable
    try { Add-Content -Path $Script:LOG_FILE -Value '' -Encoding UTF8 }
    catch { Write-Error "Cannot write to $($Script:LOG_FILE)"; exit 1 }

    Write-Section "KOI Development Environment Setup v$($Script:VERSION)"
    Write-Log "Timestamp  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "OS         : Windows $([System.Environment]::OSVersion.Version)"
    Write-Log "PowerShell : $($PSVersionTable.PSVersion)"
    Write-Log "Log file   : $($Script:LOG_FILE)"

    # ---- Flutter ----
    Write-Section "Flutter SDK"
    if (-not (Test-Flutter)) { Install-Flutter }

    # ---- Node.js ----
    Write-Section "Node.js (via NVM-Windows)"
    if (-not (Test-Node)) { Install-Node }

    # ---- Android SDK ----
    Write-Section "Android SDK"
    if (-not (Test-AndroidSdk)) {
        if ($InstallAndroid) {
            Install-AndroidSdk
        }
        else {
            Write-Warn "Android SDK not configured."
            Write-Warn "Options:"
            Write-Warn "  a) Install Android Studio: https://developer.android.com/studio"
            Write-Warn "  b) Re-run: .\setup_environment.ps1 -InstallAndroid"
            Write-Warn "Note: Android only required for mobile target."
        }
    }

    # ---- Git SSH ----
    Write-Section "Git SSH"
    if (-not (Test-GitSsh)) { Setup-GitSsh }

    # ---- VS Code Extensions ----
    if (-not $SkipVSCode) {
        Write-Section "VS Code Extensions"
        if (-not (Test-VsCodeExtensions)) { Install-VsCodeExtensions }
    }

    # ---- Report ----
    Write-Section "Environment Report"
    New-EnvironmentReport

    Write-Section "Setup Complete"
    Write-OK "KOI environment setup finished!"
    Write-Log "Next: .\validate_environment.sh  — detailed validation (Git Bash)"
    Write-Log "Next: .\test\test_environment_setup.sh — automated tests"
    Write-Log "Log:  $($Script:LOG_FILE)"
    Write-Host ""
    Write-Warn "IMPORTANT: Restart PowerShell/terminal to apply all PATH changes!"
}

Main
