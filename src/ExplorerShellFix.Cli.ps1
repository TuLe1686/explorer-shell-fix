#Requires -Version 5.1
<#
.SYNOPSIS
  CLI for explorer-shell-fix

.EXAMPLE
  .\ExplorerShellFix.Cli.ps1 diagnose
  .\ExplorerShellFix.Cli.ps1 list-vendors
  .\ExplorerShellFix.Cli.ps1 disable -VendorId baidu-netdisk -RestartExplorer
  .\ExplorerShellFix.Cli.ps1 restore -BackupPath .\.backups\baidu-netdisk.json -RestartExplorer
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('diagnose', 'list-vendors', 'disable', 'restore', 'restart-explorer', 'export')]
  [string]$Command = 'diagnose',

  [string]$VendorId,
  [string]$BackupPath,
  [string]$OutPath,
  [switch]$RestartExplorer,
  [switch]$MachineWide
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ExplorerShellFix.Core.ps1')

$root = Get-EsfRoot
$backupDir = Join-Path $root '.backups'
$reportDir = Join-Path $root 'reports'

switch ($Command) {
  'diagnose' {
    $d = Get-EsfDiagnosis
    Write-Output (Format-EsfDiagnosisText -Diagnosis $d)
  }
  'list-vendors' {
    $c = Get-EsfVendorCatalog
    $c.vendors | Select-Object id, name, risk, notes | Format-Table -AutoSize -Wrap
  }
  'disable' {
    if (-not $VendorId) { throw 'disable requires -VendorId (see list-vendors)' }
    if (-not $BackupPath) {
      if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
      }
      $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
      $BackupPath = Join-Path $backupDir "$VendorId-$stamp.json"
    }
    $rec = Disable-EsfByVendor -VendorId $VendorId -MachineWide:$MachineWide -BackupPath $BackupPath
    Write-Host "Disabled vendor '$VendorId'. Backup: $BackupPath"
    Write-Host "CLSIDs: $(($rec.Clsids | Measure-Object).Count)"
    if ($RestartExplorer) {
      Write-Host 'Restarting explorer...'
      Restart-EsfExplorer | Out-Null
      Write-Host 'Explorer restarted.'
    } else {
      Write-Host 'Restart explorer to unload already-loaded DLLs (restart-explorer).'
    }
  }
  'restore' {
    if (-not $BackupPath) { throw 'restore requires -BackupPath' }
    Restore-EsfFromBackup -BackupPath $BackupPath | Format-List
    if ($RestartExplorer) {
      Restart-EsfExplorer | Out-Null
      Write-Host 'Explorer restarted.'
    }
  }
  'restart-explorer' {
    Restart-EsfExplorer | Format-Table -AutoSize
  }
  'export' {
    $d = Get-EsfDiagnosis
    if (-not $OutPath) {
      if (-not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
      }
      $OutPath = Join-Path $reportDir ("diagnosis-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
    }
    Export-EsfReport -Diagnosis $d -Path $OutPath | ForEach-Object { Write-Host "Wrote $_" }
  }
}