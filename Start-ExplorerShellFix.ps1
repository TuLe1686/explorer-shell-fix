#Requires -Version 5.1
<#
.SYNOPSIS
  Launch explorer-shell-fix GUI, or forward to CLI.

.EXAMPLE
  .\Start-ExplorerShellFix.ps1
  .\Start-ExplorerShellFix.ps1 -Cli diagnose
  .\Start-ExplorerShellFix.ps1 -Cli disable -VendorId baidu-netdisk -RestartExplorer
#>
[CmdletBinding()]
param(
  [switch]$Cli
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$cliPath = Join-Path $here 'src\ExplorerShellFix.Cli.ps1'
$guiPath = Join-Path $here 'src\ExplorerShellFix.Gui.ps1'

if ($Cli) {
  # Forward unbound args after -Cli to the CLI script (PS 5.1+)
  $forward = @()
  if ($MyInvocation.UnboundArguments) {
    $forward = @($MyInvocation.UnboundArguments)
  }
  & $cliPath @forward
  exit $LASTEXITCODE
}

# GUI in a child process so the console returns cleanly when launched from terminal
$ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps)) {
  $ps = 'powershell.exe'
}
Start-Process -FilePath $ps -ArgumentList @(
  '-NoProfile'
  '-ExecutionPolicy', 'Bypass'
  '-File', $guiPath
)