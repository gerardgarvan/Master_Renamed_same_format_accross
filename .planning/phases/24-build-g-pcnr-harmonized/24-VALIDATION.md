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
| **Config file** | `sas/00_config.sas` (gate flag `PCNR_APPROVED`) |
| **Quick run command** | `grep -c "ERROR" sas/log/24_pcnr_build.log` (expect 0) |
| **Full suite command** | Run `sas/24_pcnr_build.sas` in clean SAS session; inspect log + QC CSVs |
| **Estimated runtime** | ~30–60 seconds (SAS session startup + 41,150 rows) |

---

## Sampling Rate

- **After every task commit:** Run `grep -c "ERROR\|WARNING" sas/log/24_pcnr_build.log`
- **After every plan wave:** Full program run; check QC CSV row counts
- **Before `/gsd:verify-work`:** Full suite must be green (0 ERROR lines, PCNR-11 assertions pass)
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 24-01-01 | 01 | 0 | PCNR-07 | static grep | `grep -ni "proc import" sas/24_pcnr_build.sas` → 0 | ❌ W0 | ⬜ pending |
| 24-01-02 | 01 | 1 | PCNR-07 | SAS log | gate macro run → no abort, NOTE in log | ❌ W0 | ⬜ pending |
| 24-02-01 | 01 | 1 | PCNR-08 | file check | `test -f qc/24_recode_rules_generated.sas` | ❌ W0 | ⬜ pending |
| 24-03-01 | 01 | 1 | PCNR-08 | SAS log | `work._recoded` row count = 41150 | ❌ W0 | ⬜ pending |
| 24-04-01 | 01 | 1 | PCNR-09 | SAS log | comparison step 0 unauthorized changes | ❌ W0 | ⬜ pending |
| 24-05-01 | 01 | 2 | PCNR-10 | SAS log | `g.pcnr_harmonized` column list = KEY + KEEP final_names | ❌ W0 | ⬜ pending |
| 24-06-01 | 01 | 2 | PCNR-11 | SAS log | PCNR-11 assertion block passes (0 errors) | ❌ W0 | ⬜ pending |
| 24-07-01 | 01 | 2 | PCNR-11 | file check | `test -f qc/24_pcnr_recode_counts.csv && test -f qc/24_pcnr_recode_totals.csv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Verify `qc/23_sentinel_fingerprint.txt` exists and is readable
- [ ] Verify `qc/23_sentinel_candidates.csv` exists and is readable
- [ ] Verify `docs/sentinel_decisions.csv` exists and is readable
- [ ] Resolve name map filename: `docs/23_pcnr_name_map.csv` → `docs/pcnr_name_map.csv` (or confirm canonical name)
- [ ] Confirm `PCNR_APPROVED = 1` can be set in `sas/00_config.sas`
- [ ] Static check: `grep -ni "proc import" sas/24_pcnr_build.sas` → expect 0 (file not yet created; confirm after Wave 1)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `g.master_data_harmonized` confirmed unchanged after program 24 run | PCNR-11 | Requires SAS session with `g` libname mounted | Run PROC COMPARE or re-run fingerprint check; compare nobs/nvars/modate |
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
