# Task 10: String & Date Cleaning

## Task Prompt

Write Stata code that:
1. Creates a small dataset with messy data: names with extra whitespace, inconsistent capitalization of a gender variable ("Male", "MALE", "male", "Female", "FEMALE"), dates as strings in "MM/DD/YYYY" format, and an income variable stored as string with dollar signs and commas ("$45,000")
2. Clean the name variable: trim whitespace, proper case
3. Standardize gender to lowercase and create a numeric encoded version
4. Parse the date strings into proper Stata date format with `%td` display
5. Clean the income string: strip `$` and `,`, convert to numeric with `destring`
6. Verify all conversions worked — check for missing values introduced during cleaning

## Capabilities Exercised

- **String functions:** `strtrim()`, `lower()`, `proper()`, `subinstr()`, `regexr()`
- **Gotcha: String comparison is case-sensitive** — must standardize before comparing
- **Date-time functions:** `date()`, `%td` format
- **Data management:** `destring`, `encode`, `generate`, `replace`
- **Gotcha: Missing values** — check what `destring, force` produces

## Reference Files

- references/string-functions.md
- references/date-time-functions.md
- references/data-management.md
