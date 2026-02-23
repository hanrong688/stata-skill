# Task 01: Data Cleaning & Missing Value Handling

## Task Prompt

Using `sysuse auto`, write a do-file that:
1. Creates a binary indicator `expensive` for cars with price above $6,000, handling missing values correctly
2. Creates a `price_category` variable with 3 levels (cheap/medium/expensive) based on price terciles
3. Labels all new variables and their values
4. Replaces negative values of `rep78` with missing (pretend some exist)
5. Saves the cleaned dataset as `auto_clean.dta` with compression

## Capabilities Exercised

- **Gotcha: Missing values sort to +infinity** — must use `if !missing()` on comparisons
- **Gotcha: generate vs replace** — creating new vs modifying existing variables
- **Data management:** `generate`, `replace`, `label variable`, `label define`, `label values`
- **Variables/operators:** `if` qualifiers, missing value handling
- **Workflow:** `compress`, `save`, `describe`

## Reference Files

- references/data-management.md
- references/variables-operators.md
- references/basics-getting-started.md
