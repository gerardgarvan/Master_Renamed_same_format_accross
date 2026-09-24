# Phase 14: Label-Similarity Sweep - Research

**Researched:** 2026-08-29
**Domain:** SAS 9.4M8 string-similarity computation, variable label extraction, concept profiling extension
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HARM-02 | Canonical names sourced from `docs/precede_dictionary.csv`, read programmatically. `VARIABLE_RECTIFICATION.xlsx` is NOT a crosswalk | CSV already has `dict_name`, `description`, and `sas_name` columns; PROC IMPORT pattern established in existing programs |
| HARM-03 | Label-similarity sweep over all variable labels in `g.master_data_harmonized`; measure and threshold stated; candidate pairs written to committed artifact for human review | SAS has `COMPGED` and `SPEDIS` for edit-distance; no external library needed; pattern follows 10_concept_profile.sas |
| HARM-09 | SSDI death family (`SSDI_DEATH_DATE_Y_N`, `SSDI_DEATH_Y_N`, `SSDI_DEATH`) and `CPT1_CLASS`/`CPT1_LABEL` pair added to the concept list and profiled | Both variable families are already in `g.master_data_harmonized`; profiling follows exact `10_concept_profile.sas` machinery |
</phase_requirements>

---

## Summary

Phase 14 closes the structural gap that all previous variable-matching work could not address: two variables that measure the same clinical concept but whose column names share no characters are invisible to name-based matching. The only way to find them is to compare what the columns say about themselves -- their SAS variable labels -- using a string-similarity measure.

The existing pipeline already handles concept-based alias detection (`10_concept_profile.sas`) and human-confirmed harmonization (`10b_concept_harmonize.sas`). Phase 14 adds a NEW upstream step: extract all labels from `g.master_data_harmonized`, compute all pairwise label similarities, and surface the pairs above a threshold for a human to judge. It does NOT harmonize anything -- that is Phase 15's job. It also extends the concept profiler to cover two concept groups that `10_concept_profile.sas` never received: the SSDI death family and the CPT1 code/label pair.

The key design principle is already established in this pipeline: a program proposes, a human confirms, the next program applies exactly what is confirmed and fails on any unmapped value. Phase 14 is the "propose" step for label-similar pairs. The "apply" step is Phase 15, which reuses the `10b` machinery.

**Primary recommendation:** Implement `14_label_similarity.sas` in two sections -- (A) the label sweep over `g.master_data_harmonized` producing a candidate CSV, and (B) the concept profiler extension adding SSDI and CPT1 groups to `10_concept_profile.sas`-style evidence. The sweep uses `COMPGED` (generalized edit distance) with a stated threshold, consistent with how SAS handles fuzzy matching natively without external libraries.

---

## Project Constraints (from CLAUDE.md)

- SAS 9.4M8 on Windows; session encoding is not UTF-8
- Read-only on `master_data_1..8.sas7bdat` and everything under `raw\master`
- No PHI in git: `.gitignore` excludes `*.sas7bdat`, `*.xlsx`, `*.csv`, `data/` tree
- `g` libname for output datasets; `qclib` libname for QC artifacts
- UF colors (#0021A5, #FA4616) on visual deliverables; KEY sheet leftmost in workbooks
- All pipeline paths on P: -- `g_path`, `logs_path`, `qc_path` (not version-controlled)
- SAS programs in `sas/` (version-controlled, local disk C:)
- Restart SAS session between programs (`%abort cancel` leaves interactive session)
- No PROC SQL UPDATE, no `data X; set X;` patterns
- No `&SQLOBS` -- use explicit `SELECT COUNT(*) INTO :macvar TRIMMED`
- `%LENGTH` check before any macro variable used in a condition
- `IS NOT MISSING` only in PROC SQL; DATA step uses `NOT MISSING(x)`
- `dictionary.columns.TYPE` is `char`/`num`, not the numeric 1/2 of PROC CONTENTS
- LENGTH before SET -- PROC IMPORT must never decide types
- No bare open-code `%IF` (needs `%DO` block); every `%abort cancel` inside a named macro
- No apostrophes or embedded semicolons in `%PUT` text
- No `%GLOBAL` omission -- anything read outside its setting macro must be declared global
- FIRSTOBS=/OBS= for indexed reads; never POINT=
- No PROC inside an open DATA step (terminates the DATA step)
- `g.master_data_harmonized` never on the left of a DATA statement
- Data values never round-tripped through a macro variable into generated code

---

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| SAS 9.4M8 | 9.4M8 | All computation | Project constraint; no external tools |
| `COMPGED` function | Base SAS | Generalized edit distance between two strings | Native, no add-ons; used for fuzzy label matching |
| `SPEDIS` function | Base SAS | Spelling distance (asymmetric edit distance) | Alternative measure; useful for substring containment |
| `PROC IMPORT` with `guessingrows=max` | Base SAS | Read `precede_dictionary.csv` | Established pattern in 10b, 11 programs |
| `dictionary.columns` | Base SAS | Extract variable labels from a SAS dataset | Only way to get labels without reading the data |
| ODS EXCEL | Base SAS | Write multi-sheet evidence workbooks | Established pattern; UF colors applied via ODS |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `PROC PRINTTO` | Base SAS | Route log to file | Used by every program when `in_pipeline=0` |
| `%include "00_config.sas"` | n/a | Load path macros | First action in every pipeline program |
| `call symputx` | Base SAS | Pass metadata to macro variables | Rule extraction before DATA step opens |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `COMPGED` | `SOUNDEX`, `COMPLEV` | `COMPGED` is more general; `COMPLEV` gives raw Levenshtein count without normalization; `SOUNDEX` is phonetic only and misses abbreviation variants |
| Manual threshold tuning | Fixed 0.3 | A stated, documented threshold is the requirement (HARM-03); the value should be chosen to surface ~20-50 pairs for human review |

---

## Architecture Patterns

### Recommended Program Structure

Phase 14 is ONE program: `sas/14_label_similarity.sas`

It has two independent sections that can be read and planned separately but run in a single program:

**Section A -- Label sweep (HARM-02, HARM-03)**
1. Preconditions (dirs, `g.master_data_harmonized` exists and has rows)
2. Read `precede_dictionary.csv` -- extract `dict_name`, `description`, `sas_name` columns
3. Extract labels from `dictionary.columns` for `g.master_data_harmonized`
4. Join labels to the PRECEDE dictionary by variable name (exact match first)
5. For each variable, determine the "best label" -- prefer the PRECEDE dictionary description; fall back to the SAS label; fall back to the variable name itself
6. Compute all pairwise label similarities using `COMPGED`
7. Filter to pairs above threshold; exclude trivially self-similar pairs and already-confirmed-concept pairs from `10_concept_profile.sas` and earlier harmonization
8. Write candidate pairs to `docs/label_similarity_candidates.csv` (two columns side by side: varname_a, label_a, varname_b, label_b, similarity_score)
9. Write evidence workbook `docs/LABEL_SIMILARITY_EVIDENCE.xlsx` with KEY sheet, full pair table, and filtered candidates
10. Write QC artifact to `qc/14_label_similarity.txt`

**Section B -- Concept profiler extension (HARM-09)**
11. Add SSDI death family and CPT1 groups to a concept table (same structure as `work.concepts` in `10_concept_profile.sas`)
12. Check that all named columns exist in `g.master_data_harmonized`
13. Run value inventory and pairwise cross-tabulation for the new groups (exact same logic as `10_concept_profile.sas` Sections 2-3)
14. Append new rows to the existing `docs/concept_decisions_TEMPLATE.csv` -- or write a separate `docs/concept_decisions_SSDI_CPT1_TEMPLATE.csv` so the existing Phase 10 decisions are not disturbed
15. Append new evidence to `docs/CONCEPT_EVIDENCE.xlsx` (add new sheets, do not overwrite existing)

### Recommended Project Structure
```
sas/
  14_label_similarity.sas   -- new; this phase's sole program
docs/
  label_similarity_candidates.csv   -- new committed artifact; human review input
  LABEL_SIMILARITY_EVIDENCE.xlsx    -- new workbook
  concept_decisions_TEMPLATE.csv    -- extended with SSDI/CPT1 rows (or separate file)
  CONCEPT_EVIDENCE.xlsx             -- existing; append SSDI/CPT1 sheets
qc/
  14_label_similarity.txt   -- new QC artifact (on P:, not committed)
logs/
  14_label_similarity.log   -- new log file (on P:, not committed)
```

### Pattern 1: Label Extraction via `dictionary.columns`

SAS stores variable labels in `dictionary.columns.label`. This is the only way to get all labels without reading the data itself.

```sas
/* Source: SAS 9.4 dictionary.columns reference */
proc sql noprint;
  create table work.labels as
  select upcase(name) as varname length=32,
         strip(label)            as var_label length=256,
         type, length, varnum
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_HARMONIZED'
    and upcase(name) not in ('PRECEDE_STUDY_ID')
  order by varnum;
  select count(*) into :n_vars trimmed from work.labels;
quit;
```

**Critical note:** Many variables in this dataset have NO label (label is blank). For those, the variable name itself is the only descriptor. The "best label" logic must handle this -- blank label falls back to `varname`.

### Pattern 2: COMPLEV for Label Similarity -- NOT COMPGED

**CORRECTED 2026-08-29. Earlier text in this document recommending COMPGED with a
`1 - compged/(2*maxlen)` normalisation is SUPERSEDED. Do not implement it.**

COMPGED returns a WEIGHTED generalised edit cost. Its default operation costs are
on the order of 100 per insert, delete or replace -- not 1. Two 20-character
labels differing in five characters score about 500, so the proposed
normalisation gives `1 - 500/40 = -11.5`. Every score would be large and
negative, nothing would clear a positive threshold, and the sweep would report
ZERO candidates. That reads as "no similar labels exist" rather than "the
arithmetic is wrong", which is the silent-failure shape this pipeline has hit
repeatedly.

This document also gave the signature `COMPGED(s1, s2, ins, del, sub)`. That is
wrong: COMPGED takes an optional cost-table argument, not three separate cost
parameters.

**Use COMPLEV.** It returns a plain Levenshtein distance in CHARACTERS, so it
normalises predictably with no knowledge of a cost table:

```sas
case
  when max(lengthn(strip(a.label)), lengthn(strip(b.label))) = 0 then .
  else 1 - complev(upcase(strip(a.label)), upcase(strip(b.label)))
           / max(lengthn(strip(a.label)), lengthn(strip(b.label)))
end as score_edit
```

LENGTHN, not LENGTH -- LENGTH returns 1 for a blank string, which makes the
divisor wrong for an empty label.

**Jaccard is REQUIRED, not optional.** Pitfall 1 below is correct that character
distance misses semantically equivalent labels: "patient died" and "death
occurred" mean the same thing and share almost no characters. Edit distance alone
cannot find that class, and that class is the reason this phase exists. Compute
both scores, write both, and let a pair qualify on EITHER.

**Calibrate before trusting any threshold.** Score `Death_Date_Y_N` against
`IsDead_Y_N` -- Phase 10 proved them identical on all 8,730 overlapping rows. If
that pair does not clear threshold, the threshold is wrong, not the data. Record
the observed score in the QC artifact so the calibration is visible.

### Pattern 3: Pairwise Comparison Without a PROC Inside a DATA Step

The pairwise comparison must be done in DATA step or PROC SQL without invoking a PROC from inside a DATA step (PCM compliance). The established approach is to load all metadata before any DATA step opens.

```sas
/* Extract all (varname, label) pairs into indexed macro vars before DATA step */
proc sql noprint;
  select count(*) into :n_vars trimmed from work.labels;
  select upcase(varname) into :vn1-:vn&n_vars from work.labels;
  select var_label       into :vl1-:vl&n_vars from work.labels;
quit;

/* Then compute all O(n^2) pairs in a DATA step with DO loops */
/* For 187 variables: 187*186/2 = 17,391 pairs -- acceptable */
data work.pair_scores;
  length varname_a $32 varname_b $32 label_a $256 label_b $256 similarity 8;
  do i = 1 to &n_vars;
    do j = i+1 to &n_vars;
      varname_a  = symget(cats('vn', i));
      varname_b  = symget(cats('vn', j));
      label_a    = symget(cats('vl', i));
      label_b    = symget(cats('vl', j));
      /* Use upcase labels for case-insensitive comparison */
      la = upcase(strip(label_a));
      lb = upcase(strip(label_b));
      /* Handle blank labels: use variable name as fallback */
      if missing(la) then la = upcase(varname_a);
      if missing(lb) then lb = upcase(varname_b);
      max_d = 2 * max(length(la), length(lb));
      if max_d > 0 then similarity = 1 - compged(la, lb) / max_d;
      else similarity = .;
      if similarity >= &threshold then output;
    end;
  end;
  drop i j la lb max_d;
run;
```

**Note:** `symget()` is the DATA-step equivalent of resolving a macro variable. Indexed macro variables `:vn1-:vn187` are populated by the SQL step above. This avoids PROC SQL inside the DATA step.

**Alternative for large N:** If the label list exceeds the macro variable index limit (unlikely at 187 variables), use `PROC SQL` with a self-join instead:

```sas
/* Source: SAS 9.4 PROC SQL documentation */
proc sql;
  create table work.pair_scores as
  select a.varname as varname_a, a.var_label as label_a,
         b.varname as varname_b, b.var_label as label_b,
         1 - compged(upcase(strip(a.var_label)), upcase(strip(b.var_label))) /
             (2 * max(length(strip(a.var_label)), length(strip(b.var_label)))) as similarity
  from work.labels as a, work.labels as b
  where a.varname < b.varname
    and calculated similarity >= &threshold;
quit;
```

The PROC SQL self-join is cleaner and avoids the indexed-macro-variable approach entirely. Given PROC SQL is already used throughout this pipeline, prefer the self-join form.

### Pattern 4: Reading `precede_dictionary.csv` for Canonical Names (HARM-02)

```sas
/* Pattern established in 11_dictionary_reconcile.sas */
proc import datafile="&docs_path.\precede_dictionary.csv"
    out=work.prec_raw dbms=csv replace;
  guessingrows=max;
run;

data work.prec_dict;
  length sheet $40 dict_name $100 dict_type $30 description $500
         source $200 note $200 sas_name $32;
  set work.prec_raw (rename=(sheet=_sh dict_name=_dn dict_type=_dt
                              description=_desc source=_src note=_nt sas_name=_sn));
  sheet       = strip(cats(_sh));
  dict_name   = strip(cats(_dn));
  dict_type   = strip(cats(_dt));
  description = strip(cats(_desc));
  sas_name    = upcase(strip(cats(_sn)));
  keep sheet dict_name dict_type description sas_name;
run;
```

The `description` column is the label-equivalent from the authoritative dictionary. `sas_name` is the canonical SAS variable name. This table gives the "best available label" for variables that are in the dictionary.

### Pattern 5: HARM-09 -- Adding SSDI and CPT1 Concept Groups

The SSDI death family follows the same three-variant shape already profiled (DEATH_FLAG concept). Add these rows to the concept table:

```sas
/* New concept groups for Section B */
data work.new_concepts;
  length concept $32 varname $32 note $80;
  infile datalines dsd dlm='|' truncover;
  input concept $ varname $ note $;
  datalines;
SSDI_DEATH_FLAG|SSDI_DEATH_DATE_Y_N|SSDI variant -- date Y/N form
SSDI_DEATH_FLAG|SSDI_DEATH_Y_N|SSDI variant -- Y/N form
SSDI_DEATH_FLAG|SSDI_DEATH|SSDI variant -- plain form
CPT1_CODE_LABEL|CPT1_CLASS|CPT code classification (159 distinct)
CPT1_CODE_LABEL|CPT1_LABEL|CPT code label (159 distinct)
;
run;
```

Note: `CPT1_CLASS` and `CPT1_LABEL` have 159 distinct values each. The cardinality guard in `10_concept_profile.sas` was set to 50 and was raised to 200 in `13_value_profile_long.sas`. For the concept profiler in Phase 14, the guard must be set to at least 200 to allow CPT1 profiling. This is a stated requirement (HARM-09) so the guard must be relaxed with documentation.

### Anti-Patterns to Avoid

- **Normalizing COMPGED without checking for zero-length strings:** `COMPGED('', '')` returns 0, and dividing by `max_dist = 0` causes a division-by-zero. Always check `max_dist > 0`.
- **Using COMPGED on raw labels without UPCASE/STRIP:** Case differences inflate the distance for pairs that are semantically identical. Always `upcase(strip(...))`.
- **Placing a threshold assertion in the program:** The threshold is a human parameter, not a correctness criterion. The program must STATE the threshold and write all pairs above it, not assert that N pairs is the right number.
- **Overwriting `docs/CONCEPT_EVIDENCE.xlsx` entirely:** The existing workbook documents decisions already confirmed. Append new sheets; do not replace the file with an empty workbook that only contains SSDI/CPT1 evidence.
- **Trusting the cardinality guard to protect CPT1:** CPT1 has 159 distinct values, which is below the raised ceiling of 200 (from Phase 13). The profiler must explicitly accommodate 159-distinct-value columns, which means the cross-tab will be large. Cap the cross-tab output at a stated row limit rather than producing a 159x159 matrix.
- **Using `VARIABLE_RECTIFICATION.xlsx` as a name crosswalk:** The requirements state explicitly this file is a register of open questions only (HARM-02). The canonical name source is `docs/precede_dictionary.csv`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Edit distance between strings | Custom character-by-character comparison | `COMPGED` or `COMPLEV` | SAS Base provides these; custom code will have bugs in edge cases (empty strings, multi-byte chars) |
| Label extraction from SAS dataset | PROC CONTENTS + parsing | `dictionary.columns.label` | Direct, accurate, single query |
| CSV write | Custom DATA step PUT | PROC EXPORT | Consistent quoting, encoding handling |
| Multisheet Excel output | Multiple ODS calls with manual file management | ODS EXCEL with `sheet_name=` option | Already established in this pipeline |

---

## Common Pitfalls

### Pitfall 1: COMPGED Finds Character Similarity, Not Semantic Similarity
**What goes wrong:** Two labels like "Death Date Yes/No" (label for `Death_Date_Y_N`) and "Is Dead Yes/No" (label for `IsDead_Y_N`) share the substring "Yes/No" but the COMPGED score will be driven by the total edit distance, which is large. The same-concept pairs this sweep is designed to find may NOT score above a naive threshold.

**Why it happens:** COMPGED measures character-level edit distance. Same-concept variables in clinical data often have semantically equivalent but textually distinct labels. The edit distance between "patient died" and "death occurred" is high despite identical meaning.

**How to avoid:** Use two complementary approaches: (1) COMPGED with a LOW threshold (e.g., 0.3 or even lower) to cast a wide net, and (2) word-overlap: tokenize each label into words, compute the Jaccard similarity (shared words / union of words), and report pairs with high Jaccard. Implement both; write both scores to the candidate table. The human reviews both columns.

**Warning signs:** If zero or very few pairs are above a 0.5 threshold, the threshold is too high rather than the dataset having no similar pairs.

### Pitfall 2: Blank Labels Are the Norm, Not the Exception
**What goes wrong:** Many variables in the merged/harmonized file have no SAS label. Comparing blank to blank gives `similarity = 1.0` (or undefined), flooding the results with trivial matches.

**Why it happens:** SAS variable labels are optional. The source extracts were not created with systematic labeling.

**How to avoid:** Before computing similarity, assign a "working label" for each variable: use the PRECEDE dictionary description if the variable appears there (join on `sas_name`); use the SAS label if non-blank; use the variable name as last resort. Exclude pairs where BOTH working labels are the variable name (they are distinguishable by name, not label, and are not the target of this sweep). Log how many variables fell back to each level.

### Pitfall 3: Already-Known Pairs Pollute the Candidate List
**What goes wrong:** Pairs that `10_concept_profile.sas` already handles (e.g., `Death_Date_Y_N` / `IsDead_Y_N`) will appear in the sweep results, confusing the human reviewer into thinking they need to decide something already decided.

**Why it happens:** The label sweep has no knowledge of what the concept profiler already covers.

**How to avoid:** Build an exclusion table of all variable pairs already in `work.concepts` from Phase 10. Filter the label-similarity candidates against this exclusion list before writing the output. Document the exclusion count in the QC artifact.

### Pitfall 4: PROC SQL Self-Join at O(n^2) Pairs
**What goes wrong:** With 187 variables, the self-join produces 17,391 rows -- fine. But if the threshold is very low and most pairs qualify, the output table can be large.

**Why it happens:** No WHERE clause on the similarity BEFORE COMPGED is computed means every pair is computed. COMPGED is not trivially vectorizable by SQL.

**How to avoid:** The cardinality is small enough (187 variables) that computing all 17,391 pairs is fast. Do not attempt to pre-filter by label length or other heuristics -- just compute all pairs and filter by threshold after. A 17,391-row intermediate table is negligible in memory.

### Pitfall 5: CPT1 Cross-Tab Is 159 x 159
**What goes wrong:** Running the same pairwise cross-tabulation logic as Phase 10 on `CPT1_CLASS` x `CPT1_LABEL` produces a table with up to 159 * 159 = 25,281 rows. This is displayable but creates a very large Excel sheet.

**Why it happens:** CPT1 is a classification column, not a binary flag. The cross-tab was designed for Y/N columns.

**How to avoid:** For the `CPT1_CODE_LABEL` group, report value inventory and n_both/n_a_only/n_b_only/n_neither (the pair summary), but cap the detailed cross-tab at the top 200 rows by `n_rows` descending. Add a note on the sheet stating the cap. For SSDI columns, which are binary flags, the full cross-tab is small and should be shown in full.

### Pitfall 6: Writing to `docs/CONCEPT_EVIDENCE.xlsx` Without Checking for an Open File
**What goes wrong:** If the file is open in Excel, the ODS delete step fails and the program aborts with an unhelpful error.

**Why it happens:** The `%drop_stale` macro in `10_concept_profile.sas` uses `fdelete` and checks the return code -- but only the new SSDI/CPT1 sheets need to be added, not the whole workbook rebuilt.

**How to avoid:** For Phase 14, append to `CONCEPT_EVIDENCE.xlsx` using ODS EXCEL with `action=update` if available, or write a SEPARATE file `CONCEPT_EVIDENCE_EXT.xlsx` for the new groups. The separate file is simpler and avoids the existing file at all. Document the split in the KEY sheet of each workbook.

---

## Code Examples

### Full Label Extraction and COMPGED Pairwise Sweep

```sas
/* Source: SAS 9.4 dictionary.columns, COMPGED documentation */
/* SECTION A -- Extract labels */
proc sql noprint;
  create table work.labels as
  select upcase(name) as varname length=32,
         strip(label)            as var_label length=256
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_HARMONIZED'
    and upcase(name) not in ('PRECEDE_STUDY_ID')
  order by varnum;
  select count(*) into :n_vars trimmed from work.labels;
quit;

/* Join to PRECEDE dictionary for best label */
proc sql noprint;
  create table work.best_labels as
  select l.varname,
         case
           when not missing(d.description) then strip(d.description)
           when not missing(l.var_label)   then strip(l.var_label)
           else l.varname
         end as working_label length=256,
         case
           when not missing(d.description) then 'DICTIONARY'
           when not missing(l.var_label)   then 'SAS_LABEL'
           else 'VARNAME'
         end as label_source length=12
  from work.labels as l
  left join work.prec_dict as d
    on l.varname = d.sas_name;
quit;

/* Pairwise COMPGED -- self-join, both scores */
%let threshold = 0.30;

proc sql;
  create table work.pair_candidates as
  select a.varname as varname_a, a.working_label as label_a,
         b.varname as varname_b, b.working_label as label_b,
         a.label_source as source_a, b.label_source as source_b,
         /* Score 1: normalized COMPGED (character edit distance) */
         1 - compged(upcase(strip(a.working_label)),
                     upcase(strip(b.working_label))) /
             (2 * max(length(strip(a.working_label)),
                      length(strip(b.working_label)))) as score_edit,
         /* Score 2: word Jaccard -- implemented separately in DATA step */
         . as score_jaccard
  from work.best_labels as a, work.best_labels as b
  where a.varname < b.varname
    /* Skip pairs where both fall back to varname -- name-matching already covers them */
    and not (a.label_source='VARNAME' and b.label_source='VARNAME')
    and calculated score_edit >= &threshold
  order by score_edit desc;
quit;
```

### Excluding Known Concept Pairs

```sas
/* Build exclusion list from Phase 10 concept groups -- concepts already decided */
data work.known_pairs;
  length varname_a $32 varname_b $32;
  /* All pairs within each concept group from 10_concept_profile.sas */
  /* ... same datalines as work.concepts in 10_concept_profile.sas ... */
  /* Cross with itself to get all pairs, or hardcode from the concept table */
run;

/* Filter candidates */
proc sql;
  create table work.new_candidates as
  select c.*
  from work.pair_candidates as c
  where not exists
    (select 1 from work.known_pairs as k
     where (k.varname_a = c.varname_a and k.varname_b = c.varname_b)
        or (k.varname_a = c.varname_b and k.varname_b = c.varname_a));
quit;
```

### QC Artifact Pattern (consistent with all existing programs)

```sas
data _null_;
  file "&qc_path.\14_label_similarity.txt";
  put "14_label_similarity -- Run: %sysfunc(datetime(), datetime20.)";
  put "=======================================================================";
  put " ";
  put "harmonized_vars=&n_vars";
  put "vars_with_dict_label=&n_dict_label";
  put "vars_with_sas_label=&n_sas_label";
  put "vars_using_varname=&n_varname_fallback";
  put "pairs_computed=&n_pairs_total";
  put "threshold=&threshold";
  put "pairs_above_threshold=&n_above";
  put "known_concept_pairs_excluded=&n_excluded";
  put "candidate_pairs_written=&n_candidates";
  put " ";
  put "SSDI death family -- all three columns present: &ssdi_present";
  put "CPT1 pair -- both columns present: &cpt1_present";
  put " ";
  put "This program proposes. A human confirms.";
  put "Complete docs/label_similarity_candidates.csv -- mark CONFIRMED=YES for each";
  put "pair a human judges as same-concept. Then add confirmed pairs to";
  put "docs/concept_decisions.csv and run 10b_concept_harmonize.sas (Phase 15).";
run;
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|-----------------|--------------|--------|
| Name-based alias detection only | Name-based + label-similarity | Phase 14 (new) | Finds aliases invisible to name matching |
| Cardinality guard at 50 | Raised to 200 | Phase 13 | CPT1 (159 distinct) now profileable |
| Static concept list in 10_concept_profile.sas | Extended with SSDI/CPT1 in Phase 14 | Phase 14 (new) | HARM-09 requirement |

**Existing programs already running (context for what Phase 14 reads):**
- `09_summary_stats.sas`: Every variable in `g.master_data_harmonized` summarized -- coverage, distinct count, distribution
- `10_concept_profile.sas`: 18 concept groups profiled; decision template written
- `10b_concept_harmonize.sas`: 11 `h_` columns created; 11 aliases dropped after proof
- `11_dictionary_reconcile.sas`: Fuzzy name matching against `precede_dictionary.csv`; rename map proposed but not applied
- `12_column_redundancy.sas`: Pairwise column equality sweep; nothing dropped
- `13_value_profile_long.sas`: Stacked value profile across merged/harmonized/cohort datasets

---

## Open Questions

1. **What is the right similarity threshold?**
   - What we know: A threshold of 0.3 (normalized COMPGED) will surface pairs that share roughly 30% of character operations. This is a wide net.
   - What is unclear: Whether same-concept labels in this specific dataset are textually similar enough to be above any reasonable threshold. Labels like "Death Date Yes/No" vs "SSDI Death Date Yes/No" will score well; "Is Dead" vs "Death" will not.
   - Recommendation: Run the sweep at threshold=0.20 on first pass to see the raw distribution of similarity scores; document the chosen threshold with the count of pairs it produces. The threshold is a parameter, not a hardcoded constant -- store it in a `%let threshold = 0.20;` at the top of the program, clearly labeled.

2. **Which variables actually have labels in `g.master_data_harmonized`?**
   - What we know: SAS labels are optional; the source extracts may not have set them uniformly.
   - What is unclear: What fraction of the 187 columns have non-blank labels vs. fall back to variable name.
   - Recommendation: The precondition section of Phase 14 should count and log the three label-source tiers (DICTIONARY / SAS_LABEL / VARNAME) so the planner knows how informative the sweep can actually be. If more than 80% of variables fall back to VARNAME, the label sweep will mostly compare variable names -- which Phase 11 already did. That would be worth noting in the QC artifact.

3. **Should the SSDI/CPT1 concept evidence go into the existing `CONCEPT_EVIDENCE.xlsx` or a new file?**
   - What we know: Writing to an open Excel file fails hard. The existing file documents confirmed decisions from Phase 10.
   - What is unclear: Whether Phase 15 needs to read from a single decision file or can handle two.
   - Recommendation: Write a new `CONCEPT_EVIDENCE_EXT.xlsx` for the SSDI/CPT1 groups. The template CSV can extend `concept_decisions_TEMPLATE.csv` by appending rows (PROC EXPORT REPLACE would overwrite; use a DATA step append and PROC EXPORT). Alternatively, write `concept_decisions_EXT_TEMPLATE.csv` and note that Phase 15 must merge the two before running `10b`. The planner should decide which approach based on Phase 15's design.

---

## Environment Availability

All dependencies are native SAS 9.4M8 on Windows. No external tools required.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SAS `COMPGED` function | Label similarity | Yes | Base SAS 9.4 | `COMPLEV` (raw count, needs normalization) |
| `dictionary.columns.label` | Label extraction | Yes | Base SAS | None needed |
| `docs/precede_dictionary.csv` | HARM-02 canonical names | Yes (confirmed in docs/) | Current | None -- required by HARM-02 |
| `g.master_data_harmonized` | All of Section A and B | Yes (confirmed by project state) | 187 cols, 41,150 rows | Run Phase 10b first |
| ODS EXCEL | Evidence workbook output | Yes | SAS 9.4 | ODS CSV (no formatting) |
| `qc/` directory on P: | QC artifact | Yes | n/a | None -- required |

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | SAS `%abort cancel` macro assertions embedded in program |
| Config file | None (assertion macros inline in each program) |
| Quick run command | Submit `14_label_similarity.sas` in SAS 9.4; check log for ERROR/WARNING |
| Full suite command | Submit `99_run_all.sas` in clean SAS session |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| HARM-02 | `precede_dictionary.csv` read programmatically; names sourced from `sas_name` column | Unit (assertion in program) | Submit program; log must have 0 ERRORs | Gate: n_dict_rows > 0 |
| HARM-03 | All pairs computed; threshold stated as macro var; candidate CSV written | Unit (file-existence assertion) | Check `docs/label_similarity_candidates.csv` exists after run | Gate: `%sysfunc(fileexist(...))` |
| HARM-03 | Similarity measure and threshold recorded in QC artifact | Unit (QC artifact content) | Check `qc/14_label_similarity.txt` contains threshold= line | Human review of artifact |
| HARM-09 | SSDI columns and CPT1 columns found in `g.master_data_harmonized` | Unit (assertion in program) | Log must show ssdi_present=YES cpt1_present=YES | Program aborts if absent |
| HARM-09 | Value inventory and cross-tab produced for both new groups | Integration | Evidence workbook exists; SSDI/CPT1 sheets present | Human review of workbook |

### Wave 0 Gaps
- [ ] `sas/14_label_similarity.sas` -- the phase's sole deliverable (does not exist yet)
- [ ] `docs/label_similarity_candidates.csv` -- written by the program; committed as artifact
- [ ] `docs/LABEL_SIMILARITY_EVIDENCE.xlsx` -- written by the program; NOT committed (PHI exclusion: .xlsx in .gitignore)

Note: `label_similarity_candidates.csv` IS committed (it is a decision input, like `concept_decisions.csv`). The `.xlsx` evidence workbook is NOT committed (matches existing pattern -- CONCEPT_EVIDENCE.xlsx is also not in git).

---

## Sources

### Primary (HIGH confidence)
- SAS 9.4 Functions and CALL Routines Reference -- `COMPGED`, `COMPLEV`, `SPEDIS` function documentation
- SAS 9.4 `dictionary.columns` -- `label` column availability confirmed by existing pipeline use
- `sas/10_concept_profile.sas` (read) -- established patterns for value inventory, cross-tabulation, cardinality guard, ODS EXCEL output, decision template writing
- `sas/10b_concept_harmonize.sas` (read) -- established `concept_decisions.csv` pattern; `CONFIRMED=YES` gate; coverage check; redundancy proof
- `sas/11_dictionary_reconcile.sas` (read) -- `PROC IMPORT` pattern for `precede_dictionary.csv`; fuzzy matching approaches already attempted
- `sas/13_value_profile_long.sas` (read) -- cardinality ceiling rationale; CPT1 at 159 distinct confirmed
- `docs/precede_dictionary.csv` (read) -- confirmed columns: `sheet`, `dict_name`, `dict_type`, `description`, `source`, `note`, `sas_name`
- `.planning/REQUIREMENTS.md` -- HARM-02, HARM-03, HARM-09 definitions confirmed
- `.planning/ROADMAP.md` -- Phase 14 success criteria confirmed

### Secondary (MEDIUM confidence)
- SAS Communities: `COMPGED` normalization patterns -- multiple sources agree on dividing by `2 * max_length`
- SSDI variable family structure (`SSDI_DEATH_DATE_Y_N`, `SSDI_DEATH_Y_N`, `SSDI_DEATH`) -- inferred from REQUIREMENTS.md HARM-09 description; not directly verified by reading the dataset, since `g.master_data_harmonized` is on P: and not accessible in this research session

---

## Metadata

**Confidence breakdown:**
- Standard stack (SAS functions, patterns): HIGH -- verified against existing pipeline programs
- Architecture (program structure, section ordering): HIGH -- follows established patterns from Phases 10/10b/11/12/13
- COMPGED normalization and threshold: MEDIUM -- formula is standard but threshold value is empirical (dataset-dependent)
- SSDI/CPT1 variable names: MEDIUM -- taken from REQUIREMENTS.md HARM-09; not verified by reading `g.master_data_harmonized` directly

**Research date:** 2026-08-29
**Valid until:** 2026-09-29 (stable SAS 9.4M8 platform; low risk of changes)
