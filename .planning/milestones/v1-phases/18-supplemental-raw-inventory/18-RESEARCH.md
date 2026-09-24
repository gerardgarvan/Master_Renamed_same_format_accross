# Phase 18: Supplemental Raw Gap Diagnostic — Research

**Researched:** 2026-09-16
**Domain:** SAS 9.4 — diagnostic reporting, key comparison, column-level gap-fill audit
**Confidence:** HIGH (all findings grounded in Phase 16 executed spec and existing SAS source)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01: 2022 ID mismatch handling**
Program runs the diagnostic (5 base IDs not in r9 vs 5 r9 IDs not in base with lengths, plus
`length()` frequency tables for both non-matching sets), writes `qc\18_id_diagnostic.txt`,
and continues. The only `%abort cancel` in the program is the D15 gate at the end. Gerard
inspects the diagnostic and decides whether a numeric-to-char cast or another fix applies.
PCM-D-16 cannot be auto-closed in code. Any 2022 fix is Phase 19+ work.

**D-02: Gap-fill scope and metrics**
Compute on all files with matched IDs: r1 (22,472), r2 (14,778), r3 (2,688), r4 (7,695),
r5 (9,462), r6 (9,462), r9 (31,935). r7 and r8 excluded until PCM-D-16 is resolved.
IN_BASE metric applies where IN_BASE non-key columns exist: r1 (2), r2 (101), r3 (7), r5 (1),
r9 (3). r4 and r6 contribute only the NEW-column metric.
Per column per file: n_matched, n_fillable (base missing / raw populated), n_equal,
n_conflict, n_raw_populated (NEW only). Sorted by n_fillable desc within IN_BASE, then
n_raw_populated desc within NEW.

**D-03: PCM-D-15 decision gate**
Phase 18 ends with `%let D15_APPROVED=0`. The program writes `qc\18_gap_candidates.txt`.
Gerard reviews, records approved columns in `docs/DECISIONS.md`, then sets the flag to 1.
Phase 17 cannot run until the gate is cleared. PCM-D-15 is Gerard's decision for Phase 18
scope; Price may be consulted before the flag is set.

**D-04: Program naming and outputs**
SAS program: `sas/18_supplemental_raw_gap.sas`
Outputs:
- `qc\18_id_diagnostic.txt` — 2022 ID comparison
- `qc\18_gap_candidates.txt` — per column per file gap table (sorted per D-02)
- `logs\18_supplemental_raw_gap.log`

**D-05: Phase ordering note**
Phase 17 is downstream of Phase 18. Phase 17's `work.analysis_base_ext` takes columns
approved under PCM-D-15. The roadmap entry for Phase 17 should state this dependency.

### Claude's Discretion

- Whether to produce a single combined gap table or one section per file
- Macro structure (one macro per file vs a generalized loop)
- Whether the ID diagnostic and the gap counts are two sections of one program or two programs
  (`18a`, `18b`); one program is acceptable now that the diagnostic does not abort

### Deferred Ideas (OUT OF SCOPE)

- Actual gap-fill joins (merging raw values into `g.analysis_base`) — Phase 17+ work
- 2022 ID format fix / cast application — gated on PCM-D-16 resolution; Phase 18 only diagnoses
- r7/r8 gap-fill (2022 files) — deferred until PCM-D-16 is resolved
</user_constraints>

---

<phase_requirements>
## Phase Requirements

Phase 18 requirements are not yet formally defined in REQUIREMENTS.md or ROADMAP.md.
Based on CONTEXT.md decisions and Phase 16 findings, the following requirements are proposed
for the planner to formalize:

| ID (proposed) | Description | Research Support |
|---|---|---|
| RAW-08 | 2022 ID diagnostic: 5 base IDs not in r9 / 5 r9 IDs not in base with lengths, plus length frequency tables for both non-matching sets; written to `qc\18_id_diagnostic.txt`; program continues (no abort) | D-01; Phase 16 "2022 ID mismatch" finding |
| RAW-09 | Gap-fill counts on matched IDs for r1, r2, r3, r4, r5, r6, r9: per column: bucket, n_matched, n_fillable, n_equal, n_conflict, n_raw_populated; written to `qc\18_gap_candidates.txt` | D-02; Phase 16 column overlap table |
| RAW-10 | r2 large column families (dCDT, LINUS) reported as rollups (family, n_cols, median n_raw_populated) with individual detail in an appendix section | CONTEXT.md specifics; 3,341 dCDT + 251 LINUS columns |
| RAW-11 | PCM-D-15 gate: `%let D15_APPROVED=0` at program end; program aborts if flag remains 0 on re-run beyond this line | D-03 |
| RAW-12 | `raw_path` moved to `00_config.sas` and referenced by both `16_raw_inventory.sas` and `18_supplemental_raw_gap.sas` | D-04 canonical refs; 00_config.sas currently lacks raw_path |
</phase_requirements>

---

## Summary

Phase 18 is a pure diagnostic/reporting program. It delivers two follow-on items from Phase 16
that were explicitly deferred as "16b": a 2022 ID mismatch diagnostic and a per-column gap-fill
candidate table. No data is modified. No `g.*` dataset is written. The program reads
`g.analysis_base` and the raw files under `&raw_path`, and writes two QC text files.

The 2022 mismatch (r7/r8/r9 matching 0 base rows on the 2022 cohort) is diagnosed, not
fixed. Phase 16 established that r9 is character and still shows the mismatch, so a simple
`cats()` cast is ruled out as the sole explanation. The diagnostic prints 5+5 sample IDs with
lengths and frequency-distributes the length of all non-matching IDs on both sides.

The gap-fill table enables Gerard (and optionally Price) to decide which raw columns are
approved for later join into `g.analysis_base` (PCM-D-15). Phase 17
(`17_summary_stats_by_domain.sas`) is gated on that approval via a `%let D15_APPROVED=0`
flag — identical in mechanics to the `DOMAIN_MAP_APPROVED` gate already in Phase 17.

**Primary recommendation:** Structure the program as two clearly separated sections within one
file — Section A (ID diagnostic, always runs) and Section B (gap counts, always runs) — with
the `%let D15_APPROVED=0` gate at the very end. Reuse the `%import_csv` / `%import_xlsx`
macros from Phase 16 rather than re-importing; the Phase 16 program established the import
pattern and the raw files are read-only.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SAS 9.4M8 | M8 | All computation, I/O, ODS FILE output | Project constraint; already installed |
| Base SAS (PROC SORT, DATA step, PROC SQL) | 9.4 | Merge, counting, sorting, key comparisons | Only tool available |
| ODS TEXT / FILE statement | 9.4 | Write `.txt` QC artifacts | Used in all prior phases; avoids ODS EXCEL dependency for diagnostic outputs |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| PROC FREQ | 9.4 | Length frequency tables for ID diagnostic | ID diagnostic section; also for conflict/equal/fillable counts if preferred over DATA step |
| PROC MEANS / PROC SUMMARY | 9.4 | Median n_raw_populated for r2 family rollups | r2 dCDT/LINUS family summary |
| dictionary.columns | 9.4 system | Column metadata (type, length, name) for bucketing | IN_BASE detection; already used in Phase 16 |
| dictionary.tables | 9.4 system | Sheet enumeration for XLSX files | r2/r3/r4 multi-sheet; already used in Phase 16 |

### No External Packages

This phase uses only Base SAS. No SAS/STAT, SAS/ACCESS, or third-party macros.

**Installation:** None required.

---

## Architecture Patterns

### Recommended Program Structure

```
sas/18_supplemental_raw_gap.sas
  Section 0: Config, libname g, log routing, preconditions (%assert_base)
  Section 1: Macro library (%import_csv, %import_xlsx, %fail_out, %gate_d15, etc.)
  Section 2: raw_path definition (move to 00_config.sas per D-04/canonical refs)
  Section A: 2022 ID Diagnostic
    A-1  Import r9 (read-only, reuse %import_csv)
    A-2  Anti-join: base IDs not in r9 (2022 stratum only)
    A-3  Anti-join: r9 IDs not in base
    A-4  5-sample print + length() frequency table for each non-matching set
    A-5  Write qc\18_id_diagnostic.txt (ODS TEXT or FILE)
  Section B: Gap-fill counts
    B-1  Import r1, r2, r3, r4, r5, r6, r9 (reuse macros; skip r7, r8)
    B-2  For each file: merge matched IDs with g.analysis_base on key
    B-3  For IN_BASE columns: count fillable / equal / conflict per column
    B-4  For NEW columns: count raw_populated per column
    B-5  Rollup r2 dCDT/LINUS families (family, n_cols, median n_raw_populated)
    B-6  Write qc\18_gap_candidates.txt (per-file summary block + detail + r2 appendix)
  Section C: D15 gate
    C-1  %let D15_APPROVED = 0;
    C-2  %gate_d15; /* aborts if not 1 */
  Section D: Log restore
```

### Pattern 1: Gate Macro (replicate from Phase 17)

**What:** A `%let FLAG=0` at program end with a gate macro that `%abort cancel`s if the
flag is still 0. Gerard sets it to 1 after reviewing the output.

**When to use:** Any human-review checkpoint that must block downstream phases.

**Example (from `17_summary_stats_by_domain.sas`, line 145 / 196-200):**
```sas
%let D15_APPROVED = 0;

%macro gate_d15;
  %if &D15_APPROVED ne 1 %then %do;
    %fail_out(msg=PCM-D-15 awaiting approval -- set D15_APPROVED=1 after reviewing 18_gap_candidates.txt);
  %end;
%mend gate_d15;

/* ... all work above ... */

%gate_d15;  /* last executable line */
```

### Pattern 2: Type-Aware Equality Comparison

**What:** Comparing a raw column value to its base counterpart requires type coercion.
Both sides must be `strip(cats(...))` for equality so numeric vs character differences are
not silently lost.

**When to use:** Computing n_equal / n_conflict for IN_BASE columns in Section B.

```sas
/* Within a DATA step merge on matched IDs */
length _raw_str $64 _base_str $64;
_raw_str  = strip(cats(raw_value));
_base_str = strip(cats(base_value));

if missing(base_value) and not missing(raw_value) then n_fillable + 1;
else if _raw_str = _base_str then n_equal + 1;
else if not missing(base_value) and not missing(raw_value) then n_conflict + 1;
```

Note: char/num type differences between raw and base on the same column name are themselves
a reportable finding (PCM-T-13 context; dictionary.columns.type is `'char'`/`'num'`, not 1/2).

### Pattern 3: Import Reuse (do NOT re-implement)

**What:** `%import_csv` (PROC IMPORT, `guessingrows=max`) and `%import_xlsx` (libname `xin`
with XLSX engine, sheet enumeration via `dictionary.tables`, copy via `call execute`) from
Phase 16.

**When to use:** Every raw file import in Sections A and B.

Since `16_raw_inventory.sas` does not yet exist in git (the sas/ glob returned no file),
the macro code must be reconstructed from the Phase 16 spec or the planner must include a
Wave 0 task to retrieve it from the executed log or the plan doc. The macros are documented
in Phase 16's CONTEXT.md and summary doc.

### Pattern 4: r2 Family Rollup

**What:** 3,341 dCDT and 251 LINUS columns would produce unreadable output row-by-row.
Report them as: family name, n_cols, median n_raw_populated. Append individual column detail
to an appendix section of the same text file.

**When to use:** Section B-5, immediately before writing `qc\18_gap_candidates.txt`.

### Anti-Patterns to Avoid

- **Bare open-code `%IF`** — all conditional logic inside named macros (PCM rule, enforced throughout project)
- **`%abort cancel` outside a named macro** — every abort must be inside `%fail_out` or equivalent
- **`cats()` for the 2022 key comparison without checking the output** — r9 is already character and still mismatches; do not conclude a cast explains it until the diagnostic prints confirm
- **`&SQLOBS`** — use explicit `SELECT COUNT(*) INTO :macvar TRIMMED` instead
- **Apostrophes or embedded semicolons in `%PUT` text** — ASCII-only session rule
- **In-place dataset rewrite (`data X; set X;`)** — forbidden (PCM-T-02)
- **Writing to `g.*` datasets** — Phase 18 is read-only on all `g.*` and all `raw\` sources
- **Assuming `00_config.sas` assigns `libname g`** — it does NOT; each program must issue `libname g "&g_path";` after the `%include`
- **Hard-coding `raw_path`** — must be moved into `00_config.sas` as part of this phase (canonical ref D-04)

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CSV import | Custom infile/input | `%import_csv` from Phase 16 (`guessingrows=max`) | Already handles key detection, row assertions; duplication creates divergence risk |
| XLSX sheet enumeration | Hard-coded sheet names | `%import_xlsx` from Phase 16 (dictionary.tables + call execute) | Sheet names can change; already proven against r2's 3,987-column sheet |
| Length frequency table | Manual DATA step histogram | PROC FREQ on a `length()` derived variable | Two lines vs. twenty; handles ties and missing automatically |
| Column metadata | Manual PROC CONTENTS | `dictionary.columns` in PROC SQL | Already used for IN_BASE bucketing in Phase 16; no re-learn cost |
| Gap counts | Column-by-column hard-coded DATA steps | A parameterized macro or PROC SQL group-by over a transposed/stacked view | 101 IN_BASE columns in r2 alone — not manually enumerable |

---

## Common Pitfalls

### Pitfall 1: Silent Zero Coverage from Missing libname g

**What goes wrong:** `00_config.sas` defines `&g_path` but does NOT issue `libname g`. If
the program omits `libname g "&g_path";` after the `%include`, every reference to
`g.analysis_base` resolves with a warning or to the WORK library, producing 0-row counts with
no error.

**Why it happens:** Phase 16's first run produced zero coverage for exactly this reason.

**How to avoid:** Always issue `libname g "&g_path";` as the first line after the
`%include "...00_config.sas";`. Then call `%assert_base` (which aborts if `g.analysis_base`
is unreachable) before any read.

**Warning signs:** n_matched = 0 for all files on a run that previously produced non-zero counts.

### Pitfall 2: cats() Cast Does Not Explain the 2022 Mismatch

**What goes wrong:** The instinct is to `cats(numeric_id)` and retry the join. r9 is already
character and still shows 9,215 raw-only / 9,215 base-only IDs. A cast alone will not fix it.

**Why it happens:** master_data_7 (2022) carried PRECEDE_STUDY_ID as NUM8 — possible leading
zeros, scientific notation, or a different ID series entirely.

**How to avoid:** The diagnostic must print both sides raw, with lengths, before any cast is
attempted. PCM-D-16 is open and cannot be auto-closed in code.

**Warning signs:** After a `cats()` join attempt, n_matched still 0 and the printed samples
show values that look structurally different (e.g., one side has leading zeros, one has `E`
notation).

### Pitfall 3: dictionary.columns.type Is a String, Not a Number

**What goes wrong:** Filtering for numeric columns with `where type = 1` returns nothing.
The correct values are `'num'` and `'char'`.

**Why it happens:** PCM-T-13 — this has bitten the project before.

**How to avoid:** Always filter with `where type = 'num'` (or `'char'`).

### Pitfall 4: r2 Section-Divider Columns Counted as Data

**What goes wrong:** Eight 100%-missing r2 columns (`IDR Variables Only`, `Bloods`, `LINUS`,
`garvan_added_variables`, etc.) are structural section dividers, not data. If included in the
NEW-column metric they inflate the "candidates" list.

**Why it happens:** PROC IMPORT assigns them as variables; they appear in dictionary.columns.

**How to avoid:** Identify and exclude them by name before computing n_raw_populated. List
them explicitly in the QC output as "section divider — excluded."

### Pitfall 5: r2 Gap Table Unreadable at 3,885 Rows

**What goes wrong:** Writing one row per r2 column produces a 3,885-row detail section that
buries the clinically interesting candidates.

**Why it happens:** r2 has 3,341 dCDT + 251 LINUS feature columns.

**How to avoid:** Implement the family rollup (Pattern 4): per-file summary block at top, then
high-level domain block, then individual detail as an appendix. The output must let the
candidates (Frailty_Score, Edu_Years, MMSE 3-word, lab columns) be found without reading 4,000 rows.

### Pitfall 6: `raw_path` Not in 00_config.sas

**What goes wrong:** Phase 18 needs `raw_path`; Phase 16 defined it as a `%let` inside its
own program. If Phase 18 duplicates it, the two can diverge silently.

**Why it happens:** Phase 16 did not move `raw_path` to config.

**How to avoid:** Wave 0 task: add `%let raw_path = ...;` to `00_config.sas`, remove the
local definition from `16_raw_inventory.sas` if that file is being edited, and have Phase 18
read it from config.

---

## Code Examples

### ID Diagnostic Anti-Join (Section A-2)

```sas
/* Source: Phase 16 findings and standard SAS DATA step anti-join */
proc sort data=g.analysis_base(keep=PRECEDE_STUDY_ID) out=work.base_ids nodupkey; by PRECEDE_STUDY_ID; run;
proc sort data=work.raw_r9(keep=PRECEDE_STUDY_ID)      out=work.r9_ids   nodupkey; by PRECEDE_STUDY_ID; run;

data work.base_not_in_r9;
  merge work.base_ids (in=inb) work.r9_ids (in=inr);
  by PRECEDE_STUDY_ID;
  if inb and not inr;
  id_length = length(trim(PRECEDE_STUDY_ID));
run;

data work.r9_not_in_base;
  merge work.r9_ids (in=inr) work.base_ids (in=inb);
  by PRECEDE_STUDY_ID;
  if inr and not inb;
  id_length = length(trim(PRECEDE_STUDY_ID));
run;
```

### Gate Macro (Section C — replicated from Phase 17 pattern)

```sas
%let D15_APPROVED = 0;   /* Gerard sets to 1 after reviewing qc\18_gap_candidates.txt */

%macro gate_d15;
  %if &D15_APPROVED ne 1 %then %do;
    %fail_out(msg=PCM-D-15 awaiting approval -- review 18_gap_candidates.txt then set D15_APPROVED=1);
  %end;
%mend gate_d15;

/* ... all substantive sections ... */

%gate_d15;
```

### Type-Safe Column Comparison for IN_BASE Gap Counts

```sas
/* For each IN_BASE column col_x that exists in both raw_rN and g.analysis_base */
data work.gap_col_x;
  merge work.matched_rN(keep=id col_x rename=(col_x=raw_val))
        work.base_matched(keep=id col_x rename=(col_x=base_val));
  by id;
  length _r $200 _b $200;
  _r = strip(cats(raw_val));
  _b = strip(cats(base_val));
  fillable = (missing(base_val) and not missing(raw_val));
  equal    = (not missing(raw_val) and not missing(base_val) and _r = _b);
  conflict = (not missing(raw_val) and not missing(base_val) and _r ne _b);
run;

proc sql noprint;
  select sum(fillable), sum(equal), sum(conflict)
  into :n_fill trimmed, :n_eq trimmed, :n_conf trimmed
  from work.gap_col_x;
quit;
```

---

## Runtime State Inventory

This is a read-only reporting phase — no rename, refactor, or migration.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | `g.analysis_base` (41,150 rows, 125 cols) — read-only | None |
| Live service config | None | None |
| OS-registered state | None | None |
| Secrets/env vars | `raw_path` currently a `%let` inside 16_raw_inventory.sas — not in config | Move to 00_config.sas as Wave 0 task |
| Build artifacts | `16_raw_inventory.sas` not present in git working tree (glob returned nothing) | Planner must note: macros must be reconstructed from Phase 16 plan docs or obtained from executed version |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| SAS 9.4M8 | All computation | Assumed yes (project constraint) | 9.4M8 | None — project-mandated |
| P: drive (raw\ path) | All raw file imports | Assumed yes (used in Phase 16) | — | None — source data lives here |
| g.analysis_base | Merge spine, key comparisons | Present (41,150 rows verified Phase 16) | — | %assert_base aborts if missing |
| qc\ directory (P: path) | Output files | Assumed yes | — | Program must check with %sysfunc(fileexist) before routing ODS |
| logs\ directory (P: path) | Log routing | Assumed yes | — | Same check |

**Missing dependencies with no fallback:** None identified beyond the project-standard P: drive assumption.

**Note on 16_raw_inventory.sas:** The file does not appear in the git working tree (the `sas/` directory glob returned no result for this program). The Wave 0 plan task must either (a) confirm the file exists on disk outside git, or (b) reconstruct the `%import_csv` and `%import_xlsx` macros from the Phase 16 plan and summary documents. Do not assume the macros are importable.

---

## Validation Architecture

No automated test framework is configured for this project. Validation follows the established
PCM pattern: SAS assertions within the program + human QC artifact review.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SAS 9.4 in-program assertions (`%fail_out` / `%abort cancel`) |
| Config file | None — assertions are inline |
| Quick run command | Submit `sas/18_supplemental_raw_gap.sas` in a fresh SAS session |
| Full suite command | Same (single program) |

### Phase Requirements to Validation Map

| Req ID | Behavior | Test Type | Validation Artifact |
|--------|----------|-----------|---------------------|
| RAW-08 | 2022 diagnostic file written, contains 5+5 sample IDs and length freq tables | Manual review | `qc\18_id_diagnostic.txt` |
| RAW-09 | Gap candidates file written, per-column per-file counts correct | Manual review | `qc\18_gap_candidates.txt` |
| RAW-10 | r2 dCDT/LINUS families reported as rollups | Manual review | Rollup block in `qc\18_gap_candidates.txt` |
| RAW-11 | D15 gate fires (program aborts at end until flag set) | Smoke test — run without setting flag, confirm abort | SAS log shows `%abort cancel` |
| RAW-12 | `raw_path` in `00_config.sas` and both programs reference it | Code review | `00_config.sas` diff |

### Wave 0 Gaps

- [ ] Confirm or reconstruct `%import_csv` / `%import_xlsx` macros — required before Section A or B can be coded
- [ ] Add `%let raw_path = ...;` to `00_config.sas` — required before any raw file reference
- [ ] Confirm `qc\` and `logs\` directories exist on P: with `%sysfunc(fileexist(...))` guards

---

## Open Questions

1. **Is `16_raw_inventory.sas` available on disk (outside git)?**
   - What we know: The git working tree glob returned no file at `sas/16_raw_inventory.sas`.
   - What's unclear: Whether the file was never committed (written only to P: or a working
     copy not yet committed) or was deleted.
   - Recommendation: Wave 0 task verifies with `%sysfunc(fileexist(...))` or a dir listing.
     If absent, `%import_csv` / `%import_xlsx` must be reconstructed from Phase 16 plan docs.

2. **Exact value of `raw_path`**
   - What we know: Phase 16 spec says it was a `%let raw_path = ...` inside
     `16_raw_inventory.sas`, not in config.
   - What's unclear: The exact string (likely `P:\PeCAN Master Data\Gerard\raw` or similar).
   - Recommendation: Wave 0 task reads `16_raw_inventory.sas` from disk (or the Phase 16
     plan docs) and extracts the `%let raw_path` line before writing the new `00_config.sas` entry.

3. **Are the 2022 IDs in g.analysis_base the same as in master_data_7 (numeric)?**
   - What we know: r9 is character and still shows 9,215 mismatches; cast alone is unlikely
     to explain it.
   - What's unclear: Whether the IDs are a different series entirely or a formatting artefact
     (leading zeros, scientific notation).
   - Recommendation: The diagnostic output (5+5 samples + length distribution) answers this.
     Phase 18 must not attempt to resolve it — only display it.

4. **r2 section-divider column names — exact list**
   - What we know: Eight column names listed in the Phase 16 summary doc.
   - What's unclear: Whether these are the SAS variable names exactly as imported (PROC IMPORT
     may have modified them).
   - Recommendation: Wave 0 task imports r2 and checks `dictionary.columns` against the
     known divider label strings before exclusion.

---

## Sources

### Primary (HIGH confidence)
- `.planning/phases/18-supplemental-raw-inventory/18-CONTEXT.md` — all locked decisions, code patterns, pitfalls
- `16-supplemental-raw-inventory.md` — Phase 16 executed spec: key coverage, column overlap, 2022 mismatch description, r2 family breakdown
- `sas/00_config.sas` — confirmed absence of raw_path and libname g
- `sas/17_summary_stats_by_domain.sas` lines 145, 196-200 — exact gate macro pattern

### Secondary (MEDIUM confidence)
- `.planning/STATE.md` — project conventions (PCM-T-01 through T-13, established decisions)
- `.planning/REQUIREMENTS.md` — requirement traceability; Phase 18 requirements not yet formally registered

### Tertiary (LOW confidence)
- None — all findings grounded in project artifacts

---

## Metadata

**Confidence breakdown:**
- Program structure: HIGH — grounded in CONTEXT.md decisions and Phase 16 spec
- SAS patterns (gate macro, anti-join, type comparison): HIGH — exact code from Phase 17 available
- Import macros: MEDIUM — macros documented in Phase 16 spec but `16_raw_inventory.sas` not confirmed in git
- raw_path exact value: LOW — not visible in any committed file; must be retrieved from disk or log

**Research date:** 2026-09-16
**Valid until:** Stable (no external dependencies; pure SAS pipeline)
