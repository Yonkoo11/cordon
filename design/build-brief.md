# Build brief — Backed status page (direction: Proposal 1, "Ledger: solid line, dashed line")

Every number here is a decision. Copy comes from ai/PRODUCT-BRIEF.md 5b verbatim; where this brief
shows copy it is quoted from there. Read the whole brief before writing a line.

## Output contract
- Files: `web/index.html` (markup + inline CSS), `web/chain.js` (ES module, reads + render),
  `web/replay.html` (+ inline CSS, small inline module), `web/replay.txt` (copy of demo/replay.txt).
- No framework, no build step, no wallet, no analytics, no external script. Fonts: Google Fonts
  (Newsreader 400/500 incl. italic, IBM Plex Mono 400/500) with system fallbacks.
- Must not add: badges, stats rows, testimonials, any sentence not in 5b. Machine facts (addresses,
  block number, UTC time, values, contract names) are allowed because they are reads, not copy.

## Tokens (8 colour roles per mode + 3 state colours)
| token | light | dark | job |
|---|---|---|---|
| --paper | #f6f3ec | #12130f | page ground (tinted, ER-1) |
| --sheet | #fffdf8 | #1b1c18 | raised surface (status band default, code block) |
| --ink | #1b1a17 | #ece8de | primary text, solid stroke |
| --ink-2 | #4f4c44 | #b9b4a7 | secondary text |
| --ink-3 | #6b675e | #948f83 | labels, meta, dashed stroke |
| --rule | #d9d3c5 | #33342e | hairlines |
| --ok / --ok-wash | #1f6b3a / #e4efe3 | #74c993 / #172619 | HEALTHY |
| --warn / --warn-wash | #835500 / #f5ead2 | #e6b65a / #29230f | CAUTION |
| --bad / --bad-wash | #a3231b / #f6e0dc | #f08a7f / #2d1a17 | HALT |
Contrast targets: every text token ≥ 4.5:1 on --paper and on each wash (checked in QA with a script).
Deviation from P1 mockup: --ink-2/--ink-3 darkened in light (#55524a→#4f4c44, #77736a→#6b675e) so
--ink-3 13px mono labels clear 4.5:1 on paper; P1 mockup measured below that.

## Type
- Display/prose: Newsreader. Machine facts: IBM Plex Mono. Never prose in mono, never a machine fact in serif (copy-rules §7). Exception: the 5b Kind labels are prose (serif).
- Scale: 13 (mono labels, uppercase +.06em, 12px min only for uppercase th) · 15 (mono values) · 17 (body) · 19–23 clamp (backing line, limits) · 22–28 clamp (status sentence) · 32–56 clamp (h1, line-height 1.04, -0.025em). Ratio h1/body = 3.3×.
- tabular-nums on all tables.

## Layout (max-width 1120px, gutter 16px)
1. Header: grid 7fr/4fr, gap 48px, padding-top 72px (48 at ≤760). Left: h1 + subline (max 52ch). Right, bottom-aligned: `#read-meta` (mono 13px: `block N · HH:MM:SS UTC`) and the "See it stop a bad mint" link (44px min target).
2. Status band (`#status`): radius --r-md 6px, shadow-2, padding 24/28/24/36, left edge 6px solid state colour, background = state wash. Holds status sentence, reasons list (each `<li>` = Kind stroke + `bit N` mono + 5b reason text), Try again button (error only). Margin-bottom 64px.
3. "What we read" table, 4 columns (5b header). Rows: Supply on this chain · Supply, 1 h change · Minter set · Admin transfer · Report age (labels from 5d + "Supply on this chain" phrase from reasons 0/7). At ≤760 the Read from column moves under the label (no column hidden; addresses stay visible).
4. Backing: grid 7fr/4fr. Left: h2 + backing line with each figure a mono `.fig` with 2px dashed underline. Right: reported Kind marker, report URI link, sha256 (mono 13px, break-all).
5. Minters: h2 + table (controller link · cap · refill / s). Header labels "Controller", "Cap", "Refill per second" are nouns lifted from 5a.
6. Use it: h2 + `pre` (sheet, shadow-2, overflow-x:auto inside the box) with the constructor call and deployed addresses as code comments; under it a mono link row (Blockscout / Sourcify per contract).
7. Limits: h2 + ordered list, serif 19–23px, `01`..`05` mono counters, top hairline per item.
8. Footer: 5b footer verbatim, link to https://github.com/Yonkoo11/backed.
Section spacing: 72px between sections, 64px after status.

## Motif — solid vs dashed (three scales)
- Large: status band left edge, solid 6px in state colour.
- Medium: `.kind::before` 28×2px stroke, solid (`Read from the chain`) / dashed (`Posted by our reporter from the KPMG report`); also on each reason li by bit (0–4 solid, 5–7 dashed).
- Small: `.fig` dashed 2px underline under reported figures.

## Radius, shadow
- --r-sm 2px (buttons), --r-md 6px (status band, code). Two values.
- Shadow philosophy: soft-elevation ladder (light) — shadow-1 for button, shadow-2 for status band and code. Dark: inset 1px top highlight + deep low-alpha drop. No glows.

## Motion
- One curve `cubic-bezier(.2,.8,.2,1)`. Durations: 120ms press, 160ms hover, 320ms status background/edge colour change.
- Button: hover translateY(-1px) + shadow-2; active scale(.97). Links: underline offset change only is not depth, so links get `text-decoration-color` + background tint on hover inside @media(hover:hover); primary depth reserved for the button.
- Zero infinite animations; no entrance animation. Reduced motion: transition-duration .01ms.

## States (brief 5a)
- Empty: every `[data-v]`, backing line, read-meta show `—`; status text `Reading Robinhood Chain…`; band neutral (sheet bg, ink-3 edge).
- Loading: same; AbortController cancels at 8000 ms → Error.
- Error: `Could not reach Robinhood Chain. Nothing here is a verdict. Try again.` + `Try again` button; if values exist they stay, at opacity .55.
- Success: level wash + edge + h1 "stop." in state colour; refresh every 60000 ms and on Try again.

## Replay (web/replay.html)
Same tokens and fonts. h1 = "See it stop a bad mint" (5b replay link text). `pre` loads `replay.txt` via fetch and shows it verbatim; on failure shows `Replay output not found. Run the command below to produce it.` Then the command in a `pre`:
`forge test --match-test test_overMintHaltsBorrow --fork-url https://rpc.mainnet.chain.robinhood.com -vv`. Link back to index (text: "Backed", the product name).

## Acceptance checklist
- [ ] Every 5b string used on the page appears byte-identical (grep script, curly vs straight apostrophes as in 5b: straight `'`).
- [ ] Status band top < 900 at 1440×900 and < 844 at 390×844.
- [ ] scrollWidth == innerWidth at 390.
- [ ] Light and dark screenshots at 1440 and 390 viewed.
- [ ] All text tokens ≥ 4.5:1 on paper and washes (script).
- [ ] No hex outside :root blocks; ≤ 2 radius tokens; one easing curve; 0 infinite animations.
- [ ] Nothing in src/, test/, script/ touched.
- [ ] Not one word of copy, one colour or one URL differs from this brief.
