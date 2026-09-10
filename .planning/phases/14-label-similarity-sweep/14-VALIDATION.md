---
phase: 14
slug: label-similarity-sweep
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-29
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS log inspection + file-existence checks (no test runner — SAS batch) |
| **Config file** | none |
| **Quick run command** | `%sysrc` check + `proc contents data=docs/label_similarity_candidates.csv; run;` |
| **Full suite command** | Run `sas/14_label_similarity.sas` and inspect `qc/14_label_similarity.txt` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Verify output file exists and has expected structure
- **After every plan wave:** Full SAS run against `g.master_data_harmonized`
- **Before `/gsd:verify-work`:** All SAS programs complete with 0 ERRORs in log
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 14-01-01 | 01 | 1 | HARM-03 | file check | `test -f qc/14_label_similarity.txt` | ❌ W0 | ⬜ pending |
| 14-01-02 | 01 | 1 | HARM-02 | log scan | grep for `ERROR` absent in log | ❌ W0 | ⬜ pending |
| 14-02-01 | 02 | 1 | HARM-09 | file check | `test -f qc/14_label_similarity.txt` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `qc/` directory exists (already present from prior phases)
- [ ] `g.master_data_harmonized` is accessible (prerequisite)
- [ ] `docs/precede_dictionary.csv` is readable

*Existing infrastructure covers all phase requirements — no new test framework needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Candidate pair list is tractable for human review | HARM-03 | Threshold is empirical; program must log score distribution first | Review `qc/14_label_similarity.txt`, confirm < 100 pairs unless threshold justifies more |
| Similarity measure and threshold stated in code comments | HARM-03 | Comment verification | Open `sas/14_label_similarity.sas`, confirm a comment states the measure name and threshold value |
| SSDI and CPT1 concept profiles are human-readable | HARM-09 | ODS output | Open `qc/14_label_similarity.txt`, confirm SSDI family and CPT1 pair each have a profile section |
| `VARIABLE_RECTIFICATION.xlsx` NOT imported as crosswalk | HARM-02 | Code audit | Confirm no `PROC IMPORT` referencing VARIABLE_RECTIFICATION in 14_label_similarity.sas |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

---

## Corrections applied 2026-08-29

Every artifact name in this document referred to a file no plan creates, so all
checks would have failed against a correct implementation -- the worst kind of
validation error, because it reads as an implementation bug.

| Was | Now |
|---|---|
| `sas/14_label_sweep.sas` | `sas/14_label_similarity.sas` |
| `qc/14_label_candidates.txt` | `qc/14_label_similarity.txt` |
| `qc/14_concept_evidence_ssdi_cpt1.txt` | `qc/14_label_similarity.txt` (Section B appends) |
| `g.label_sim_candidates` | `docs/label_similarity_candidates.csv` |

Plan 14-02 is wave 2, matching its own frontmatter; this document said wave 1.

### The full artifact list to check

- `sas/14_label_similarity.sas`
- `docs/label_similarity_candidates.csv`
- `docs/concept_decisions_EXT_TEMPLATE.csv`
- `docs/LABEL_SIMILARITY_EVIDENCE.xlsx`
- `docs/CONCEPT_EVIDENCE_EXT.xlsx`
- `qc/14_label_similarity.txt`

### Two checks worth adding

**Calibration.** Assert that `Death_Date_Y_N` / `IsDead_Y_N` scores above
threshold on at least one measure. Phase 10 proved that pair identical on all
8,730 overlapping rows, so if the scorer misses it the threshold is wrong. A
sweep returning zero candidates otherwise looks like a clean result.

**Template schema.** Assert `concept_decisions_EXT_TEMPLATE.csv` carries exactly
the seven headers 10b requires: concept, varname, value_txt, target_value,
confirmed, harmonized_name, priority. A wrongly shaped template fails at 10b in
Phase 15, one phase away from where the mistake was made.
