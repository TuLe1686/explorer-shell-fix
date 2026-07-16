#Requires -Version 5.1
# Simple WinForms GUI for explorer-shell-fix
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot 'ExplorerShellFix.Core.ps1')

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'explorer-shell-fix'
$form.Size = New-Object System.Drawing.Size(980, 660)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(820, 540)

$lblVendor = New-Object System.Windows.Forms.Label
$lblVendor.Text = 'Vendor / 厂商'
$lblVendor.Location = New-Object System.Drawing.Point(12, 14)
$lblVendor.AutoSize = $true

$cmbVendor = New-Object System.Windows.Forms.ComboBox
$cmbVendor.Location = New-Object System.Drawing.Point(100, 10)
$cmbVendor.Size = New-Object System.Drawing.Size(300, 24)
$cmbVendor.DropDownStyle = 'DropDownList'

$btnDiagnose = New-Object System.Windows.Forms.Button
$btnDiagnose.Text = 'Diagnose / 诊断'
$btnDiagnose.Location = New-Object System.Drawing.Point(420, 8)
$btnDiagnose.Size = New-Object System.Drawing.Size(110, 28)

$btnDisable = New-Object System.Windows.Forms.Button
$btnDisable.Text = 'Disable vendor'
$btnDisable.Location = New-Object System.Drawing.Point(540, 8)
$btnDisable.Size = New-Object System.Drawing.Size(110, 28)

$btnDisableHigh = New-Object System.Windows.Forms.Button
$btnDisableHigh.Text = 'Disable ALL HIGH'
$btnDisableHigh.Location = New-Object System.Drawing.Point(660, 8)
$btnDisableHigh.Size = New-Object System.Drawing.Size(140, 28)
$btnDisableHigh.BackColor = [System.Drawing.Color]::FromArgb(255, 240, 200)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = 'Restore last'
$btnRestore.Location = New-Object System.Drawing.Point(810, 8)
$btnRestore.Size = New-Object System.Drawing.Size(120, 28)

$btnRestart = New-Object System.Windows.Forms.Button
$btnRestart.Text = 'Restart Explorer only'
$btnRestart.Location = New-Object System.Drawing.Point(420, 42)
$btnRestart.Size = New-Object System.Drawing.Size(150, 28)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = 'Export JSON'
$btnExport.Location = New-Object System.Drawing.Point(580, 42)
$btnExport.Size = New-Object System.Drawing.Size(100, 28)

$chkMachine = New-Object System.Windows.Forms.CheckBox
$chkMachine.Text = 'Also HKLM (admin) / 写入本机策略'
$chkMachine.Location = New-Object System.Drawing.Point(100, 44)
$chkMachine.AutoSize = $true

$txt = New-Object System.Windows.Forms.TextBox
$txt.Multiline = $true
$txt.ScrollBars = 'Both'
$txt.ReadOnly = $true
$txt.Font = New-Object System.Drawing.Font('Consolas', 9)
$txt.Location = New-Object System.Drawing.Point(12, 80)
$txt.Anchor = 'Top,Bottom,Left,Right'
$txt.Size = New-Object System.Drawing.Size(928, 520)
$txt.WordWrap = $false

$form.Controls.AddRange(@(
    $lblVendor, $cmbVendor, $btnDiagnose, $btnDisable, $btnDisableHigh, $btnRestore,
    $btnRestart, $btnExport, $chkMachine, $txt
  ))

$script:LastBackup = $null
$script:Root = Get-EsfRoot

function Write-Ui([string]$s) {
  $txt.Text = $s
  $txt.SelectionStart = 0
  $txt.ScrollToCaret()
}

function Load-Vendors {
  $cmbVendor.Items.Clear()
  $cat = Get-EsfVendorCatalog
  foreach ($v in @($cat.vendors)) {
    [void]$cmbVendor.Items.Add("$($v.id)  |  $($v.name)  [$($v.risk)]")
  }
  if ($cmbVendor.Items.Count -gt 0) { $cmbVendor.SelectedIndex = 0 }
}

function Get-SelectedVendorId {
  if ($null -eq $cmbVendor.SelectedItem) { return $null }
  ($cmbVendor.SelectedItem.ToString() -split '\s+\|\s+')[0].Trim()
}

function Ensure-BackupDir {
  $dir = Join-Path $script:Root '.backups'
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $dir
}

$btnDiagnose.Add_Click({
    try {
      $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
      $d = Get-EsfDiagnosis
      Write-Ui (Format-EsfDiagnosisText -Diagnosis $d)
    } catch {
      [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Diagnose failed') | Out-Null
    } finally {
      $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
  })

$btnDisable.Add_Click({
    $vid = Get-SelectedVendorId
    if (-not $vid) { return }
    $r = [System.Windows.Forms.MessageBox]::Show(
      "Disable shell extensions for '$vid' and restart Explorer?`n将禁用该厂商的 Shell 扩展并重启资源管理器。",
      'Confirm',
      'YesNo',
      'Warning'
    )
    if ($r -ne 'Yes') { return }
    try {
      $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
      $dir = Ensure-BackupDir
      $bp = Join-Path $dir ("{0}-{1:yyyyMMdd-HHmmss}.json" -f $vid, (Get-Date))
      $rec = Disable-EsfByVendor -VendorId $vid -MachineWide:$chkMachine.Checked -BackupPath $bp
      $script:LastBackup = $bp
      Restart-EsfExplorer | Out-Null
      $d = Get-EsfDiagnosis
      Write-Ui ("Disabled $vid`r`nBackup: $bp`r`nCLSIDs: $(($rec.Clsids | Measure-Object).Count)`r`n`r`n" + (Format-EsfDiagnosisText -Diagnosis $d))
      [System.Windows.Forms.MessageBox]::Show("Done. Backup:`n$bp", 'OK') | Out-Null
    } catch {
      [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Disable failed') | Out-Null
    } finally {
      $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
  })

$btnDisableHigh.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show(
      "Disable ALL catalog vendors with risk=high (Baidu/WPS/360/...) and restart Explorer?`n一键禁用目录中所有 high 风险厂商扩展并重启资源管理器。",
      'Confirm disable-high',
      'YesNo',
      'Warning'
    )
    if ($r -ne 'Yes') { return }
    try {
      $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
      $dir = Ensure-BackupDir
      $bp = Join-Path $dir ("risk-high-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
      $rec = Disable-EsfByRiskLevel -Risk high -MachineWide:$chkMachine.Checked -BackupPath $bp
      $script:LastBackup = $bp
      Restart-EsfExplorer | Out-Null
      $d = Get-EsfDiagnosis
      $vendors = ($rec.VendorIds -join ', ')
      Write-Ui ("Disabled HIGH: $vendors`r`nBackup: $bp`r`nCLSIDs: $(($rec.Clsids | Measure-Object).Count)`r`n`r`n" + (Format-EsfDiagnosisText -Diagnosis $d))
      [System.Windows.Forms.MessageBox]::Show("Done.`nVendors: $vendors`nBackup:`n$bp", 'OK') | Out-Null
    } catch {
      [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Disable-high failed') | Out-Null
    } finally {
      $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
  })

$btnRestore.Add_Click({
    $bp = $script:LastBackup
    if (-not $bp -or -not (Test-Path -LiteralPath $bp)) {
      $ofd = New-Object System.Windows.Forms.OpenFileDialog
      $ofd.Filter = 'JSON backup|*.json'
      $ofd.InitialDirectory = (Join-Path $script:Root '.backups')
      if ($ofd.ShowDialog() -ne 'OK') { return }
      $bp = $ofd.FileName
    }
    try {
      $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
      Restore-EsfFromBackup -BackupPath $bp | Out-Null
      Restart-EsfExplorer | Out-Null
      Write-Ui ("Restored from $bp`r`n`r`n" + (Format-EsfDiagnosisText -Diagnosis (Get-EsfDiagnosis)))
    } catch {
      [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Restore failed') | Out-Null
    } finally {
      $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
  })

$btnRestart.Add_Click({
    try {
      Restart-EsfExplorer | Out-Null
      Write-Ui (Format-EsfDiagnosisText -Diagnosis (Get-EsfDiagnosis))
    } catch {
      [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Restart failed') | Out-Null
    }
  })

$btnExport.Add_Click({
    try {
      $dir = Join-Path $script:Root 'reports'
      if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      $path = Join-Path $dir ("diagnosis-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
      Export-EsfReport -Diagnosis (Get-EsfDiagnosis) -Path $path | Out-Null
      [System.Windows.Forms.MessageBox]::Show($path, 'Exported') | Out-Null
    } catch {
      [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Export failed') | Out-Null
    }
  })

Load-Vendors
try {
  Write-Ui (Format-EsfDiagnosisText -Diagnosis (Get-EsfDiagnosis))
} catch {
  Write-Ui $_.Exception.Message
}

[void]$form.ShowDialog()