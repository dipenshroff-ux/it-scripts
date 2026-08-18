#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Configures Make Me Admin policy-enforced registry settings: 30-minute admin
    rights timeout and automatic revocation on logoff/restart.

.DESCRIPTION
    Make Me Admin reads its enforced (non-overridable) configuration from:
        HKLM:\SOFTWARE\Policies\<CompanyName>\Make Me Admin
    This script sets:
        - "Admin Rights Timeout"          (REG_DWORD, minutes)
        - "Remove Admin Rights On Logout" (REG_DWORD, 1/0)
    Enabling "Remove Admin Rights On Logout" also covers restarts, since Windows
    logs the user off before a restart/shutdown completes.

.PARAMETER CompanyName
    The publisher name segment used in the registry path. The stock build from
    https://github.com/pseymour/MakeMeAdmin uses "Sinclair Community College".
    Change this if your build was compiled with a different company name.

.PARAMETER TimeoutMinutes
    Number of minutes a user retains administrator rights before expiration.

.PARAMETER RemoveOnLogout
    Whether admin rights are automatically revoked on logoff/restart.
#>

param(
    [string]$CompanyName = "Sinclair Community College",
    [int]$TimeoutMinutes = 30,
    [bool]$RemoveOnLogout = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$policyKeyPath = "HKLM:\SOFTWARE\Policies\$CompanyName\Make Me Admin"

Write-Host "Configuring Make Me Admin policy settings at:" -ForegroundColor Cyan
Write-Host "  $policyKeyPath" -ForegroundColor Gray

try {
    if (-not (Test-Path -Path $policyKeyPath)) {
        New-Item -Path $policyKeyPath -Force | Out-Null
        Write-Host "Created policy registry key." -ForegroundColor Green
    }

    New-ItemProperty -Path $policyKeyPath -Name "Admin Rights Timeout" `
        -PropertyType DWord -Value $TimeoutMinutes -Force | Out-Null
    Write-Host "[OK] Admin Rights Timeout = $TimeoutMinutes minutes" -ForegroundColor Green

    $removeOnLogoutValue = 0
    if ($RemoveOnLogout) {
        $removeOnLogoutValue = 1
    }
    New-ItemProperty -Path $policyKeyPath -Name "Remove Admin Rights On Logout" `
        -PropertyType DWord -Value $removeOnLogoutValue -Force | Out-Null
    Write-Host "[OK] Remove Admin Rights On Logout = $removeOnLogoutValue (covers logoff and restart)" -ForegroundColor Green

    Write-Host "Make Me Admin policy configuration complete." -ForegroundColor Cyan
} catch {
    Write-Error "Failed to configure Make Me Admin policy settings: $_"
    exit 1
}
