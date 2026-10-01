## UI Revamp Progress (web/, 2026-10-01)

### Phase 1: Audit
- [x] Run automated audit script (on extracted CSS; see ui-revamp-audit.md for why)
- [x] Heuristic evaluation (Nielsen's 10)
- [x] Visual inventory
- [x] Top issues with severity

### Phase 2: Plan
- [x] Findings summarised in ui-revamp-audit.md
- [x] Order: contrast, mobile tables, hover depth, inset highlight, code block size
- [x] Approval: not asked of the user. This run is a subagent under an instruction that says the design pass must not stop to ask; the plan is the build brief (design/build-brief.md) the direction was approved against. Recorded here so nobody reads this as a user sign-off.

### Phase 3: Implement
- [x] Foundation tokens (already from build brief)
- [x] Hard-rule fixes (CF-4 hover depth, contrast)
- [x] Conditional rules (mobile stacked rows for both tables)
- [x] Animation system (one curve, 120/160/320 ms, reduced motion)
- [x] Accessibility pass (contrast script, 44px targets, focus ring, aria-live on status)

### Phase 4: Validate
- [x] Audit re-run: 2 remaining, both false positives with reasons
- [x] Blur/squint: status band is the focal block at both widths (screenshots design/shots/index-*.png)
- [x] Before/after in ui-revamp-before-after.md
