# Stata Skill Test Suite

Automated evaluation pipeline for the `stata` Claude Code skill. Runs test tasks through the skill, judges the output against a rubric, and proposes concrete improvements.

## Quick Start

```bash
# Run a single task through the full pipeline (run + judge + propose)
./tests/scripts/run_pipeline.sh tests/tasks/task_01_data_cleaning.md

# Run just the test (no judging)
./tests/scripts/run_test.sh tests/tasks/task_07_did.md

# Run all 14 tasks (test only)
./tests/scripts/run_all.sh

# Dry run — list tasks without executing
./tests/scripts/run_all.sh --dry-run

# Judge an existing run
./tests/scripts/judge.sh tests/results/run_001

# Propose skill edits from judge findings
./tests/scripts/propose_changes.sh tests/results/run_001
```

## Pipeline

Each test task goes through three stages:

```
task_*.md ──> run_test.sh ──> judge.sh ──> propose_changes.sh
                  │                │                │
                  v                v                v
           transcript.json  judge_findings.md  proposed_changes.md
```

### Stage 1: Run (`run_test.sh`)

Extracts the prompt from the `## Task Prompt` section of a task file and sends it to `claude --print --output-format json`. The CLI inherits the user's full environment including installed skills.

**Outputs** (in `tests/results/run_NNN/`):
- `transcript.json` — full Claude response
- `task.md` — copy of the original task
- `metadata.json` — run number, timestamp, duration
- `stderr.log` — any CLI errors

### Stage 2: Judge (`judge.sh`)

Sends the task, transcript, and rubric to Claude and asks it to score each of the 7 rubric categories (1-5). The rubric uses weighted scoring: PRIMARY categories (syntax, command selection, options, information retrieval) count 2x, SECONDARY categories (gotcha awareness, completeness, idiomaticness) count 1x. Maximum weighted total is 55.

**Outputs:**
- `judge_findings.md` — scores, justifications, errors found, strengths/weaknesses

### Stage 3: Propose (`propose_changes.sh`)

Sends the judge findings, transcript, task, and the current `skills/stata/SKILL.md` (plus file listings) to Claude. Asks for concrete, actionable edits: file path, action (add/modify/create), content, priority, and justification tied to specific judge findings.

**Outputs:**
- `proposed_changes.md` — specific file edits to improve the skill

## Directory Structure

```
tests/
├── README.md            # This file
├── coverage_map.md      # Skill capability inventory (used to design tasks)
├── rubric.md            # 7-category scoring rubric with weighted totals
├── tasks/               # 14 test task files
│   ├── task_01_data_cleaning.md
│   ├── task_02_merge_reshape.md
│   ├── ...
│   └── task_14_mata_basics.md
├── scripts/
│   ├── run_test.sh      # Run single task
│   ├── run_all.sh       # Run all tasks
│   ├── judge.sh         # Score against rubric
│   ├── propose_changes.sh  # Propose skill edits
│   └── run_pipeline.sh  # Full pipeline (run + judge + propose)
└── results/             # Auto-created run directories
    └── run_NNN/
        ├── task.md
        ├── transcript.json
        ├── metadata.json
        ├── stderr.log
        ├── judge_findings.md
        └── proposed_changes.md
```

## Task File Format

Task files must follow this structure:

```markdown
# Task N: Title

## Task Prompt

The actual prompt sent to Claude. Everything under this heading
(until the next ## or # heading, or end of file) is extracted.

## Capabilities Exercised

- What skill areas this tests

## Reference Files

- Which skill reference files are relevant
```

The `## Task Prompt` heading is required. The runner extracts everything between it and the next same-level heading.

## Rubric Categories

| # | Category | Weight | What it measures |
|---|----------|--------|------------------|
| 1 | Syntax Correctness | PRIMARY (2x) | Valid Stata syntax that would run |
| 2 | Command Selection | PRIMARY (2x) | Right command for the task |
| 3 | Option & Usage Correctness | PRIMARY (2x) | Correct options and arguments |
| 4 | Information Retrieval | PRIMARY (2x) | Found and used correct references |
| 5 | Gotcha Awareness | SECONDARY (1x) | Handled known Stata pitfalls |
| 6 | Completeness | SECONDARY (1x) | Addressed all parts of the request |
| 7 | Idiomaticness | SECONDARY (1x) | Follows Stata conventions |

**Weighted total**: (sum of PRIMARY scores) * 2 + (sum of SECONDARY scores) = max 55

## Requirements

- `claude` CLI installed and authenticated
- `jq` recommended (for JSON parsing; scripts fall back to raw content)
- Bash 4+
