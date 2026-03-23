# Task 02: Multi-Source Panel Construction

## Task Prompt

I need to build a student-level panel from three separate data sources. Simulate all three datasets and then combine them. Here's the setup:

**Dataset 1 — Test scores (wide format):** 500 students, with columns `student_id`, `school_id`, `score_2019`, `score_2020`, `score_2021`. Some students transferred schools between years (their `school_id` reflects only their most recent school).

**Dataset 2 — Student demographics:** `student_id`, `gender`, `race`, `free_lunch` (binary). Only 480 of the 500 students are in this file (20 missing due to data entry issues).

**Dataset 3 — School characteristics:** `school_id`, `school_name`, `urban`, `total_enrollment`. There are 25 schools.

Build me a long-format student-year panel with demographics and school characteristics merged on. I need you to:
- Reshape the scores to long
- Merge demographics (handle the 20 unmatched students — keep them but flag them)
- Merge school characteristics
- Make sure the merge diagnostics look right — I want to see the `_merge` tabulations
- Create a variable `score_change` that's the year-over-year change within each student
- The final dataset should have `student_id`, `year`, `score`, `score_change`, all demographics, and all school vars

## Capabilities Exercised

- Data management: `reshape long`, `merge 1:1`, `merge m:1`, merge diagnostics
- Gotcha: merge always check `_merge` — must tabulate before dropping
- Gotcha: reshape requires understanding stub/j variable naming
- Programming: `set seed`, `set obs`, simulating multi-file data
- Panel operations: `bysort id (time): gen change = score - score[_n-1]`
- Gotcha: `_n` and `_N` references with `by` groups

## Reference Files

- references/data-management.md
- references/programming-basics.md
- references/variables-operators.md
