# Stata Skill Test Suite

Automated evaluation pipeline for the `stata` Claude Code skill. Sends test tasks to a fresh Claude instance with the skill loaded, judges the output against a rubric, and reports scores with metrics.

## Quick Start

```bash
# Single task — score + metrics
python tests/eval.py tests/tasks/task_01_data_cleaning.md

# Multiple runs for variance analysis
python tests/eval.py tests/tasks/task_01_data_cleaning.md --runs 5

# All tasks
python tests/eval.py tests/tasks/task_*.md

# Save results as a baseline
python tests/eval.py tests/tasks/task_*.md --runs 3 --save tests/results/baseline.json

# Compare current results against a baseline
python tests/eval.py tests/tasks/task_*.md --runs 3 --compare tests/results/baseline.json

# Override model (default: claude-sonnet-4-6)
python tests/eval.py tests/tasks/task_01_data_cleaning.md --model claude-opus-4-6
```

## How It Works

`eval.py` uses the Claude Agent SDK to run two independent `query()` calls per test:

```
task_*.md ──> Test Agent ──> Judge Agent ──> results/run_NNN/
                 │                │
                 v                v
          transcript.json   judge_findings.md
                                  │
                                  v
                            metadata.json (score, cost, tokens, time)
```

1. **Test Agent** — receives the task prompt, runs with the skill loaded via the `plugins` parameter. Always uses `cwd=/tmp` so no repo context leaks into the session. Unlimited turns, `bypassPermissions` mode. No system prompt — the skill content itself should be what makes the difference.
2. **Judge Agent** — receives the task, rubric, and transcript. Scores 7 categories (1-5 each) and computes a weighted total out of 55.

Each `query()` call is stateless — no context bleed between tests.

### Skill Isolation

The test agent loads skills via the `plugins` parameter, **not** via `cwd` auto-discovery. This is important because:

- Using `cwd=REPO_ROOT` would let the agent auto-discover the plugin AND access all repo files (CLAUDE.md, test files, reference docs directly), leaking context a real user wouldn't have
- The agent runs with `cwd=/tmp` in all modes, so the only difference between with-skill and without-skill is whether the plugin is loaded
- No biasing system prompt (e.g. "You are a Stata expert") is used — real users don't get one, so the skill content itself must carry the weight

## Pipeline Modes

### Single Run
```bash
python tests/eval.py tests/tasks/task_07_did.md
```
Produces one `run_NNN/` directory with score, transcript, judge findings, and metadata.

### Variance Analysis (`--runs N`)
```bash
python tests/eval.py tests/tasks/task_07_did.md --runs 5
```
Runs the same task N times and reports mean, stdev, and range. Use this to measure consistency. Aim for stdev < 3. High variance signals a documentation gap that causes the agent to take different (sometimes wrong) approaches.

### A/B Comparison (`--compare`)
```bash
# Before editing docs
python tests/eval.py tests/tasks/task_*.md --runs 3 --save tests/results/before.json

# After editing docs
python tests/eval.py tests/tasks/task_*.md --runs 3 --compare tests/results/before.json
```
Prints a delta table showing score changes per task. Look for: mean going up, stdev flat or down, no new failure modes in judge findings. If scores drop, the edit may have introduced confusing examples — simpler is better.

### Staleness Test (`--no-skill`)
```bash
# Baseline without skill
python tests/eval.py tests/tasks/task_*.md --no-skill --save tests/results/no_skill.json

# Compare: does the skill actually help?
python tests/eval.py tests/tasks/task_*.md --compare tests/results/no_skill.json
```
Runs the test agent with no plugin loaded (`plugins=[]`). The environment is otherwise identical (`cwd=/tmp`, same model, no system prompt). Use this to verify the skill provides measurable value — if scores are similar with and without the skill, the task may be too easy or the skill content isn't being used effectively.

### Alternative Skill Version (`--skill-path`)
```bash
# Test current skill
python tests/eval.py tests/tasks/task_*.md --save tests/results/v1.json

# Test alternative version
python tests/eval.py tests/tasks/task_*.md --skill-path /path/to/v2 --compare tests/results/v1.json
```
Points the plugin loader at a different directory for A/B version comparison. The directory must contain a `.claude-plugin/plugin.json`. Use this to test skill edits in a separate checkout before merging.

### Parallel Execution
To run multiple tasks in parallel, launch separate processes:
```bash
python tests/eval.py tests/tasks/task_01_data_cleaning.md --runs 5 &
python tests/eval.py tests/tasks/task_07_did.md --runs 5 &
wait
```
Run directories are created atomically, so parallel execution is safe.

## Output Structure

Each run creates `tests/results/run_NNN/` containing:

| File | Contents |
|------|----------|
| `task.md` | Copy of the original task file |
| `transcript.json` | `{"result": "..."}` — the test agent's full response |
| `judge_findings.md` | Per-category scores, justifications, errors, strengths/weaknesses |
| `metadata.json` | Score, model, skill_mode, cost, tokens, duration, timestamp |

### metadata.json fields

```json
{
    "task_file": "task_01_data_cleaning.md",
    "model": "claude-sonnet-4-6",
    "skill_mode": "with_skill",
    "score": 54,
    "score_max": 55,
    "test_duration_ms": 36179,
    "test_cost_usd": 0.0548,
    "test_usage": { "input_tokens": "...", "output_tokens": "...", "..." },
    "test_num_turns": 1,
    "judge_duration_ms": 32319,
    "judge_cost_usd": 0.0401,
    "timestamp": "2026-03-20T19:19:50Z"
}
```

The `skill_mode` field is one of:
- `"with_skill"` — default, plugin loaded from repo root
- `"no_skill"` — `--no-skill` flag, no plugin loaded
- `"/path/to/dir"` — `--skill-path` flag, custom plugin directory

## Task File Format

```markdown
# Task N: Title

## Task Prompt

The actual prompt sent to the test agent. Everything under this heading
(until the next ## or # heading, or end of file) is extracted.

## Capabilities Exercised

- What skill areas this tests (gotchas, commands, patterns)

## Reference Files

- Which skill reference files are relevant to this task
```

The `## Task Prompt` heading is required.

## Rubric

Scoring rubric is in `tests/rubric.md`. Seven categories, weighted:

| # | Category | Weight | What it measures |
|---|----------|--------|------------------|
| 1 | Syntax Correctness | PRIMARY (2x) | Valid Stata syntax that would run |
| 2 | Command Selection | PRIMARY (2x) | Right command for the task |
| 3 | Option & Usage Correctness | PRIMARY (2x) | Correct options and arguments |
| 4 | Information Retrieval | PRIMARY (2x) | Found and used correct references |
| 5 | Gotcha Awareness | SECONDARY (1x) | Handled known Stata pitfalls |
| 6 | Completeness | SECONDARY (1x) | Addressed all parts of the request |
| 7 | Idiomaticness | SECONDARY (1x) | Follows Stata conventions |

**Weighted total**: (sum of PRIMARY) * 2 + (sum of SECONDARY) = max 55

## Improving Documentation Based on Test Results

The test-and-improve workflow:

1. **Run with variance** (`--runs 3+`) and save a baseline
2. **Read judge findings** from the lowest-scoring runs — they identify specific documentation gaps
3. **Edit the reference file** to address the gap (add a gotcha, fix an example, clarify an option)
4. **Re-run and compare** against the baseline
5. **Check for regressions** — if scores drop, the edit may be too complex. Keep examples simple; overly clever code patterns get cargo-culted incorrectly

Common documentation issues that lower scores:
- Missing gotcha warnings (missing values, variable naming, operator precedence)
- Incorrect or incomplete code examples
- Complex patterns that the agent reproduces incorrectly (prefer simple, direct examples)
- Conflicting patterns across sections of the same reference file

## Runner-Only Baseline (`--runner-only`)

```bash
python tests/eval.py tests/tasks/task_*.md --runner-only --save tests/results/runner_baseline.json
```

Loads a minimal plugin (`tests/runner-only-plugin/`) that contains **only** Stata execution instructions — binary paths and batch mode syntax — with no reference docs, package guides, or gotcha warnings. This is the meaningful comparison baseline: it isolates what the reference material adds beyond "here's how to run Stata."

The `--no-skill` baseline (no plugin at all) is a weaker comparison because the agent can't even execute code.

## Eval Results (March 2026)

Full results, run-by-run index, analysis, and the changes we made are in **[`EVAL_RESULTS_2026-03-22.md`](EVAL_RESULTS_2026-03-22.md)**.

**TL;DR:** 24 tasks × 5 runs, Sonnet 4.6. Full skill 52.5/55 vs runner-only 37.9/55 (+14.6 delta). Skill wins 21/24, ties 2, loses 1. Found and fixed 4 bugs in reference docs, added 3 missing gotchas, added 1 missing workflow. See the full doc for per-task scores, run directory links, and specific evidence from transcripts.

## Legacy Bash Scripts

The `tests/scripts/` directory contains the original bash pipeline (`run_test.sh`, `judge.sh`, `propose_changes.sh`, `run_pipeline.sh`). These still work for quick one-offs but lack metrics tracking, variance analysis, and A/B comparison. Use `eval.py` for all testing.

## Requirements

- Python 3.10+
- `claude-agent-sdk` (installed via `pip install claude-agent-sdk`)
- Claude Code authenticated (the SDK inherits auth from the session)
