#Requires -RunAsAdministrator
#Requires -Version 5.1

param(
    [string]$Domain = "yourdomain.com",
    [string]$LogPath = "$PSScriptRoot\deploy-apps-$(Get-Date -Format 'yyyyMMdd-HHmmss').log",
    [switch]$SkipGCPWConfig
)

# Setup error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$script:installationsFailed = @()
$script:installationsSucceeded = @()

# Start logging
$null = Start-Transcript -Path $LogPath -Append

trap {
    Write-Error "Unexpected error occurred: $_"
    Stop-Transcript
    exit 1
}

Write-Host "Deploy-Apps Script started at $(Get-Date)" -ForegroundColor Cyan
Write-Host "Log file: $LogPath" -ForegroundColor Gray

# Validate winget is available
Write-Host "Validating winget availability..." -ForegroundColor Cyan
try {
    $wingetVersion = winget --version 2>$null
    if (-not $wingetVersion) {
        throw "Winget not found in PATH"
    }
    Write-Host "Found winget: $wingetVersion" -ForegroundColor Green
} catch {
    Write-Error "Winget is not installed or not accessible. Please install App Installer from Microsoft Store."
    Stop-Transcript
    exit 1
}

# Update Winget package sources to prevent hash mismatch errors
Write-Host "Updating Winget sources..." -ForegroundColor Cyan
try {
    winget source update 2>&1 | Tee-Object -Variable updateOutput
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Winget source update completed with warnings (Exit code: $LASTEXITCODE)"
    } else {
        Write-Host "Winget sources updated successfully." -ForegroundColor Green
    }
} catch {
    Write-Error "Failed to update winget sources: $_"
    Write-Host "Continuing with installation attempts..." -ForegroundColor Yellow
}

# Define Winget Package IDs
$apps = @(
    "Google.Chrome",
    "Google.CredentialProviderForWindows",
    "Google.GoogleDrive",
    "TeamViewer.TeamViewer.Host",
    "pseymour.MakeMeAdmin",
    "DisplayLink.GraphicsDriver",
    "Adobe.Acrobat.Reader.64-bit"
)

# Loop and install each app silently
$appsCount = $apps.Count
$currentIndex = 0

foreach ($app in $apps) {
    $currentIndex++
    $progressPercent = [math]::Round(($currentIndex / $appsCount) * 100)
    Write-Host "[$currentIndex/$appsCount] ($progressPercent%) Installing $app..." -ForegroundColor Yellow
    
    try {
        # Run installation
        $installOutput = winget install --id $app --exact --silent --accept-package-agreements --accept-source-agreements 2>&1
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Host "[OK] Successfully installed $app." -ForegroundColor Green
            $script:installationsSucceeded += $app
        } elseif ($exitCode -eq -1978335215 -or $exitCode -eq 0x80070005) {
            # Common winget exit codes for already installed or access denied
            Write-Warning "[WARN] $app installation skipped (already installed or access issue, Exit code: $exitCode)."
            $script:installationsSucceeded += $app
        } else {
            Write-Error "[FAIL] Failed to install $app (Exit code: $exitCode)."
            Write-Error "Output: $installOutput"
            $script:installationsFailed += $app
        }
    } catch {
        Write-Error "[FAIL] Exception installing $app`: $_"
        $script:installationsFailed += $app
    }
}

# Post-Install Configuration for GCPW (Optional)
if (-not $SkipGCPWConfig) {
    if ([string]::IsNullOrWhiteSpace($Domain) -or $Domain -eq "yourdomain.com") {
        Write-Warning "GCPW configuration skipped: Domain not configured. Replace 'yourdomain.com' in the script or use -Domain parameter."
    } elseif ($Domain -notmatch '^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(\s*,\s*([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,})*$') {
        Write-Error "GCPW configuration skipped: '$Domain' is not a valid domain (or comma-separated domain list)."
    } else {
        Write-Host "Configuring GCPW for domain: $Domain" -ForegroundColor Cyan
        try {
            # Create registry path
            $gcpwPath = "HKLM:\SOFTWARE\Google\GCPW"
            if (-not (Test-Path $gcpwPath)) {
                $null = New-Item -Path "HKLM:\SOFTWARE\Google" -Name "GCPW" -Force -ErrorAction Stop
                Write-Host "Created registry path: $gcpwPath" -ForegroundColor Green
            } else {
                Write-Host "Registry path already exists: $gcpwPath" -ForegroundColor Green
            }
            
            # Set domain configuration
            $null = New-ItemProperty -Path $gcpwPath -Name "domains_allowed_to_login" -Value $Domain -PropertyType String -Force -ErrorAction Stop
            Write-Host "[OK] GCPW configured successfully for domain: $Domain" -ForegroundColor Green
        } catch {
            Write-Error "[FAIL] Failed to configure GCPW registry settings: $_"
        }
    }
}

# Summary report
Write-Host "`n" -ForegroundColor Gray
Write-Host "========== INSTALLATION SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Successful: $($script:installationsSucceeded.Count)" -ForegroundColor Green
if ($script:installationsSucceeded.Count -gt 0) {
    $script:installationsSucceeded | ForEach-Object { Write-Host "  [OK] $_" -ForegroundColor Green }
}

Write-Host "Failed: $($script:installationsFailed.Count)" -ForegroundColor $(if ($script:installationsFailed.Count -gt 0) { 'Red' } else { 'Green' })
if ($script:installationsFailed.Count -gt 0) {
    $script:installationsFailed | ForEach-Object { Write-Host "  [FAIL] $_" -ForegroundColor Red }
}
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "All application installations completed." -ForegroundColor Green
Write-Host "Script finished at $(Get-Date)" -ForegroundColor Cyan

# Close logging
Stop-Transcript

# Exit with appropriate code
if ($script:installationsFailed.Count -gt 0) {
    exit 1
} else {
    exit 0
}