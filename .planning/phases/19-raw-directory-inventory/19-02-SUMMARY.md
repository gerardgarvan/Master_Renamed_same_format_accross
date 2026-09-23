---
phase: 19-raw-directory-inventory
plan: 02
status: complete
completed: "2026-09-23"
commits:
  - aad8fc4  # R3-B-01: unquoted XLSX sheet ref (SHEET1 case mismatch)
  - 583a129  # R3-B-02: datalines4 for embedded semicolons in KEY_LEGEND notes
  - 0a69877  # R3-B-02b: correct infile syntax (infile datalines, not datalines4)
---

# Plan 19-02 Summary — Run, Verify, Deliver

## What Was Done

Ran `sas/19_raw_dir_inventory.sas` in three iterations on the P: machine, diagnosing
and fixing two runtime bugs before achieving a clean run.

### Bugs Fixed This Plan

**R3-B-01** (`aad8fc4`) — XLSX sheet name case-sensitivity mismatch.
`dictionary.members` always returns uppercase memnames (e.g., `SHEET1`). Using that
value as a SAS name literal (`"SHEET1"n`) triggers a case-sensitive lookup in the XLSX
engine, which fails when the actual Excel tab is `Sheet1`. The fix: use an unquoted SAS
name (`set _xlw.&&_sh&j;`) for sheets whose memname is a valid SAS identifier (starts
with letter or underscore). Unquoted SAS names go through SAS's case-insensitive
resolution and correctly locate the tab. Sheets with digit-prefix names fall back to
the literal form (they are non-master XLSX files not required by D-06). This fixed
`ALL_AIM2_MASTER_DATASET_20210917.xlsx` (md8) and two other XLSX files, bringing
profiled count from 23 → 26 and allowing `assert_masters_profiled` to pass.

**R3-B-02 / R3-B-02b** (`583a129`, `0a69877`) — Embedded semicolons in DATALINES
terminated the `KEY_LEGEND` block early. Several notes column values contain `;`
(e.g., `". for num; blank for char"`), which SAS treated as DATALINES terminators,
producing six `ERROR 180-322` lines and truncating those note values. Fix: switch to
`datalines4;` / `;;;;` terminator. A follow-up commit corrected the INFILE clause
(`infile datalines` is correct; only the `DATALINES` statement itself takes the `4`
suffix).

### Final Run Results

| Assertion | Result |
|-----------|--------|
| D-02b: all 8 required extracts found in raw\master | passed |
| assert_families: FAMILIES full-join balanced | passed |
| assert_inv06: total=31 profiled=26 listed=2 failed=3 | passed |
| assert_masters_profiled: all 8 md1-md8 at profiled status | passed |
| ERROR lines | 4 (XLSX engine, digit-prefix sheets — expected, non-master) |
| ERROR 180-322 lines | 0 |

### Deliverables Confirmed

| File | Status |
|------|--------|
| `qc/19_raw_inventory.xlsx` | Produced; 7 sheets; KEY leftmost |
| `qc/19_raw_files.csv` | Produced; md3 row with 64-char SHA-256 present |

Workbook sheet inventory (verified by opening locally):

| Sheet | Data Rows |
|-------|-----------|
| KEY | 16 |
| FILES | 31 |
| SHEETS | 5 |
| VARIABLES | 1,574 |
| KEY_COLUMNS | 60 |
| RECONCILIATION | 31 |
| FAMILIES | 40 |

### COM Scouting Review (R2-B-03)

`WORK.COM_SCOUT` had **0 rows** — no residual `COM*` variables outside the known
prefix families (`COMPLICATION_SUM`, `COMP10_`, `LINUS`). FAMILIES DATALINES prefix
list is confirmed complete. No updates required.

### Human Checkpoint

Workbook opened and verified: KEY leftmost, all seven sheets present, UF blue headers,
pct_missing and pct_sentinel as separate columns, sheet_name column in VARIABLES,
match_basis and UNENC_MRN in KEY_COLUMNS, md3 row in FILES with status=profiled.
COM scouting confirmed — all residual COM* columns are dCDT clock columns (0 found).
