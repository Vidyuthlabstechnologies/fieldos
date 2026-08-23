# CLAUDE.md

This project's conventions, code style, patterns, and quick commands live
in [AGENTS.md](AGENTS.md) -- read that file for the full picture (project
context, adding a router/page, DB conventions, testing requirements, env
vars, quick commands). Keep the two in sync rather than duplicating
content that can drift; this file exists because some tooling looks for
`CLAUDE.md` specifically, not because it should hold separate instructions.

## Client reference data (`resources/`)

`resources/` holds Protek Consult's actual BOQ/estimation source files for
three real projects. It is gitignored and must never be committed, logged,
or quoted with real figures in any file that gets committed (including
this one) -- describe structure, not numbers.

| Project | Files | Imported? |
|---|---|---|
| Narapally | `NARAPALLY MASONRY ESTIMATION.xlsx`, `NARAPALLY.pdf` | Yes -- `importers/narapally_boq.py` |
| Thumukunta | `THUMUKUNTA EST.xlsx`, `THUMUKUNTA.pdf` | Partial -- `importers/brick_and_concrete_boq.py` (general, not client-specific) covers brick work + RCC/concrete; reinforcement, plastering, flooring not yet done |
| Vidyanagar | `VIDYANAGAR CONCRETE ESTIMATION.xlsx`, `VIDYANAGAR STEEL ESTIMATION.xlsx`, `VIDYANAGAR.pdf` | No importer yet -- concrete and steel are separate workbooks |

See AGENTS.md's "Client reference data" section for the sheet-by-sheet
breakdown. `importers/brick_and_concrete_boq.py` targets the BRICK WORK /
CONCRETE ESTIMATION sheet-layout convention generally (any workbook using
it, not just Thumukunta's file) -- `--project-name` is a required argument,
no client default. If asked to extend Thumukunta's coverage or build
Vidyanagar's importer, follow `importers/narapally_boq.py` or
`importers/brick_and_concrete_boq.py`'s pattern: parse, then reconcile
every computed figure against the sheet's own stated total before writing
anything -- refuse output on any mismatch.
