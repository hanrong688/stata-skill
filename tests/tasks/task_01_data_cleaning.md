# Task 01: Administrative Data Cleaning Pipeline

## Task Prompt

I have a messy CSV of employee records I need to clean up. Rather than make you import the actual file, simulate it — create a dataset of 200 observations with these problems, then fix them all:

- `name`: full names with random extra whitespace, inconsistent casing ("JOHN  smith", "  jane DOE")
- `hire_date`: string dates in mixed formats — some "MM/DD/YYYY", some "YYYY-MM-DD", some "Month DD, YYYY"
- `salary`: stored as string with dollar signs, commas, and some entries like "N/A" or "pending"
- `dept_code`: string department codes where "MKT", "mkt", and "Mkt" should all be the same
- `performance_score`: numeric 1-5 but with some values of 0, -1, and 99 that should be missing
- `email`: some valid, some blank strings ("") that should be proper missing

Clean everything: standardize the names, parse all three date formats into a proper Stata date, destring salary handling the non-numeric entries correctly, standardize department codes, recode bad performance scores to missing, and fix the blank-string emails. At the end verify there are no unexpected missings in the required fields (name, hire_date, dept_code).

## Capabilities Exercised

- String functions: `strtrim()`, `stritrim()`, `strproper()`, `lower()`, `subinstr()`, `regexm()`, `regexs()`
- Date parsing: `date()` with multiple masks, conditional parsing
- Gotcha: `destring, force` silently produces missing — need to know which obs failed
- Gotcha: blank strings ("") are not the same as system missing (.)
- Gotcha: string comparison is case-sensitive
- Data management: `generate`, `replace`, `destring`, `encode`

## Reference Files

- references/string-functions.md
- references/date-time-functions.md
- references/data-management.md
- references/variables-operators.md
