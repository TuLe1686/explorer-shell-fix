# Changelog

## [0.1.0] - 2026-07-17

### Added

- Diagnose Explorer process health (main vs factory hosts, handles, third-party modules)
- Vendor catalog (`data/risk-vendors.json`) with risk levels
- Reversible disable via `Shell Extensions\Blocked` + icon-overlay key rename
- CLI: `diagnose`, `list-vendors`, `disable`, `disable-high`, `restore`, `restart-explorer`, `export`
- WinForms GUI with **Disable ALL HIGH**
- Combined backup JSON for multi-vendor disable-high
- GitHub issue templates (bug / feature / vendor pattern)

### Fixed

- Filter false-positive CLSID matches that only share a vendor *path* in registry but load **system** Inproc servers (`shdocvw.dll`, `shell32.dll`, `%SystemRoot%\...`)
- Restore only restores overlays listed in the backup (no blanket re-enable of all `DISABLED_*` keys)

### Notes

- Does **not** uninstall software
- Restart Explorer after disable to unload already-injected DLLs
- App updates may re-register shell extensions