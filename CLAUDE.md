<!-- GSD:project-start source:PROJECT.md -->
## Project

**PROJECT.md — PeCAN Master Dataset Integration**

A reproducible, provenance-tracked SAS pipeline that merges eight heterogeneous master
extracts (`master_data_1..8.sas7bdat`) into one analysis-ready patient-level dataset.
Every type conversion, name reconciliation, and row-count change is traceable to a
numbered SAS program in version control.

**Core Value:** A single `99_run_all.sas` that runs start-to-finish in a clean SAS session against
read-only sources, producing `g.master_data_merged` (41,150 rows), passing QC reports,
a data dictionary, and a resolved DECISIONS.md — with no manual steps.

### Constraints

- SAS 9.4M8 on Windows; session encoding is not UTF-8 (source of PCM-F-10 encoding damage)
- Read-only on `master_data_1..8.sas7bdat` and everything under `raw\master`
- No PHI in git: `.gitignore` excludes `*.sas7bdat`, `*.xlsx`, `*.csv`, `data/` tree
- Repo on local disk, not P: drive — git against network share is slow and prone to index corruption
- Delivery: UF colors (#0021A5, #FA4616) on visual deliverables; KEY sheet leftmost in workbooks

---
<!-- GSD:project-end -->

<!-- GSD:stack-start source:STACK.md -->
## Technology Stack

Technology stack not yet documented. Will populate after codebase mapping or first phase.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
