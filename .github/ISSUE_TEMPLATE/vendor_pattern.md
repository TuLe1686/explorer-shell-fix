---
name: Vendor pattern
about: Add or fix a risk-vendor detection pattern (DLL path / product name)
title: "[vendor] "
labels: vendor-rules
assignees: ""
---

## Product

- Name:
- Vendor / publisher:
- Suggested risk: high | medium | low

## Evidence

- DLL path(s) under Explorer or CLSID InprocServer32:
- Icon overlay key name(s) if any:
- Why it breaks Explorer (hang / white screen / high handles):

## Suggested `data/risk-vendors.json` patterns

```json
{
  "id": "example-id",
  "name": "Example",
  "risk": "high",
  "patterns": ["ExampleDll", "ExamplePathFragment"],
  "notes": "..."
}
```

## False-positive risk

<!-- Could this match Windows system DLLs or unrelated software? -->