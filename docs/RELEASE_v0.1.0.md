## explorer-shell-fix v0.1.0

First public release: diagnose and **reversibly disable** third-party Windows Explorer shell extensions that cause **blank folder windows** or “double-click does nothing”.

### Highlights

- **Diagnose** — explorer.exe main/factory hosts, handle counts, icon overlays, matched vendor CLSIDs  
- **Disable one vendor** or **Disable ALL HIGH** (Baidu / WPS / 360 / … from catalog)  
- **Restore** from JSON backup under `.backups\`  
- **No uninstall** — same `Shell Extensions\Blocked` idea as ShellExView  
- **False-positive filter** — skip system Inproc DLLs (`shdocvw.dll`, `shell32.dll`, …)

### Quick start

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\Start-ExplorerShellFix.ps1
# or CLI:
.\Start-ExplorerShellFix.ps1 -Cli diagnose
.\Start-ExplorerShellFix.ps1 -Cli disable-high -RestartExplorer
```

### Requirements

Windows 10/11, PowerShell 5.1+

### Caution

Registry changes can remove overlay icons / context-menu items for those apps. Backups are written automatically. MIT license, no warranty.

Full notes: [CHANGELOG.md](https://github.com/TuLe1686/explorer-shell-fix/blob/main/CHANGELOG.md)