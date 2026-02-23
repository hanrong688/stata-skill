It seems write permissions haven't been granted for these files yet. Here's the complete summary of the three proposed changes — all addressing the single identified weakness:

---

# Proposed Changes

## Summary
The only weakness across both deducted categories (Option & Usage Correctness: 4/5, Gotcha Awareness: 4/5) is the `rnormal()` SD-vs-variance confusion. Three targeted edits to two existing reference files address this.

## Change 1: Add SD-vs-variance gotcha to mathematical-functions.md
- **File:** `references/mathematical-functions.md`
- **Action:** Modify (insert after line 58, before "Practical patterns")
- **Priority:** High
- **Justification:** Judge cited `rnormal(0, 4)` vs `rnormal(0, 2)` as the key error in both Option & Usage Correctness and Gotcha Awareness. Current file documents the signature but doesn't warn about notation mismatch.
- **Content to insert:**

```markdown
**Gotcha — `rnormal()` takes SD, not variance:**
Mathematical notation writes N(μ, σ²) where the second parameter is *variance*.
Stata's `rnormal(m, s)` takes *standard deviation*. Always take the square root:
```stata
* DGP says e ~ N(0, 4) — that means variance=4, so SD=2
generate e = rnormal(0, 2)          // CORRECT: SD = sqrt(4) = 2
generate e = rnormal(0, 4)          // WRONG: this gives variance=16, not 4

* DGP says e ~ N(0, σ²) in general
generate e = rnormal(0, sqrt(`sigma2'))
```
```

## Change 2: Add inline comment to Monte Carlo example in bootstrap-simulation.md
- **File:** `references/bootstrap-simulation.md`
- **Action:** Modify (line 64)
- **Priority:** Medium
- **Justification:** Same finding. The existing example already uses `rnormal(0, 2)` correctly but silently — adding a comment reinforces the gotcha at the copy-paste point.
- **Change line 64 from:**
```stata
    generate y = 2 + 3*x + rnormal(0, 2)
```
**to:**
```stata
    generate y = 2 + 3*x + rnormal(0, 2)   // N(0,4) errors: SD=sqrt(4)=2
```

## Change 3: Add pitfall to Common Pitfalls list in bootstrap-simulation.md
- **File:** `references/bootstrap-simulation.md`
- **Action:** Modify (after line 277, add item 6)
- **Priority:** Medium
- **Justification:** The Common Pitfalls section is the natural checklist the agent reviews for gotcha awareness.
- **Add after item 5:**
```markdown
6. Using variance instead of SD in `rnormal()` — N(0, σ²) requires `rnormal(0, sqrt(σ²))`, not `rnormal(0, σ²)`
```
