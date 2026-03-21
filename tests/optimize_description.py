#!/usr/bin/env python3
"""Skill description optimization loop using the Claude Agent SDK.

Drop-in replacement for skill-creator's run_loop.py that uses the Agent SDK
(inherits auth from Claude Code session) instead of the raw Anthropic API.

Usage:
    python tests/optimize_description.py \
        --eval-set tests/trigger-eval.json \
        --skill-path plugins/stata/skills/stata \
        --max-iterations 5 --verbose
"""

import argparse
import asyncio
import json
import re
import sys
import time
from pathlib import Path

# Import working parts from skill-creator (eval uses claude -p, no API key needed)
SKILL_CREATOR = Path.home() / ".claude/plugins/cache/claude-plugins-official/skill-creator"
# Find the active version
for d in sorted(SKILL_CREATOR.iterdir(), reverse=True):
    if (d / "skills/skill-creator/scripts/run_eval.py").exists():
        sys.path.insert(0, str(d / "skills/skill-creator"))
        break

from scripts.run_eval import find_project_root, run_eval  # noqa: E402
from scripts.run_loop import split_eval_set  # noqa: E402
from scripts.utils import parse_skill_md  # noqa: E402

from claude_agent_sdk import ClaudeAgentOptions, ResultMessage, query  # noqa: E402


async def improve_description_sdk(
    skill_name: str,
    skill_content: str,
    current_description: str,
    eval_results: dict,
    history: list[dict],
    model: str,
) -> str:
    """Call Claude via Agent SDK to improve the description based on eval results."""
    failed_triggers = [
        r for r in eval_results["results"]
        if r["should_trigger"] and not r["pass"]
    ]
    false_triggers = [
        r for r in eval_results["results"]
        if not r["should_trigger"] and not r["pass"]
    ]

    train_score = f"{eval_results['summary']['passed']}/{eval_results['summary']['total']}"

    prompt = f"""You are optimizing a skill description for a Claude Code skill called "{skill_name}".

The description appears in Claude's "available_skills" list. When a user sends a query, Claude decides whether to invoke the skill based solely on the title and on this description. Your goal is to write a description that triggers for relevant queries, and doesn't trigger for irrelevant ones.

Current description:
"{current_description}"

Current score: {train_score}

"""
    if failed_triggers:
        prompt += "FAILED TO TRIGGER (should have triggered but didn't):\n"
        for r in failed_triggers:
            prompt += f'  - "{r["query"]}" (triggered {r["triggers"]}/{r["runs"]} times)\n'
        prompt += "\n"

    if false_triggers:
        prompt += "FALSE TRIGGERS (triggered but shouldn't have):\n"
        for r in false_triggers:
            prompt += f'  - "{r["query"]}" (triggered {r["triggers"]}/{r["runs"]} times)\n'
        prompt += "\n"

    if history:
        prompt += "PREVIOUS ATTEMPTS (do NOT repeat these — try something structurally different):\n\n"
        for h in history:
            train_s = f"{h.get('train_passed', h.get('passed', 0))}/{h.get('train_total', h.get('total', 0))}"
            prompt += f'Description: "{h["description"]}" (score: {train_s})\n'
            if "results" in h:
                for r in h["results"]:
                    status = "PASS" if r["pass"] else "FAIL"
                    prompt += f'  [{status}] "{r["query"][:80]}" ({r["triggers"]}/{r["runs"]})\n'
            prompt += "\n"

    prompt += f"""Skill content (for context):
{skill_content[:3000]}

Write a new description (100-200 words, max 1024 characters) that:
- Uses imperative form ("Use this skill for/when...")
- Focuses on user intent, not implementation details
- Is distinctive and immediately recognizable
- Generalizes from the failures to broader categories — do NOT list specific queries

Tips:
- Skills undertrigger more than they overtrigger — be slightly "pushy"
- Include concrete keywords users might say (command names, file types, domain terms)
- Be creative — try different sentence structures across iterations

Respond with ONLY the new description text in <new_description> tags."""

    result_text = ""
    async for msg in query(
        prompt=prompt,
        options=ClaudeAgentOptions(
            model=model,
            permission_mode="bypassPermissions",
            system_prompt="You are an expert at writing skill descriptions that optimize triggering accuracy.",
        ),
    ):
        if isinstance(msg, ResultMessage):
            result_text = msg.result or ""

    match = re.search(r"<new_description>(.*?)</new_description>", result_text, re.DOTALL)
    description = match.group(1).strip().strip('"') if match else result_text.strip().strip('"')

    # Truncate if over limit
    if len(description) > 1024:
        description = description[:1021] + "..."

    return description


async def main():
    parser = argparse.ArgumentParser(description="Optimize skill description (Agent SDK)")
    parser.add_argument("--eval-set", required=True, help="Path to trigger eval JSON")
    parser.add_argument("--skill-path", required=True, help="Path to skill directory")
    parser.add_argument("--model", default="claude-sonnet-4-6", help="Model for improvement and eval")
    parser.add_argument("--max-iterations", type=int, default=5)
    parser.add_argument("--runs-per-query", type=int, default=3)
    parser.add_argument("--holdout", type=float, default=0.4)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    eval_set = json.loads(Path(args.eval_set).read_text())
    skill_path = Path(args.skill_path)
    project_root = find_project_root()
    name, original_description, content = parse_skill_md(skill_path)
    current_description = original_description

    if args.holdout > 0:
        train_set, test_set = split_eval_set(eval_set, args.holdout)
        if args.verbose:
            print(f"Split: {len(train_set)} train, {len(test_set)} test", file=sys.stderr)
    else:
        train_set, test_set = eval_set, []

    history = []
    best_description = current_description
    best_test_score = -1

    for iteration in range(1, args.max_iterations + 1):
        if args.verbose:
            print(f"\n{'='*60}", file=sys.stderr)
            print(f"Iteration {iteration}/{args.max_iterations}", file=sys.stderr)
            print(f"Description: {current_description[:100]}...", file=sys.stderr)
            print(f"{'='*60}", file=sys.stderr)

        # Eval on train + test together
        all_queries = train_set + test_set
        t0 = time.time()
        all_results = run_eval(
            eval_set=all_queries,
            skill_name=name,
            description=current_description,
            num_workers=10,
            timeout=30,
            project_root=project_root,
            runs_per_query=args.runs_per_query,
            trigger_threshold=0.5,
            model=args.model,
        )
        elapsed = time.time() - t0

        # Split results
        train_queries = {q["query"] for q in train_set}
        train_results_list = [r for r in all_results["results"] if r["query"] in train_queries]
        test_results_list = [r for r in all_results["results"] if r["query"] not in train_queries]

        train_passed = sum(1 for r in train_results_list if r["pass"])
        train_total = len(train_results_list)
        test_passed = sum(1 for r in test_results_list if r["pass"])
        test_total = len(test_results_list)

        if args.verbose:
            print(f"Train: {train_passed}/{train_total} ({elapsed:.1f}s)", file=sys.stderr)
            for r in train_results_list:
                s = "PASS" if r["pass"] else "FAIL"
                print(f"  [{s}] {r['triggers']}/{r['runs']} exp={r['should_trigger']}: {r['query'][:70]}", file=sys.stderr)
            if test_set:
                print(f"Test:  {test_passed}/{test_total}", file=sys.stderr)
                for r in test_results_list:
                    s = "PASS" if r["pass"] else "FAIL"
                    print(f"  [{s}] {r['triggers']}/{r['runs']} exp={r['should_trigger']}: {r['query'][:70]}", file=sys.stderr)

        history.append({
            "iteration": iteration,
            "description": current_description,
            "train_passed": train_passed,
            "train_total": train_total,
            "test_passed": test_passed,
            "test_total": test_total,
            "results": train_results_list,
        })

        # Track best by test score
        if test_passed > best_test_score:
            best_test_score = test_passed
            best_description = current_description

        if train_passed == train_total:
            if args.verbose:
                print(f"\nAll train queries passed!", file=sys.stderr)
            break

        if iteration == args.max_iterations:
            break

        # Improve
        if args.verbose:
            print(f"\nImproving description...", file=sys.stderr)

        train_summary = {"passed": train_passed, "failed": train_total - train_passed, "total": train_total}
        train_results = {"results": train_results_list, "summary": train_summary}

        new_description = await improve_description_sdk(
            skill_name=name,
            skill_content=content,
            current_description=current_description,
            eval_results=train_results,
            history=history,
            model=args.model,
        )

        if args.verbose:
            print(f"Proposed: {new_description[:100]}...", file=sys.stderr)

        current_description = new_description

    # Summary
    print(f"\n{'='*60}")
    print(f"Original:  {original_description}")
    print(f"Best:      {best_description}")
    print(f"Best test: {best_test_score}/{len(test_set)}" if test_set else "")
    print(f"Iterations: {len(history)}")
    print(f"{'='*60}")

    output = {
        "original_description": original_description,
        "best_description": best_description,
        "best_test_score": f"{best_test_score}/{len(test_set)}" if test_set else None,
        "history": history,
    }
    results_path = Path(args.skill_path).parent.parent.parent.parent / "tests/results/trigger_optimization.json"
    results_path.parent.mkdir(parents=True, exist_ok=True)
    results_path.write_text(json.dumps(output, indent=2))
    print(f"\nResults saved to {results_path}")


if __name__ == "__main__":
    asyncio.run(main())
