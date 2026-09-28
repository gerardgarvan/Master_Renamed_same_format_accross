---
phase: 24
slug: build-g-pcnr-harmonized
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-28
---

# Phase 24 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS 9.4 log assertions + static grep checks |
| **Config file** | `sas/00_config.sas` (gate flag `PCNR_APPROVED`, committed as 1 in Plan 01) |
| **Quick run command** | `findstr /b /c:"ERROR" "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs\24_pcnr_build.log"` (expect no output) -- logs live under `&logs_path` on P:, not in the repo |
| **Full suite command** | Run `sas/24_pcnr_build.sas` in clean SAS session; inspect log + QC CSVs |
| **Estimated runtime** | ~30–60 seconds (SAS session startup + 41,150 rows) |

---

## Sampling Rate

- **After every task commit:** static greps on `sas/24_pcnr_build.sas` (below); the log check applies only after a SAS run on the P: machine
- **After every SAS run:** `powershell -ExecutionPolicy Bypass -File scan_pipeline_logs.ps1` (Phase 22 scanner) must report PASS
- **After every plan wave:** Full program run; check QC CSV row counts
- **Before `/gsd:verify-work`:** Full suite must be green (0 ERROR lines, PCNR-11 assertions pass)
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 24-01-01 | 01 | 1 | PCNR-07 | static | `test -f docs/pcnr_name_map.csv && test ! -f docs/23_pcnr_name_map.csv && grep -c "%let PCNR_APPROVED = 1;" sas/00_config.sas` → 1 | n/a | ⬜ pending |
| 24-01-02 | 01 | 1 | PCNR-07 | static | `grep -n "%macro pcnr_gate_check" sas/24_pcnr_build.sas`; `grep -ci "proc import"` → 0 | ❌ W1 | ⬜ pending |
| 24-01-03 | 01 | 1 | PCNR-08 | static | `grep -n "not exists" sas/24_pcnr_build.sas`; `grep -c "length=7"` → 0 | ❌ W1 | ⬜ pending |
| 24-02-01 | 02 | 2 | PCNR-08 | SAS log | `work._recoded` row count = 41150; recode-step change count NOTE | ❌ W2 | ⬜ pending |
| 24-02-02 | 02 | 2 | PCNR-11 | SAS log | `NOTE: [24] comparison OK`; 0 unauthorized; both cross-checks pass | ❌ W2 | ⬜ pending |
| 24-03-01 | 03 | 3 | PCNR-09, PCNR-10 | SAS log | 163 columns = KEY source_names + KEEP final_names; type/length unchanged | ❌ W3 | ⬜ pending |
| 24-03-02 | 03 | 3 | PCNR-10, PCNR-11 | SAS log + file | `NOTE: [24] PCNR-11 PASS`; both qc/24_pcnr_recode_*.csv exist | ❌ W3 | ⬜ pending |
| 24-03-03 | 03 | 3 | PCNR-11 | manual | human-verified full run (Plan 03 Task 3) | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Verify `qc/23_sentinel_fingerprint.txt` exists and is readable
- [ ] Verify `qc/23_sentinel_candidates.csv` exists and is readable
- [ ] Verify `docs/sentinel_decisions.csv` exists and is readable
- [ ] Name map renamed (not copied): `docs/23_pcnr_name_map.csv` → `docs/pcnr_name_map.csv` (Plan 01 Task 1)
- [ ] `PCNR_APPROVED = 1` committed in `sas/00_config.sas` (a session-only value is reset by the config %include)
- [ ] Static check: `grep -ni "proc import" sas/24_pcnr_build.sas` → expect 0 (file not yet created; confirm after Wave 1)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `g.master_data_harmonized` confirmed unchanged after program 24 run | PCNR-11 | Requires SAS session with `g` libname mounted | SECTION 8 check 7 compares nobs/nvar/modate to the Phase 23 fingerprint; confirm its NOTE in the log |
| Zero remaining approved-sentinel values in `g.pcnr_harmonized` | PCNR-11 | Requires SAS session | Run program 24 Section 8 assertion; inspect log for "PCNR-11 PASS" |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
