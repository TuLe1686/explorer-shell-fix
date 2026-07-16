# Contributing

## Scope

- Fix Explorer white-screen / hang issues caused by shell extensions  
- Keep zero runtime dependencies (PowerShell + WinForms only)

## Vendor rules

Edit `data/risk-vendors.json`:

```json
{
  "id": "my-vendor",
  "name": "Display Name",
  "risk": "high|medium|low",
  "patterns": ["DllName", "FolderPathFragment"],
  "notes": "Why it matters"
}
```

Patterns are matched against overlay names, CLSID display names, and InprocServer32 DLL paths.

## Code layout

| Path | Role |
|------|------|
| `src/ExplorerShellFix.Core.ps1` | Diagnose / disable / restore / restart |
| `src/ExplorerShellFix.Cli.ps1` | CLI |
| `src/ExplorerShellFix.Gui.ps1` | WinForms UI |
| `Start-ExplorerShellFix.ps1` | Entry |

## PR checklist

- [ ] Does not uninstall software  
- [ ] Disable path is reversible (backup JSON)  
- [ ] README updated if UX changes  
- [ ] No secrets / machine-specific paths committed  

## Manual test

1. `.\Start-ExplorerShellFix.ps1 -Cli diagnose`  
2. Disable a high-risk vendor on a throwaway VM if possible  
3. Confirm folders open; then restore from `.backups\`