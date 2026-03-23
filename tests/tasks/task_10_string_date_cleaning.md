# Task 10: Messy Date-Time and String Processing

## Task Prompt

I have event log data with timestamps in various awful formats. Simulate a dataset of 300 observations and clean it:

- `event_id`: sequential integer
- `timestamp_str`: a mix of formats — about 1/3 are "2024-03-15 14:30:00" (ISO datetime), 1/3 are "03/15/2024 2:30 PM" (US with AM/PM), and 1/3 are "15mar2024 14:30" (Stata-ish). All are strings.
- `location`: free-text with inconsistencies — "New York", "new york", "NEW YORK", "New  York" (double space), "New York " (trailing space), and some "NYC" that should all map to "New York"
- `amount`: string with various currency formats — "$1,234.56", "1234.56", "$1234", "EUR 500.00", and some blanks
- `notes`: free text, some containing email addresses that I need to extract into a new variable

Parse all timestamps into a single Stata datetime (`%tc`). Standardize locations (lowercase, trim, map abbreviations). Extract the numeric amount regardless of currency prefix. Use `regexm()`/`regexs()` to pull out email addresses from the notes field. For each cleaning step, report how many observations had issues.

## Capabilities Exercised

- String functions: `strtrim()`, `stritrim()`, `lower()`, `subinstr()`, `regexm()`, `regexs()`, `ustrregexm()`
- Date-time: `clock()` with multiple masks, `%tc` format, conditional parsing
- Gotcha: `date()` returns days since 1960, `clock()` returns milliseconds — don't mix them
- Gotcha: blank strings ("") ≠ system missing (.)
- Gotcha: `regexm()` sets `regexs()` — must extract match before next `regexm()` call
- Data management: `destring`, `generate`, `replace`

## Reference Files

- references/string-functions.md
- references/date-time-functions.md
- references/data-management.md
- references/variables-operators.md
