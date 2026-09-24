# Phase 8: Documentation & Handoff - Research

**Researched:** 2026-08-27
**Domain:** SAS 9.4 data dictionary generation, ODS EXCEL, pipeline finalization
**Confidence:** HIGH (all findings drawn from direct code inspection and project artifacts)

---

## Project Constraints (from CLAUDE.md)

- SAS 9.4M8 on Windows; session encoding is NOT UTF-8 -- all text artifacts must be ASCII only
- Read-only on `master_data_1..8.sas7bdat` and everything under `raw\master`
- No PHI in git: `.gitignore` excludes `*.sas7bdat`, `*.xlsx`, `*.csv`, `data/` tree
- Repo on local disk (C:), not P: -- data, logs, and QC outputs live on P: outside git
- Delivery: UF colors (#0021A5, #FA4616) on visual deliverables; KEY sheet leftmost in workbooks
- Do not edit files outside a GSD workflow unless explicitly bypassed

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DOC-01 | User can run `08_dictionary.sas` to produce `docs/DATA_DICTIONARY.xlsx` with every variable: source, type, length, coverage, derivation rule | `dictionary.columns` + PROC MEANS pattern below; ODS EXCEL confirmed available in SAS 9.4M8 |
| DOC-02 | User can open `docs/DECISIONS.md` and see every decision resolved and attributed | **The requirement text says "D-01 through D-07" and is now out of date -- the register runs to D-11, plus D-12 proposed here.** D-08..D-11 are resolved; D-05 is NOT a formality (see Pitfall 7). Verify the full range, not the original seven. |
| DOC-03 | User can run `99_run_all.sas` in a clean SAS session against read-only sources and have all programs complete without manual steps | `08_dictionary.sas` must be added to `99_run_all.sas`; the `%in_pipeline` guard pattern is already established |
| DOC-04 | User can verify git history shows each phase as a reviewable commit | Git process only; no SAS code needed |
</phase_requirements>

---

## Summary

Phase 8 is a finalization phase with three distinct deliverables: (1) a SAS program `08_dictionary.sas` that generates `docs/DATA_DICTIONARY.xlsx`, (2) a final audit of `docs/DECISIONS.md` to confirm all decisions through D-07 are resolved, and (3) verification that `99_run_all.sas` runs clean from scratch after `08_dictionary.sas` is added to it.

The data dictionary program has four moving parts: pull column metadata from `dictionary.columns`, compute coverage percentages from `g.master_data_merged`, look up ownership from `qclib.ownership_map`, and assign a derivation category to each variable. The derivation logic is the most bespoke piece -- it cannot be automated without a mapping table.

The `%abort cancel` return-code question requires a deliberate decision and one batch-mode test, not code. It has no impact on the SAS programs themselves but must be settled before `99_run_all.sas` is ever scheduled on Windows.

**Primary recommendation:** Build `08_dictionary.sas` in three steps: metadata join (no writes), coverage computation (PROC MEANS over `g.master_data_merged`), then a single ODS EXCEL output with the merged result. Assert variable count matches PROC CONTENTS before writing. Add the program to `99_run_all.sas` last, after it runs clean standalone.

---

## What is already done (do NOT redo)

| Item | State | Location |
|------|-------|----------|
| PCM-D-01 | Resolved 2026-08-27 | docs/DECISIONS.md |
| PCM-D-02 | Resolved 2026-08-27 | docs/DECISIONS.md |
| PCM-D-03 | Resolved 2026-08-27 | docs/DECISIONS.md |
| PCM-D-04 | Resolved 2026-08-27 | docs/DECISIONS.md |
| PCM-D-05 | Pending -- resolves in Phase 7 Plan 02 | docs/DECISIONS.md |
| PCM-D-06 | Resolved | docs/DECISIONS.md |
| PCM-D-07 | Resolved (deferred, not pursuing) | docs/DECISIONS.md |
| PCM-D-08 | Resolved 2026-08-27 | docs/DECISIONS.md |
| PCM-D-09 | Resolved 2026-08-27 | docs/DECISIONS.md |
| PCM-D-10 | Resolved 2026-08-27 | docs/DECISIONS.md |
| PCM-D-11 | Closed 2026-08-27 | docs/DECISIONS.md |
| `docs/data_dictionary_notes.txt` | Written in Phase 6 | docs/data_dictionary_notes.txt |
| `qclib.ownership_map` | Written in Phase 2 | P:/.../merge/qclib |
| `99_run_all.sas` Phases 1-7 | Written and verified | sas/99_run_all.sas |

DOC-02 is almost satisfied. The only gap: PCM-D-05 resolution will arrive from Phase 7 Plan 02. Phase 8 must verify D-05 is attributed in DECISIONS.md before declaring DOC-02 complete; it need not write the entry.

---

## Architecture Patterns

### Established program structure (copy from 06_reconcile.sas / 07_cohort.sas)

Every Phase 5+ program follows this shell:

```sas
options nodate nonumber ps=max ls=200;
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* suppress per-program log redirect when running under 99_run_all.sas */
%macro restore_log; %if &in_pipeline = 0 %then %do;
  proc printto; run;
%end; %mend;

%macro fail_out(msg=);
  %put ERROR: &msg;
  ods listing;
  %restore_log;
  %abort cancel;
%mend;
```

The `%in_pipeline` guard (value set to 1 by `99_run_all.sas`) suppresses per-program PROC PRINTTO redirection so the master log stays complete. `08_dictionary.sas` must follow the same pattern exactly.

### Adding `08_dictionary.sas` to `99_run_all.sas`

Insert a PHASE 8 block immediately after the Phase 7 block (before "PIPELINE COMPLETE"):

```sas
/* =========================================================================
   PHASE 8 -- Documentation & Handoff
   Reads g.master_data_merged and qclib.ownership_map (read-only).
   Reads docs/data_dictionary_notes.txt for derivation metadata.
   Writes docs/DATA_DICTIONARY.xlsx.
   ========================================================================= */
%put NOTE: ---- Phase 8: Documentation & Handoff --------------------;
%include "&sas_path.\08_dictionary.sas";
%put NOTE: ---- Phase 8 complete --------------------------------------;
```

No libname changes needed -- `g` is still open from Phase 4+. `99_run_all.sas` already sets `%let in_pipeline = 1;` after including `00_config.sas`.

### `dictionary.columns` metadata source

`dictionary.columns` is a SAS read-only view that returns column metadata for all currently assigned librefs. It does NOT require a libname for itself. The key columns for the dictionary are:

| Column | What it gives you |
|--------|-------------------|
| `libname` | library (use to filter to "G") |
| `memname` | dataset name (filter to "MASTER_DATA_MERGED") |
| `name` | variable name (case as stored) |
| `type` | "num" or "char" |
| `length` | stored length in bytes |
| `label` | SAS label if set (may be blank) |
| `format` | assigned format |

```sas
proc sql noprint;
  create table work.dict_meta as
  select upcase(name)   as varname   length=32,
         type,
         length,
         label
  from   dictionary.columns
  where  upcase(libname)  = "G"
    and  upcase(memname)  = "MASTER_DATA_MERGED"
  order by varname;
quit;
```

Confidence: HIGH -- `dictionary.columns` is standard SAS SQL dictionary table, unchanged across SAS 9.x releases.

### Coverage % per variable -- PROC SQL, NOT PROC MEANS

**PROC MEANS CANNOT PROCESS CHARACTER VARIABLES.** `var _character_;` fails with
"Variable X in list does not match type prescribed for this list". An earlier draft of this
document proposed one PROC MEANS pass for `_NUMERIC_` and one for `_CHARACTER_`; the second
does not run. That draft also contradicted itself on whether MEANS NMISS treats a blank
string as missing -- moot, since the procedure never sees character variables.

Use `PROC SQL COUNT()` for BOTH types. `COUNT(var)` counts non-missing values, and for
character variables SAS treats an all-blank string as missing, so one expression covers both
and there is no two-path implementation to keep consistent.

The variable list is driven from `work.dict_meta` (built from `dictionary.columns`), so the
loop covers exactly the columns the dictionary will document -- 173 in the current merged
file, not the "~200+" an earlier draft assumed.

```sas
proc sql noprint;
  select count(*) into :n_total trimmed from g.master_data_merged;
  select count(*) into :n_vars  trimmed from work.dict_meta;
quit;

proc sql;
  create table work.coverage (varname char(32), n_nonmiss num, coverage_pct num);
quit;

%macro coverage_all;
  %local i v n;
  %do i = 1 %to &n_vars;
    proc sql noprint;
      select varname into :v trimmed from work.dict_meta (firstobs=&i obs=&i);
      /* COUNT(var) works for char and num alike; blank char counts as missing */
      select count(&v) into :n trimmed from g.master_data_merged;
      insert into work.coverage
        values("&v", &n, %sysevalf(100 * &n / &n_total));
    quit;
  %end;
%mend coverage_all;
%coverage_all;
```

`firstobs=/obs=` rather than `POINT=`, which cannot be combined with a WHERE and has already
cost this project a silent no-op loop.

Confidence: HIGH for the SQL approach. The PROC MEANS approach in the earlier draft was
wrong for half the variables.

### ODS EXCEL for DATA_DICTIONARY.xlsx

ODS EXCEL is available in SAS 9.4M3+ (confirmed available in 9.4M8). The `docs/` path is on C: (version-controlled), which is correct since xlsx is gitignored but the file itself lives in docs/.

**Wait -- `docs/DATA_DICTIONARY.xlsx` is an xlsx file. The gitignore excludes `*.xlsx`.** This means the file will NOT be committed. It will exist on disk but not in git. The planner must note this: the dictionary is a deliverable artifact on the analyst's machine, not a git artifact.

```sas
ods excel file="&docs_path.\DATA_DICTIONARY.xlsx"
          options(sheet_name="Dictionary"
                  frozen_headers="yes"
                  autofilter="yes"
                  embedded_titles="yes");

proc print data=work.dict_final noobs label;
  var varname type length source derivation coverage_pct label;
run;

ods excel close;
```

For UF colors on column headers, ODS EXCEL supports `style=` overrides via PROC REPORT. Use PROC REPORT instead of PROC PRINT for the final output:

```sas
proc report data=work.dict_final nowd;
  columns varname type length source derivation coverage_pct label;
  define varname / "Variable" style(header)=[background=#0021A5 color=white];
  /* ... other columns ... */
run;
```

Confidence: HIGH -- ODS EXCEL with these options is standard SAS 9.4M3+ syntax.

### Sheet order constraint (KEY sheet leftmost)

CLAUDE.md requires KEY sheet leftmost. In ODS EXCEL, sheets appear in the order they are written. Write the KEY sheet first:

```sas
ods excel file="&docs_path.\DATA_DICTIONARY.xlsx"
          options(sheet_name="KEY");
/* write key/legend content */

ods excel options(sheet_name="Dictionary");
/* write main dictionary */

ods excel close;
```

### Derivation categories for the dictionary

The `derivation` column must be populated from a lookup, not from `dictionary.columns`. The categories established by project decisions are:

| Category | Variables | Derivation text |
|----------|-----------|-----------------|
| md3 spine owner | Most variables where md3 is owner | "md3 spine -- ownership_map" |
| mdN owner (non-md3) | Variables where md1/md2/md4-md8 own | "mdN owner -- ownership rule" (fill N from the RESOLVED owner, not `ownership_map.owner`, which reads CONFLICT for 135 of 163) |
| md8 gap-fill (MRG-06) | Cognitive_Score, Cognitive_Category, Frailty_Score, Frailty_Category, ORAL_MORPHINE_EQUIV_mg_POD_DAY6 | "md3 spine, md8 gap-fill (MRG-06)" |
| Merge-derived flags | rt_envelope_flag, n_sources, in_md1..in_md8 | "derived at merge (Phase 4)" |
| Deliberate multi-column | Death_Date_Y_N, IsDead_Y_N, Death, frailty char/numeric, ISO_SEV variants | "source-specific; kept separate by PCM-D-0X" |

The cleanest implementation: build a `work.derivation_map` dataset in the SAS program with one row per variable and a derivation string. Then join to `dict_meta`. For the ownership-governed variables (the majority), join `qclib.ownership_map` directly to get the owner source and construct the derivation string programmatically.

```sas
/* Join ownership_map to get derivation for most variables */
proc sql noprint;
  create table work.dict_with_deriv as
  select d.varname,
         d.type,
         d.length,
         d.label,
         case
           when o.varname is not null then
             "md" || strip(put(o.source_num,best.)) || " owner (ownership_map)"
           else "derived -- see notes"
         end as derivation length=80
  from   work.dict_meta   as d
  left join qclib.ownership_map as o
    on upcase(d.varname) = upcase(o.varname);
quit;
```

Then overlay the special cases (MRG-06 gap-fill, merge-derived, deliberate multi-column) via UPDATE or a second CASE block.

### `qclib.ownership_map` schema -- KNOWN, do not guess

The columns are `varname`, `owner`, `n_sources`, `sources_present`, `coalesce_flag`. This has
been queried repeatedly in this project; an earlier draft of this document guessed
"varname, source (or equivalent), owner" and used a column `source_num` that does not exist.

**The trap: `owner` holds the literal string `CONFLICT` for every multi-source variable --
135 of 163.** Phase 2 deliberately did not choose owners; it recorded the conflict and left
resolution to Phase 4. So a straight `LEFT JOIN ... select o.owner as source` puts
`CONFLICT` in the dictionary's source column for the large majority of rows, which makes the
central column of the deliverable useless.

**The real owner comes from the resolution RULE**, applied in `04_merge.sas` SECTION 2b:

- md3 if md3 carries the variable (spine)
- otherwise the contributing source with the highest row count
  (md3 41150 > md8 22473 > md1=md2 14778 > md6 9462 > md7 9215 > md4=md5 7695)
- ties to the lowest source number
- explicit override to md7 for the five frailty components
  (`Feels_Exausted`, `Low_Physical_Activity`, `Slow_Walking_Speed`,
   `Unintended_Weight_Loss`, `Week_Grip_Strength`) -- md6 wins on row count but its $1 width
  cannot hold md7's 3-character values

`08_dictionary.sas` must reproduce this, exactly as `04_merge.sas` does. Two copies of the
rule already exist (`04_merge.sas` and the recovery sweep); a third is a maintenance hazard.
**Recommendation: extract the resolution into `sas/00_ownership_rule.sas` and `%include` it
from both `04_merge.sas` and `08_dictionary.sas`,** so the dictionary can never describe a
different ownership than the merge actually applied.

---

## Common Pitfalls

### Pitfall 1: ODS EXCEL writes to docs/ -- file is gitignored

`docs/DATA_DICTIONARY.xlsx` matches `*.xlsx` in `.gitignore`. The file will not be tracked. This is correct per PHI policy, but it means DOC-01 is a manual verification ("file exists on disk") not a git-visible artifact. The plan must not attempt to `git add` it.

**What to do:** The verification task for DOC-01 is: open the file, confirm the sheet count,
confirm variable count matches PROC CONTENTS. That is a human step, not an assertion.

**But this is worth a decision rather than acceptance.** `DATA_DICTIONARY.xlsx` holds variable
names, types, lengths, coverage counts and derivation strings -- no patient rows, no PHI. It is
precisely the kind of artifact that benefits from version history, and it is the primary
handoff deliverable of the whole project. A single negation in `.gitignore`:

```
!docs/DATA_DICTIONARY.xlsx
```

keeps it tracked without weakening the blanket `*.xlsx` rule for source extracts. Recommend
raising this as a decision rather than letting the default exclude the deliverable.

### Pitfall 2: `dictionary.columns` only sees assigned librefs

`dictionary.columns` only returns metadata for librefs open at query time. `08_dictionary.sas` must assign `libname g` before querying `dictionary.columns`. Under `99_run_all.sas`, `g` is already open from Phase 4. When running standalone, the program must open `g` itself.

Pattern (copy from 07_cohort.sas): `libname g "&g_path";` near the top, before any dictionary query.

### Pitfall 3: `dictionary.columns` column names are uppercase

The `libname` and `memname` columns from `dictionary.columns` are returned in uppercase regardless of how the library was assigned. Always filter with `upcase()` or use uppercase literals.

### Pitfall 4: ODS EXCEL FILE= path -- backslash macro variable

Paths like `"&docs_path.\DATA_DICTIONARY.xlsx"` are correct. The period terminates the macro variable reference; the backslash is literal. Do NOT "fix" this to `"&docs_path\..."` -- without the period, `docs_path\DATA_DICTIONARY` becomes the macro variable name and resolves to blank.

### Pitfall 5: PROC MEANS cannot process character variables at all

Not "NMISS behaves differently for character" -- PROC MEANS REJECTS them. `var _character_;`
errors with "Variable X in list does not match type prescribed for this list", so any plan
built on a `_NUMERIC_` pass plus a `_CHARACTER_` pass silently documents only half the
variables (or fails outright, depending on where the error lands).

An earlier draft of this document asserted both that MEANS NMISS counts blanks as missing
AND that it counts them as non-missing, in two places, which is the tell that neither
statement was checked.

**Use `PROC SQL COUNT(var)` for both types.** It counts non-missing values, and SAS treats an
all-blank character string as missing, so one expression is correct for the whole dictionary.

### Pitfall 6: `%abort cancel` return-code behavior on Windows batch

From SAS 9.4 documentation and project STATE.md: `%abort cancel` leaves an interactive session swallowing the next submit. In batch mode (`sas -sysin`), `%abort cancel` terminates the SAS process. The return code emitted to the Windows OS is system-dependent; SAS documentation states it may be 1 or a platform-specific value.

**How to settle it:** Run `sas -sysin test_abort.sas` where `test_abort.sas` contains only `%abort cancel;`, then check `%ERRORLEVEL%` in the calling CMD shell. This is a one-time manual test, not a SAS program artifact.

The result must be documented in DECISIONS.md as a new entry (PCM-D-12 or similar) so schedulers know what return code to watch.

**Current state:** Not yet settled. Phase 8 must include a task to run this test and record the result.

### Pitfall 7: PCM-D-05 is a stakeholder decision, not a Phase 7 formality

DOC-02 requires PCM-D-05 resolved, and an earlier draft treated this as "Phase 7 Plan 02
writes the entry, Phase 8 verifies it". That is no longer true.

**PCM-F-19 voided D-05's original rationale.** The justification for restricting the cohort to
INPATIENT/OBSERVATION was PCM-F-12: only admitted patients had the geriatric assessments, so
ambulatory patients were never eligible. After MRG-06 filled md3's blanks from md8, 13,288 of
20,540 cognitive scores and 15,161 of 23,311 frailty scores belong to patients OUTSIDE the
admitted cohort. Within the cohort those two are now the WEAKER variables (52.2% and 58.7%).
`Admit_BMI` is what actually forces the restriction -- all 12,726 of its values sit inside the
admitted cohort, zero outside.

So D-05 needs a real conversation with Erin about what the cohort is for, and Phase 8's DOC-02
now **blocks on a stakeholder decision, not a program run**. Plan accordingly: either treat
DOC-02 as satisfiable with D-05 explicitly marked "open, awaiting Erin" and attributed as
such, or accept that Phase 8 cannot close until that conversation happens.

### Pitfall 8: `99_run_all.sas` header still says "seven phases"

The program header comment currently says "Submits all seven phases." After adding Phase 8, update the comment and the "Expected final output" section. Also add `docs/DATA_DICTIONARY.xlsx` to the expected outputs block.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Column metadata | Custom PROC CONTENTS parser | `dictionary.columns` PROC SQL |
| Excel output | DATA step file output | ODS EXCEL (SAS 9.4M3+, available) |
| Coverage counts | Manual loop macros | PROC MEANS N/NMISS + ODS OUTPUT |
| Ownership lookup | Re-derive from source files | JOIN to `qclib.ownership_map` (already built) |

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SAS assertions via %abort cancel macros (project standard) |
| Config | No separate config; assertions embedded in 08_dictionary.sas |
| Quick run command | Run `08_dictionary.sas` standalone in SAS Display Manager |
| Full suite command | Run `99_run_all.sas` (all 8 phases) |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Assertion |
|--------|----------|-----------|-----------|
| DOC-01 | DATA_DICTIONARY.xlsx exists with expected variables | automated (abort if count mismatch) | PROC CONTENTS count on g.master_data_merged == variable rows in dictionary |
| DOC-01 | No variable missing source or type | automated | PROC SQL count of rows where source IS MISSING or type IS MISSING == 0; abort if > 0 |
| DOC-02 | All decisions D-01 through D-07 resolved | manual verify | Read docs/DECISIONS.md and confirm no "Pending" beside D-01 through D-07 |
| DOC-03 | 99_run_all.sas runs clean | manual verify | Human runs from clean SAS session; no aborts; DATA_DICTIONARY.xlsx written |
| DOC-04 | Git history has phase commits | manual verify | `git log --oneline` shows one commit per phase |

### Wave 0 Gaps

- [ ] `sas/08_dictionary.sas` -- does not exist yet
- [ ] `qclib.ownership_map` schema inspection -- confirm exact column names before writing JOIN
- [ ] `%abort cancel` return-code test -- one-time batch test, document result in DECISIONS.md

---

## State of the Art

| Old Approach | Current Approach | Impact |
|---|---|---|
| ODS TAGSETS.EXCELXP (XML-based, deprecated) | ODS EXCEL (native xlsx, SAS 9.4M3+) | Use ODS EXCEL only; TAGSETS.EXCELXP produces xml-disguised-as-xlsx, not real xlsx |
| PROC CONTENTS + manual XLSX | ODS EXCEL with PROC REPORT | Single-pass; supports styles for UF colors |

---

## Open Questions

1. **`qclib.ownership_map` exact column names**
   - What we know: the table exists at `P:/.../merge/qclib/ownership_map.sas7bdat`, written by Phase 2
   - What's unclear: exact column names (varname? variable? source? owner? source_num?)
   - Recommendation: planner includes a Wave 0 task to run `PROC CONTENTS data=qclib.ownership_map;` and record the schema before writing the join in `08_dictionary.sas`

2. **`%abort cancel` return code**
   - What we know: `%abort cancel` terminates batch SAS on Windows; return code is platform-specific
   - What's unclear: is it 1, or something else on this specific machine/SAS version?
   - Recommendation: Wave 0 task -- run a one-line test script, echo %ERRORLEVEL%, document in DECISIONS.md as PCM-D-12

3. **Whether DATA_DICTIONARY.xlsx should have a second sheet for derivation legend**
   - CLAUDE.md says KEY sheet leftmost; that implies two sheets minimum
   - Recommendation: KEY sheet documents the column headers and code meanings; Dictionary sheet holds the rows. Planner should decide this before drafting the ODS EXCEL section.

4. **Coverage % definition for character vs numeric**
   - Non-missing numeric: PROC MEANS N
   - Non-blank character: PROC SQL COUNT(var) -- needs confirmation that blank = missing for project purposes
   - Recommendation: planner adopts COUNT(var) for both types via PROC SQL; document in 08_dictionary.sas header

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| ODS EXCEL destination | DOC-01 xlsx output | Yes (SAS 9.4M3+) | SAS 9.4M8 | None needed |
| `qclib.ownership_map` | Derivation join | Yes (written Phase 2) | -- | None; re-run Phase 2 if missing |
| `g.master_data_merged` | Coverage stats | Yes (written Phase 4) | -- | None; re-run Phase 4 if missing |
| `docs/data_dictionary_notes.txt` | Derivation narrative | Yes | Phase 6 stub | -- |
| `docs/` directory on C: | xlsx output location | Yes | -- | -- |

---

## Sources

### Primary (HIGH confidence)
- Direct inspection of `sas/99_run_all.sas` -- existing pipeline structure and %in_pipeline pattern
- Direct inspection of `sas/00_config.sas` -- path macros and docs_path location
- Direct inspection of `sas/06_reconcile.sas`, `sas/07_cohort.sas` -- established program shell pattern
- Direct inspection of `docs/DECISIONS.md` -- current resolution state of all D-01 through D-11
- Direct inspection of `docs/data_dictionary_notes.txt` -- derivation categories and special-case variables
- `.planning/REQUIREMENTS.md` -- DOC-01 through DOC-04 requirement text
- `.planning/STATE.md` -- project state and established decisions

### Secondary (MEDIUM confidence)
- SAS 9.4 `dictionary.columns` behavior: standard, stable across SAS 9.x; no external verification performed
- ODS EXCEL availability in SAS 9.4M3+: stated in SAS documentation; 9.4M8 is later than M3 so it is present
- `%abort cancel` Windows batch behavior: documented in STATE.md and ROADMAP.md by the project; exact return code not yet measured

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- ODS EXCEL + dictionary.columns is the canonical SAS 9.4 approach
- Architecture: HIGH -- derived from existing pipeline code inspection
- Pitfalls: HIGH -- most are drawn from explicit project decisions and past session incidents documented in STATE.md

**Research date:** 2026-08-27
**Valid until:** End of project (stable SAS 9.4M8 environment)
