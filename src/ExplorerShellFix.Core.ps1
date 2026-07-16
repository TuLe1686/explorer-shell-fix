#Requires -Version 5.1
<#
.SYNOPSIS
  Core library for explorer-shell-fix (diagnose / disable / restore shell extensions).

.NOTES
  Dot-source this file. Prefer pure functions + small side-effect wrappers.
  Disable mechanism matches NirSoft ShellExView:
    HKCU|HKLM\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EsfRoot {
  Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}

function Get-EsfVendorCatalog {
  param([string]$Path = (Join-Path (Get-EsfRoot) 'data\risk-vendors.json'))
  if (-not (Test-Path -LiteralPath $Path)) {
    return @{ version = 1; vendors = @() }
  }
  Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-EsfAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = [Security.Principal.WindowsPrincipal]::new($id)
  $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-EsfBlockedRoots {
  @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
  )
}

function Ensure-EsfBlockedKey {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -Path $Path -Force | Out-Null
  }
}

function Get-EsfClsidDll {
  param([Parameter(Mandatory)][string]$Clsid)
  $paths = @(
    "HKLM:\SOFTWARE\Classes\CLSID\$Clsid\InprocServer32"
    "HKLM:\SOFTWARE\Classes\CLSID\$Clsid\InProcServer32"
    "HKLM:\SOFTWARE\WOW6432Node\Classes\CLSID\$Clsid\InprocServer32"
  )
  foreach ($p in $paths) {
    if (Test-Path -LiteralPath $p) {
      $dll = (Get-ItemProperty -LiteralPath $p -ErrorAction SilentlyContinue).'(default)'
      if ($dll) { return [string]$dll }
    }
  }
  $null
}

function Get-EsfClsidName {
  param([Parameter(Mandatory)][string]$Clsid)
  $p = "HKLM:\SOFTWARE\Classes\CLSID\$Clsid"
  if (Test-Path -LiteralPath $p) {
    return [string](Get-ItemProperty -LiteralPath $p -ErrorAction SilentlyContinue).'(default)'
  }
  $null
}

function Test-EsfIsSystemShellDll {
  <#
    True for Windows built-in shell DLLs (namespace hosts, etc.).
    These must not be attributed to third-party vendors when a vendor path
    appears only in adjacent registry values (e.g. Baidu folder namespace → shdocvw.dll).
  #>
  param([string]$DllPath)
  if ([string]::IsNullOrWhiteSpace($DllPath)) { return $true }

  $expanded = [Environment]::ExpandEnvironmentVariables($DllPath).Trim('"')
  $leaf = [IO.Path]::GetFileName($expanded)

  $systemLeaves = @(
    'shell32.dll', 'shdocvw.dll', 'windows.storage.dll', 'explorerframe.dll',
    'twinui.dll', 'twinui.pcshell.dll', 'actxprxy.dll', 'ole32.dll',
    'combase.dll', 'propsys.dll', 'ntshrui.dll', 'cscui.dll', 'ehstorshell.dll',
    'thumbcache.dll', 'zipfldr.dll', 'msxml3.dll', 'msxml6.dll'
  )
  foreach ($s in $systemLeaves) {
    if ($leaf -and ($leaf -ieq $s)) { return $true }
  }

  # Any Inproc under Windows system locations is treated as system-owned for vendor matching.
  if ($expanded -match '(?i)([:\\]|%)(Windows|WINDIR)(\\System32|\\SysWOW64|\\WinSxS|\\SystemApps|\\ShellComponents|\\ShellExperiences)\\') {
    return $true
  }
  if ($expanded -match '(?i)^%SystemRoot%\\') { return $true }
  if ($expanded -match '(?i)^C:\\Windows\\') { return $true }

  $false
}

function Test-EsfIsActionableShellDll {
  param([string]$DllPath)
  if ([string]::IsNullOrWhiteSpace($DllPath)) { return $false }
  -not (Test-EsfIsSystemShellDll -DllPath $DllPath)
}

function Resolve-EsfVendor {
  param(
    [Parameter(Mandatory)]$Catalog,
    [string]$Text
  )
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  foreach ($v in @($Catalog.vendors)) {
    foreach ($pat in @($v.patterns)) {
      if ($Text -like "*$pat*" -or $Text -match [regex]::Escape($pat)) {
        return $v
      }
    }
  }
  $null
}

function Get-EsfIconOverlays {
  param($Catalog = (Get-EsfVendorCatalog))
  $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers'
  if (-not (Test-Path -LiteralPath $root)) { return @() }

  Get-ChildItem -LiteralPath $root | ForEach-Object {
    $name = $_.PSChildName
    $clsid = [string](Get-ItemProperty -LiteralPath $_.PSPath).'(default)'
    $dll = if ($clsid) { Get-EsfClsidDll -Clsid $clsid } else { $null }
    $blob = "$name|$clsid|$dll"
    $vendor = Resolve-EsfVendor -Catalog $Catalog -Text $blob
    $disabled = $name -like 'DISABLED_*'
    [pscustomobject]@{
      Kind       = 'IconOverlay'
      Name       = $name
      Clsid      = $clsid
      Dll        = $dll
      VendorId   = if ($vendor) { $vendor.id } else { $null }
      VendorName = if ($vendor) { $vendor.name } else { $null }
      Risk       = if ($vendor) { $vendor.risk } else { 'unknown' }
      Disabled   = $disabled
      Blocked    = Test-EsfClsidBlocked -Clsid $clsid
    }
  }
}

function Get-EsfKnownShellClsids {
  <#
    Discover shell-related CLSIDs by scanning overlay keys + reg.exe string search
    for catalog patterns. Avoids full CLSID tree walk (slow).
  #>
  param($Catalog = (Get-EsfVendorCatalog))

  $map = @{}

  foreach ($o in (Get-EsfIconOverlays -Catalog $Catalog)) {
    if ($o.Clsid) {
      $map[$o.Clsid] = [pscustomobject]@{
        Kind       = 'IconOverlay'
        Name       = $o.Name
        Clsid      = $o.Clsid
        Dll        = $o.Dll
        VendorId   = $o.VendorId
        VendorName = $o.VendorName
        Risk       = $o.Risk
      }
    }
  }

  $patterns = @($Catalog.vendors | ForEach-Object { $_.patterns } | Select-Object -Unique)
  foreach ($pat in $patterns) {
    if ([string]::IsNullOrWhiteSpace($pat)) { continue }
    if ($pat.Length -lt 4) { continue }
    $out = & reg.exe query 'HKLM\SOFTWARE\Classes\CLSID' /s /f $pat 2>$null
    if (-not $out) { continue }
    foreach ($line in $out) {
      if ($line -match 'CLSID\\(\{[0-9A-Fa-f\-]{36}\})') {
        $clsid = $Matches[1]
        if ($map.ContainsKey($clsid)) { continue }
        $dll = Get-EsfClsidDll -Clsid $clsid
        $name = Get-EsfClsidName -Clsid $clsid
        # Skip system hosts / empty Inproc (namespace folders that only store a vendor path nearby)
        if (-not (Test-EsfIsActionableShellDll -DllPath $dll)) { continue }
        # Vendor must match the DLL path or COM class name — not unrelated registry values
        $blob = "$name|$dll"
        $vendor = Resolve-EsfVendor -Catalog $Catalog -Text $blob
        if (-not $vendor) { continue }
        $map[$clsid] = [pscustomobject]@{
          Kind       = 'ShellClsid'
          Name       = $name
          Clsid      = $clsid
          Dll        = $dll
          VendorId   = $vendor.id
          VendorName = $vendor.name
          Risk       = $vendor.risk
        }
      }
    }
  }

  # Drop overlay-sourced entries that point at system DLLs without a real third-party Inproc
  $map.Values |
    Where-Object {
      $_.Kind -eq 'IconOverlay' -or (Test-EsfIsActionableShellDll -DllPath $_.Dll)
    } |
    Sort-Object Risk, VendorId, Name
}

function Test-EsfClsidBlocked {
  param([string]$Clsid)
  if ([string]::IsNullOrWhiteSpace($Clsid)) { return $false }
  foreach ($root in (Get-EsfBlockedRoots)) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $item = Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue
    if ($null -eq $item) { continue }
    if ($null -ne $item.PSObject.Properties[$Clsid]) { return $true }
  }
  $false
}

function Get-EsfExplorerSnapshot {
  Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
    $gp = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
    $isFactory = ($_.CommandLine -match 'factory,\{75dff2b7-6936-4c06-a8bb-676a7b00b24b\}')
    $third = @()
    if ($gp) {
      try {
        $third = @(
          $gp.Modules |
            Where-Object {
              $_.FileName -and
              $_.FileName -notmatch '\\Windows\\(System32|SysWOW64|WinSxS|ShellComponents|ShellExperiences|SystemApps)\\'
            } |
            Select-Object -ExpandProperty ModuleName -Unique
        )
      } catch {
        $third = @('(modules unavailable)')
      }
    }
    [pscustomobject]@{
      ProcessId   = $_.ProcessId
      Role        = if ($isFactory) { 'factory-host' } else { 'main-shell' }
      Handles     = if ($gp) { $gp.HandleCount } else { $null }
      Threads     = if ($gp) { $gp.Threads.Count } else { $null }
      WorkingSetMB = if ($gp) { [math]::Round($gp.WorkingSet64 / 1MB, 1) } else { $null }
      Responding  = if ($gp) { $gp.Responding } else { $null }
      StartTime   = $_.CreationDate
      ThirdPartyModules = ($third -join ', ')
    }
  }
}

function Get-EsfDiagnosis {
  $catalog = Get-EsfVendorCatalog
  $explorers = @(Get-EsfExplorerSnapshot)
  $overlays = @(Get-EsfIconOverlays -Catalog $catalog)
  $clsids = @(Get-EsfKnownShellClsids -Catalog $catalog)

  $main = @($explorers | Where-Object Role -eq 'main-shell')
  $factory = @($explorers | Where-Object Role -eq 'factory-host')
  $riskyOverlays = @($overlays | Where-Object { $_.Risk -in @('high', 'medium') -and -not $_.Disabled })
  $blockedCount = @($clsids | Where-Object { Test-EsfClsidBlocked -Clsid $_.Clsid }).Count

  $hints = [System.Collections.Generic.List[string]]::new()
  if ($explorers.Count -ge 4) {
    $hints.Add("Multiple explorer.exe processes ($($explorers.Count)). Factory hosts may be stuck.")
  }
  if ($main | Where-Object { $_.Handles -ge 4000 }) {
    $hints.Add('Main explorer handle count is very high (>= 4000). Often shell-extension leak/hang.')
  }
  if ($riskyOverlays.Count -gt 0) {
    $hints.Add("Active risky icon overlays: $($riskyOverlays.Count).")
  }
  if ($hints.Count -eq 0) {
    $hints.Add('No strong red flags from quick heuristics. Still try disabling high-risk vendors if folders white-screen.')
  }

  [pscustomobject]@{
    TimeUtc            = (Get-Date).ToUniversalTime().ToString('o')
    IsAdmin            = (Test-EsfAdmin)
    ExplorerCount      = $explorers.Count
    MainShellCount     = $main.Count
    FactoryHostCount   = $factory.Count
    RiskyOverlayCount  = $riskyOverlays.Count
    BlockedClsidCount  = $blockedCount
    Hints              = @($hints)
    Explorers          = $explorers
    IconOverlays       = $overlays
    ShellClsids        = $clsids
  }
}

function Disable-EsfClsid {
  param(
    [Parameter(Mandatory)][string]$Clsid,
    [switch]$MachineWide
  )
  $roots = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked')
  if ($MachineWide -or (Test-EsfAdmin)) {
    $roots += 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
  }
  $done = @()
  foreach ($r in $roots) {
    try {
      Ensure-EsfBlockedKey -Path $r
      New-ItemProperty -Path $r -Name $Clsid -Value '' -PropertyType String -Force | Out-Null
      $done += $r
    } catch {
      # ignore HKLM without admin
    }
  }
  $done
}

function Enable-EsfClsid {
  param(
    [Parameter(Mandatory)][string]$Clsid
  )
  foreach ($r in (Get-EsfBlockedRoots)) {
    if (-not (Test-Path -LiteralPath $r)) { continue }
    Remove-ItemProperty -Path $r -Name $Clsid -ErrorAction SilentlyContinue
  }
}

function Disable-EsfIconOverlayKey {
  param([Parameter(Mandatory)][string]$Name)
  $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers'
  $path = Join-Path $root $Name
  if (-not (Test-Path -LiteralPath $path)) { return $false }
  if ($Name -like 'DISABLED_*') { return $true }
  $newName = 'DISABLED_' + ($Name.Trim())
  Rename-Item -LiteralPath $path -NewName $newName
  $true
}

function Enable-EsfIconOverlayKey {
  param([Parameter(Mandatory)][string]$DisabledName)
  $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers'
  $path = Join-Path $root $DisabledName
  if (-not (Test-Path -LiteralPath $path)) { return $false }
  if ($DisabledName -notlike 'DISABLED_*') { return $false }
  $orig = $DisabledName -replace '^DISABLED_', ''
  # Baidu-style priority padding
  if ($orig -match '^\.WorkspaceExt') {
    $orig = (' ' * 6) + $orig
  }
  Rename-Item -LiteralPath $path -NewName $orig
  $true
}

function Disable-EsfByVendor {
  param(
    [Parameter(Mandatory)][string]$VendorId,
    [switch]$MachineWide,
    [string]$BackupPath
  )
  $catalog = Get-EsfVendorCatalog
  $vendor = @($catalog.vendors | Where-Object id -eq $VendorId | Select-Object -First 1)
  if (-not $vendor) { throw "Unknown vendor id: $VendorId" }

  $clsids = @(Get-EsfKnownShellClsids -Catalog $catalog | Where-Object VendorId -eq $VendorId)
  $overlays = @(Get-EsfIconOverlays -Catalog $catalog | Where-Object {
      $_.VendorId -eq $VendorId -or ($_.Dll -and (Resolve-EsfVendor -Catalog $catalog -Text $_.Dll).id -eq $VendorId)
    })

  $record = [pscustomobject]@{
    TimeUtc   = (Get-Date).ToUniversalTime().ToString('o')
    VendorId  = $VendorId
    Action    = 'disable'
    Clsids    = @($clsids.Clsid | Select-Object -Unique)
    Overlays  = @($overlays | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Clsid = $_.Clsid; WasDisabled = $_.Disabled }
      })
  }

  foreach ($id in $record.Clsids) {
    [void](Disable-EsfClsid -Clsid $id -MachineWide:$MachineWide)
  }

  foreach ($ov in $overlays) {
    if (-not $ov.Disabled -and $ov.Name) {
      try { [void](Disable-EsfIconOverlayKey -Name $ov.Name) } catch { }
    }
  }

  if ($BackupPath) {
    $dir = Split-Path -Parent $BackupPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $BackupPath -Encoding UTF8
  }

  $record
}

function Disable-EsfByRiskLevel {
  <#
    Disable all catalog vendors at a given risk level (default: high).
    Writes one combined backup JSON for restore.
  #>
  param(
    [ValidateSet('high', 'medium', 'low')]
    [string]$Risk = 'high',
    [switch]$MachineWide,
    [string]$BackupPath
  )
  $catalog = Get-EsfVendorCatalog
  $targets = @($catalog.vendors | Where-Object { $_.risk -eq $Risk })
  if ($targets.Count -eq 0) {
    throw "No vendors with risk='$Risk' in catalog."
  }

  $allClsids = [System.Collections.Generic.List[string]]::new()
  $allOverlays = [System.Collections.Generic.List[object]]::new()
  $vendorIds = [System.Collections.Generic.List[string]]::new()
  $perVendor = [System.Collections.Generic.List[object]]::new()

  foreach ($v in $targets) {
    $rec = Disable-EsfByVendor -VendorId $v.id -MachineWide:$MachineWide
    $vendorIds.Add([string]$v.id)
    $perVendor.Add([pscustomobject]@{
        VendorId = $v.id
        ClsidCount = @($rec.Clsids).Count
        OverlayCount = @($rec.Overlays).Count
      })
    foreach ($id in @($rec.Clsids)) {
      if ($id -and -not $allClsids.Contains($id)) { $allClsids.Add($id) }
    }
    foreach ($ov in @($rec.Overlays)) {
      $allOverlays.Add($ov)
    }
  }

  $combined = [pscustomobject]@{
    TimeUtc    = (Get-Date).ToUniversalTime().ToString('o')
    Action     = 'disable-by-risk'
    Risk       = $Risk
    VendorId   = $null
    VendorIds  = @($vendorIds)
    Vendors    = @($perVendor)
    Clsids     = @($allClsids)
    Overlays   = @($allOverlays)
  }

  if ($BackupPath) {
    $dir = Split-Path -Parent $BackupPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $combined | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $BackupPath -Encoding UTF8
  }

  $combined
}

function Restore-EsfFromBackup {
  param([Parameter(Mandatory)][string]$BackupPath)
  if (-not (Test-Path -LiteralPath $BackupPath)) {
    throw "Backup not found: $BackupPath"
  }
  $record = Get-Content -LiteralPath $BackupPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($id in @($record.Clsids)) {
    if ($id) { Enable-EsfClsid -Clsid $id }
  }
  $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers'
  if ((Test-Path -LiteralPath $root) -and $record.Overlays) {
    Get-ChildItem -LiteralPath $root | Where-Object { $_.PSChildName -like 'DISABLED_*' } | ForEach-Object {
      # Only restore overlays listed in this backup (never blanket-enable all DISABLED_*)
      $n = $_.PSChildName
      $match = @($record.Overlays | Where-Object {
          $orig = [string]$_.Name
          if ([string]::IsNullOrWhiteSpace($orig)) { return $false }
          $n -eq ('DISABLED_' + $orig.Trim()) -or
          $n -eq ('DISABLED_' + $orig) -or
          $n.EndsWith($orig.Trim())
        })
      if ($match.Count -gt 0) {
        try { [void](Enable-EsfIconOverlayKey -DisabledName $n) } catch { }
      }
    }
  }
  [pscustomobject]@{
    RestoredFrom = $BackupPath
    VendorId     = $record.VendorId
    VendorIds    = $record.VendorIds
    Risk         = $record.Risk
  }
}

function Restart-EsfExplorer {
  Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 800
  if (Get-Process -Name explorer -ErrorAction SilentlyContinue) {
    & taskkill.exe /F /IM explorer.exe 2>$null | Out-Null
    Start-Sleep -Milliseconds 800
  }
  Start-Process -FilePath "$env:WINDIR\explorer.exe"
  Start-Sleep -Seconds 2
  @(Get-EsfExplorerSnapshot)
}

function Export-EsfReport {
  param(
    [Parameter(Mandatory)]$Diagnosis,
    [Parameter(Mandatory)][string]$Path
  )
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  $Diagnosis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
  $Path
}

function Format-EsfDiagnosisText {
  param([Parameter(Mandatory)]$Diagnosis)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.AppendLine('=== explorer-shell-fix diagnosis ===')
  [void]$sb.AppendLine("Time (UTC): $($Diagnosis.TimeUtc)")
  [void]$sb.AppendLine("Admin: $($Diagnosis.IsAdmin)")
  [void]$sb.AppendLine("explorer.exe count: $($Diagnosis.ExplorerCount) (main=$($Diagnosis.MainShellCount), factory=$($Diagnosis.FactoryHostCount))")
  [void]$sb.AppendLine("Risky overlays: $($Diagnosis.RiskyOverlayCount)")
  [void]$sb.AppendLine("Blocked CLSIDs (known set): $($Diagnosis.BlockedClsidCount)")
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Hints:')
  foreach ($h in @($Diagnosis.Hints)) { [void]$sb.AppendLine("  - $h") }
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Explorer processes:')
  foreach ($e in @($Diagnosis.Explorers)) {
    [void]$sb.AppendLine("  PID $($e.ProcessId) $($e.Role) handles=$($e.Handles) threads=$($e.Threads) wsMB=$($e.WorkingSetMB)")
  }
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Icon overlays:')
  foreach ($o in @($Diagnosis.IconOverlays)) {
    [void]$sb.AppendLine("  [$($o.Risk)] $($o.Name) | $($o.VendorName) | blocked=$($o.Blocked) disabledKey=$($o.Disabled)")
    if ($o.Dll) { [void]$sb.AppendLine("      $($o.Dll)") }
  }
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Matched shell CLSIDs:')
  foreach ($c in @($Diagnosis.ShellClsids)) {
    $b = Test-EsfClsidBlocked -Clsid $c.Clsid
    [void]$sb.AppendLine("  [$($c.Risk)] $($c.VendorId) $($c.Clsid) blocked=$b")
    if ($c.Dll) { [void]$sb.AppendLine("      $($c.Dll)") }
  }
  $sb.ToString()
}