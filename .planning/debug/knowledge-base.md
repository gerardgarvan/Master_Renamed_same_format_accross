# GSD Debug Knowledge Base

Resolved debug sessions. Used by `gsd-debugger` to surface known-pattern hypotheses at the start of new investigations.

---

## md8-count-a-1048575 — SAS XLSX engine reads blank numeric cells as 0 causing all-rows nonmiss=1
- **Date:** 2026-10-07
- **Error patterns:** 1048575, Count A, nonmiss, XLSX, master_data_8, any-column, assert_eq_local, padding rows, missing, zero
- **Root cause:** The SAS XLSX engine reads empty numeric Excel cells as 0 (non-missing), not SAS-missing (.). Blank padding rows in master_data_8.xlsx each have at least one numeric column set to 0 by the XLSX engine, so the any-column non-missing sweep flags all 1,048,575 rows as nonmiss=1. A secondary self-reference bug (row_pos and nonmiss helper variables included in _NUMERIC_ array at compile time) was also fixed but was not the root cause.
- **Fix:** When src_nobs=22473, Count A reads src.master_data_8 directly instead of the raw XLSX. src.master_data_8 already has blank rows stripped by proc 03; nobs=22473 by definition. The xlmd8 libname assignment was removed from that branch. The vname exclusion list was also extended to include row_pos and nonmiss to prevent the self-reference trap in the src_nobs=1048575 branch.
- **Files changed:** sas/27_md8_count.sas
---
