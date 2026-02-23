The change is ready to apply. Here's the full proposal:

# Proposed Changes

## Summary
The sole weakness (Gotcha Awareness: 3/5) is that none of the four Mata reference files mention that `mean()`, `variance()`, and similar Mata functions **propagate** missing values silently instead of excluding them. One high-priority change is proposed.

## Change 1: Add Mata missing value gotcha to `mata-data-access.md`
- **File:** `references/mata-data-access.md`
- **Action:** Modify — insert new section after the `st_data()` section (before `st_view()`)
- **Priority:** High
- **Justification:** Judge specifically noted: "Mata's `mean()` and `variance()` propagate missings rather than excluding them" and "a robust version would filter rows with `select(X, rowmissing(X) :== 0)`." Zero of the four Mata reference files currently mention missing value handling. This is the #1 Mata data-access pitfall.
- **Details:** Add a "Critical: Missing Values in Mata" subsection with:
  - Warning that Mata statistical functions propagate (not exclude) missings
  - WRONG/RIGHT code pattern using `select(X, rowmissing(X) :== 0)`
  - Per-column missing handling variant for heterogeneous missing patterns
  - Rule of thumb: always filter missings after `st_data()`/`st_view()` on real data

## No Other Changes Needed
All other categories scored 5/5. The agent's code was syntactically correct, idiomatic, used optimal Mata functions (`mean()`, `variance()`, `diagonal()`), included bonus features (`st_matrixrowstripe`/`st_matrixcolstripe`), and covered all five task requirements. The only gap was this single missing-value awareness issue, which is fully addressed by the proposed reference file addition.
 = select(X, rowmissing(X) :== 0)
    return(mean(Xclean) \ sqrt(diagonal(variance(Xclean)))')
}
```

### When st_data() Selects a Subset

The third argument to `st_data()` is a selection variable — rows where the variable is 0 or missing are excluded. This does **not** filter missings in the data columns themselves.

```mata
// Loads non-missing rows of "touse" but price/mpg may still have missings
X = st_data(., ("price", "mpg"), "touse")
// Still need:
X = select(X, rowmissing(X) :== 0)
```

### Missing Value Constants

```mata
.                                // system missing (same as .a through .z: > all reals)
missing(x)                       // scalar: 1 if missing
hasmissing(X)                    // matrix: 1 if any element is missing
rowmissing(X)                    // count of missings per row
colmissing(X)                    // count of missings per column
```
```

Also fix the existing `create_zscores()` example (line 253-259) to handle missings:

Replace:
```mata
void create_zscores(string scalar varname, string scalar newvar) {
    real vector data, zscores
    data = st_data(., varname)
    zscores = (data :- mean(data)) :/ sqrt(variance(data))
    st_addvar("double", newvar)
    st_store(., newvar, zscores)
}
```

With:
```mata
void create_zscores(string scalar varname, string scalar newvar) {
    real vector data, zscores, clean
    data = st_data(., varname)
    clean = select(data, data :< .)     // exclude missings for stats
    zscores = (data :- mean(clean)) :/ sqrt(variance(clean))
    st_addvar("double", newvar)
    st_store(., newvar, zscores)         // missing rows stay missing
}
```

## Change 2: Add brief note to mata-matrix-operations.md summary functions
- File: `references/mata-matrix-operations.md`
- Action: Modify
- Priority: **Medium**
- Justification: The `mean()`, `variance()`, `sum()` functions are listed at line 67-71 with no warning. A one-line note connects to the fuller treatment in mata-data-access.md.
- Details: Add a comment after the summary functions block (line 72):

Replace:
```mata
sum(A)                          // All elements
colsum(A); rowsum(A)
mean(A)                         // Column means
min(A); max(A)
colmin(A); colmax(A)
```

With:
```mata
sum(A)                          // All elements
colsum(A); rowsum(A)
mean(A)                         // Column means (propagates missing — see mata-data-access.md)
variance(A)                     // Var-cov matrix, N-1 denom (propagates missing)
min(A); max(A)
colmin(A); colmax(A)
```

## No Further Changes Needed
All other categories scored 5/5. The code quality, command selection, completeness, and idiomaticness were excellent. The `variance()` N-1 denominator note (a minor judge comment) is addressed by the inline comment in Change 2.
