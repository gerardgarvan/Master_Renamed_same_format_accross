---
phase: 28
slug: r7-r8-r9-linkage-investigation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-07
---

# Phase 28 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS log inspection + CSV file existence checks (no test framework) |
| **Config file** | none |
| **Quick run command** | `ls qc/28_linkage_investigation.csv` |
| **Full suite command** | Manual: review log for ERROR/WARNING lines + inspect CSV columns |
| **Estimated runtime** | ~5 minutes (manual inspection) |

---

## Sampling Rate

- **After every task commit:** Confirm no ERROR lines in SAS log snippet
- **After every plan wave:** Run full SAS program and inspect output CSV
- **Before `/gsd:verify-work`:** CSV exists with correct 9 columns and ≥1 row; PCM-D-28 written in docs/DECISIONS.md
- **Max feedback latency:** 10 minutes

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 28-01-T1 | 01 | 1 | LINK-01 provenance | manual | `git log --all --oneline -S "14.5" -- .planning/ docs/ \| head` | ✅ | ⬜ pending |
| 28-01-T2 | 01 | 1 | LINK-02 SAS program | file+grep | `test -f sas/28_linkage_investigation.sas && grep -c "md7_vs_md3_2022" sas/28_linkage_investigation.sas` | ❌ W0 | ⬜ pending |
| 28-02-T1 | 02 | 2 | LINK-02 CSV | checkpoint | manual run on P: drive; `ls qc/28_linkage_investigation.csv 2>/dev/null \|\| echo RUNTIME` | ❌ runtime | ⬜ pending |
| 28-02-T2 | 02 | 2 | LINK-03 PCM-D-28 | grep | `grep -c "PCM-D-28" docs/DECISIONS.md` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- `sas/28_linkage_investigation.sas` — standalone investigation program (new file)
- `qc/28_linkage_investigation.csv` — output artifact (produced at runtime on P: drive, gitignored)

*Existing infrastructure (00_config.sas macros, src libname) covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SHA comparison results accurate | Block 1 | Requires P: drive file reads | Run Block 1, inspect sha_identical_flag column vs known 80,233-byte difference files |
| ID type detection correct | Block 2 | Runtime-only (P: drive SAS datasets) | Check log for reported type (numeric vs character) for r7/r8 |
| Match rates reproduced with provenance | Block 3 | Runtime comparison + git search | Confirm git log task result cited in PCM-D-28 |
| ENCRYPTED_MRN PHI guard honored | All blocks | Log inspection | Confirm no min/max/sample values for ENCRYPTED_MRN appear in any log line or CSV row |
| PCM-D-28 v2.3 condition is specific | DECISIONS.md | Human review | Confirm condition names a concrete artifact (e.g., "a 2022 Crypto file") not vague "investigate later" |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 600s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
