#Requires -Version 5.1
<#
.SYNOPSIS
  CLI for explorer-shell-fix

.EXAMPLE
  .\ExplorerShellFix.Cli.ps1 diagnose
  .\ExplorerShellFix.Cli.ps1 list-vendors
  .\ExplorerShellFix.Cli.ps1 disable -VendorId baidu-netdisk -RestartExplorer
  .\ExplorerShellFix.Cli.ps1 disable-high -RestartExplorer
  .\ExplorerShellFix.Cli.ps1 restore -BackupPath .\.backups\xxx.json -RestartExplorer
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('diagnose', 'list-vendors', 'disable', 'disable-high', 'restore', 'restart-explorer', 'export')]
  [string]$Command = 'diagnose',

  [string]$VendorId,
  [string]$BackupPath,
  [string]$OutPath,
  [ValidateSet('high', 'medium', 'low')]
  [string]$Risk = 'high',
  [switch]$RestartExplorer,
  [switch]$MachineWide
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ExplorerShellFix.Core.ps1')

$root = Get-EsfRoot
$backupDir = Join-Path $root '.backups'
$reportDir = Join-Path $root 'reports'

function New-EsfBackupPath([string]$Prefix) {
  if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
  }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  Join-Path $backupDir "$Prefix-$stamp.json"
}

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
    if (-not $BackupPath) { $BackupPath = New-EsfBackupPath -Prefix $VendorId }
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
  'disable-high' {
    # Alias of disable-by-risk with Risk=high (also accepts -Risk)
    if (-not $BackupPath) { $BackupPath = New-EsfBackupPath -Prefix "risk-$Risk" }
    $rec = Disable-EsfByRiskLevel -Risk $Risk -MachineWide:$MachineWide -BackupPath $BackupPath
    Write-Host "Disabled risk='$Risk' vendors: $(($rec.VendorIds) -join ', ')"
    Write-Host "CLSIDs: $(($rec.Clsids | Measure-Object).Count)"
    Write-Host "Backup: $BackupPath"
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