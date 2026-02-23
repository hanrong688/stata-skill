# Proposed Changes

## Summary
The agent's critical error — creating event-time dummies as plain time indicators instead of treatment×time interactions — stems from a gap in both reference files: they only show the staggered pattern (where never-treated units have `rel_time = -999`, making dummies implicitly zero for controls) and never address the classic uniform-timing case where dummies must be explicitly interacted with treatment. Three changes are proposed to fix this.

## Change 1: Add uniform-timing event study pattern to `difference-in-differences.md`
- **File:** `references/difference-in-differences.md`
- **Action:** Modify (insert after line 161, end of "Basic Event Study" subsection)
- **Priority:** High
- **Justification:** The judge's critical finding: "Event study variables not interacted with treatment... `gen lead5 = (rel_time == -5)` creates a time dummy, not a treatment×time interaction." The current "Basic Event Study" section only shows the staggered pattern where `rel_time = -999` for never-treated units — the agent copied this pattern into a uniform-timing context where it silently fails.

**Content to insert after line 161:**

```markdown
### Event Study with Uniform Treatment Timing (Classic 2-Group DiD)

When all treated units share the same treatment date, `rel_time` is defined for **every** unit (treated and control alike). In this case, `(rel_time == -5)` is a pure time dummy — it equals 1 for all units at that calendar period. You **must** interact with the treatment indicator.

**Factor variable approach (preferred — most idiomatic):**
```stata
* rel_time defined for all units; omit t = -1 as baseline
* 1.treated# selects only treated units' relative-time dummies
reghdfe outcome ib(-1).rel_time#1.treated, ///
    absorb(unit_id year) vce(cluster unit_id)

* Pre-trend test: joint test of pre-treatment interactions
testparm 1.treated#(-5 -4 -3 -2).rel_time
```

**Manual dummy approach (when you need named variables for plotting):**
```stata
* WRONG — these are time dummies, collinear with i.year
gen lead5 = (rel_time == -5)

* RIGHT — interact with treatment indicator
forvalues k = 5(-1)2 {
    gen lead`k' = treated * (rel_time == -`k')
}
forvalues k = 0/5 {
    gen lag`k' = treated * (rel_time == `k')
}

reghdfe outcome lead5-lead2 lag0-lag5, ///
    absorb(unit_id year) vce(cluster unit_id)
test lead5 lead4 lead3 lead2   // pre-trend test
```

**Alternative: set a sentinel for controls (makes the staggered pattern work):**
```stata
replace rel_time = -999 if treated == 0
* Now (rel_time == -5) is only 1 for treated units
```

**When does the non-interacted pattern work?** Only in staggered designs where never-treated units have `rel_time = -999` (or missing `treatment_year`), so the dummies are automatically zero for the control group.
```

## Change 2: Add treatment-interaction pitfall to `event-study.md`
- **File:** `packages/event-study.md`
- **Action:** Modify (insert new WRONG/RIGHT block in the "Common Pitfalls" section at line 949, before the existing `// WRONG: Skip pre-trend testing` block)
- **Priority:** High
- **Justification:** The judge found that the agent's event-time dummies were "collinear with `i.time`" and that "Stata would drop most or all of them or produce coefficients that are mere time fixed effects." The event-study.md pitfalls section has no guidance about this fundamental specification error.

**Content to insert at line 949 (start of Common Pitfalls code block, before the first `// WRONG`):**

```stata
// WRONG — uniform timing: dummies are just time indicators, collinear with year FE
gen rel_time = year - 2014                   // defined for ALL units
gen lead3 = (rel_time == -3)                 // = 1 for everyone in 2011
reghdfe outcome lead3 lead2 lag0-lag5, absorb(unit_id year)
// Stata drops these or estimates meaningless time effects

// RIGHT — interact with treatment for uniform-timing DiD
gen lead3 = treated * (rel_time == -3)
// Or use factor variables (most idiomatic):
reghdfe outcome ib(-1).rel_time#1.treated, absorb(unit_id year) vce(cluster unit_id)

// NOTE: The non-interacted pattern works in staggered designs because
// never-treated units have rel_time = -999, making dummies zero for controls
```

## Change 3: Expand SKILL.md DiD common pattern with event study
- **File:** `SKILL.md`
- **Action:** Modify (expand the "Difference-in-Differences" common pattern section)
- **Priority:** Medium
- **Justification:** The SKILL.md DiD pattern only shows the 2x2 regression and `csdid`, but no event study. Since event study is a core DiD task (and the judge scored 2/5 on Options due to this gap), adding the correct pattern here provides first-line guidance before reference files are loaded.

**Replace the current DiD common pattern (lines ~235-244) with:**

```markdown
### Difference-in-Differences
```stata
* Classic 2x2 DiD
gen post = (year >= treatment_year)
gen treat_post = treated * post
regress y treated post treat_post, vce(cluster id)

* Event study (uniform timing) — MUST interact with treated
reghdfe y ib(-1).rel_time#1.treated, absorb(id year) vce(cluster id)
testparm 1.treated#(-5 -4 -3 -2).rel_time   // pre-trend test

* Modern staggered DiD (Callaway & Sant'Anna)
csdid y x1 x2, ivar(id) time(year) gvar(first_treat) agg(event)
csdid_plot
```
```

## No Additional Changes Needed

The remaining judge findings (matrix `J(9,4,.)` off-by-one, `i.unit` inefficiency) are generic coding errors, not skill content gaps. The matrix dimension bug is a counting mistake no reference file can prevent. The `i.unit` vs `areg`/`reghdfe` preference is already well-established in the existing reference files (the DiD reference uses `reghdfe` throughout) — the agent simply didn't follow the existing guidance.
lead* lag*) vertical yline(0) ///
    xline(4.5, lpattern(dash)) ///
    coeflabels(lead5="-5" lead4="-4" lead3="-3" lead2="-2" ///
               lag0="0" lag1="1" lag2="2" lag3="3" lag4="4" lag5="5") ///
    xtitle("Periods Relative to Treatment") ytitle("Effect")
```
```

This adds ~18 lines to SKILL.md (330 → ~348, well within the 500-line limit).

---

## Changes NOT proposed

- **Matrix dimension bug** (`J(9,4,.)` → `J(10,4,.)`): This is a one-off counting error by the agent, not a skill knowledge gap. No reference file change needed.
- **`i.unit` vs `areg`/`reghdfe`**: The reference files already consistently recommend `reghdfe` for absorbing FEs (used throughout both DiD files). The agent ignored existing guidance; adding more wouldn't help.
- **Factor variable notation `ib5.time#1.treated`**: Mentioned in Change 1 as an alternative. Could be expanded but keeping it brief avoids over-engineering the reference.
