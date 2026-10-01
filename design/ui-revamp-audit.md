# UI revamp audit — web/ (2026-10-01)

Skill: Skill(skill="ui-revamp"), run as /design Phase 4 on the build of proposal 1.

## Automated audit
`node ~/.claude/skills/ui-revamp/scripts/audit.js web/` scanned 1 file and reported nothing: it does
not read `<style>` blocks inside HTML. Re-run on the extracted CSS (index.css, replay.css):
- before: 4 violations: CF-4 a:hover colour-only (index, replay), CF-2 "0 surface background levels", CF-3 "no inset highlight".
- after fixes: 2 remain, both script artefacts, verified by reading audit.js:
  - CF-2 counts only literal hex in `background:` inside rules (line 196). This page uses tokens (forbidden-patterns bans hex in components). Real levels: --paper, --sheet, and three state washes.
  - CF-3 counts `inset` only in rule bodies, not in custom properties. `--shadow-2` carries `inset 0 1px 0` in both modes.

## Heuristic pass (Nielsen, 0 fine to 4 catastrophe)
| # | heuristic | score | note |
|---|---|---|---|
| 1 | visibility of system status | 0 | status band + block number + UTC time of the read |
| 2 | match with real world | 0 | brief vocabulary; addresses link to Blockscout |
| 3 | user control | 0 | Try again on error |
| 4 | consistency | 1 | Kind stroke used in table, reasons and backing; fixed: reasons used plain bullets in mockup |
| 5 | error prevention | 0 | read-only page |
| 6 | recognition over recall | 1 | 390: table header hidden; each row carries its own Kind label instead |
| 7 | flexibility | 0 | n/a |
| 8 | minimalism | 0 | no decoration beyond the motif |
| 9 | error recovery | 0 | 5b error text + Try again, stale values dimmed to .55 |
| 10 | help | 1 | limits section; no further docs on page by design (copy is brief-only) |

## Visual inventory
- radius: 2 tokens (--r-sm 2px, --r-md 6px)
- type sizes: 12 (uppercase th only), 13, 15, 16/17, 19-23 clamp, 22-28 clamp, 24, 32-56 clamp
- easing: 1 curve; durations 120/160/320 ms; infinite animations 0
- fonts: Newsreader + IBM Plex Mono
- icons: none

## Top issues found (severity) and status
1. (3) 390 px: minters table wrapped "1,000,000,000 USDG" and the refill header — fixed with a stacked row grid.
2. (3) Light --ink-3 on HALT wash 4.46:1 — fixed (#6b675e → #66625a, now ≥4.8:1 on every surface).
3. (2) Link hover changed colour only (CF-4) — added a 3px rule-coloured halo (box-shadow) on hover.
4. (2) Missing inset top edge on raised surfaces in light — added to --shadow-2.
5. (2) Code block font 14px overflowed at 390 — 13px + 16px padding at ≤760 (still scrolls inside its box, page does not).
6. (1) ui-slop-check S1 em dash: the page title and the empty-state glyph are brief 5b/5a verbatim. Kept; brief is binding.
