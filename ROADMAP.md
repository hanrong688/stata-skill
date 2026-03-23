# Roadmap

Big-picture directions for improving the skill. These are open problems, not specifications — if you have ideas on any of them, open an issue or PR.

This is also a good place to learn about building Claude Code skills. The problems below — how to test documentation quality, how to structure reference material for agents, how to give agents dynamic access to help systems — apply to skill development in general, not just Stata.

## Real-world empirical test suite

The current tests are synthetic prompts. But there's a huge amount of publicly available empirical work — published papers with replication data, public-use datasets, well-known textbook exercises. A stronger test suite would hand the agent a real dataset and a real task (e.g., replicate the core specification from a paper). The goal isn't perfect replication — there will always be variation. The goal is: can the agent find the right tools, write code that actually runs, and get in the ballpark? That's what tells you whether the documentation is doing its job.

## Leaner reference files and deeper progressive disclosure

The reference files are comprehensive, which may or may not be a good thing. They contain information that's irrelevant to most queries, and there's evidence that extra context can hurt rather than help — the model sometimes cargo-cults patterns it doesn't need. Worth exploring whether the files could be made more minimal, or whether progressive disclosure could go further, letting agents navigate to just the section they care about rather than reading the whole file.

## Gotchas-only skill variant

The eval results suggest that a large portion of the skill's value comes from two sources: (1) gotcha warnings that prevent specific mistakes, and (2) the "anchoring" effect of loading domain-relevant context that keeps the agent focused on the correct task. It's worth testing a stripped-down skill variant that contains *only* the gotchas from SKILL.md — no reference files, no package docs, just the concentrated warnings and routing table. If this variant scores close to the full skill, it would mean the reference material is mostly noise and the gotchas are doing the real work. If it scores much lower, the reference material is pulling its weight. Either way, it tells us where to invest.

## Better test prompts

The current test prompts are structured as explicit instructions ("do X, then Y, then Z"). Real researcher interactions are messier — they describe a goal, provide context, and expect the agent to figure out the approach. The structured format may overstate skill value by making it easy for the agent to follow a recipe, or understate it by not testing whether the skill helps the agent *plan* an approach. Future tests should include:

- **Goal-oriented prompts**: "I have panel data and I'm worried about endogeneity in my lagged dependent variable model. What should I do?" (vs. "Run Arellano-Bond GMM with xtabond2")
- **Ambiguous prompts**: "Clean this data and run regressions" with a messy dataset, where the agent must decide what cleaning and which regressions
- **Multi-step research workflows**: "I need to prepare Table 1 and the main results table for my paper" with a dataset and a rough description of the paper's question
- **Error recovery prompts**: Provide a broken .do file and ask the agent to fix it

## Harder test tasks

Several current tasks hit ceiling (task 04: both conditions score 55/55 every run). Tasks that consistently score 53+ with low variance aren't discriminating — they can't tell us whether a skill change helped or hurt. Options:
- Require exact numerical output verification (not just "did you use the right command")
- Add edge cases: missing data patterns, string encoding issues, panel gaps
- Test less-common options and interactions (e.g., `margins` with triple interactions, `sem` with equality constraints)
- Include tasks where the "obvious" approach is wrong and only the gotcha-aware approach works

## Dynamic help file access

Stata has built-in help files for every command, but they're long and in an ugly format (SMCL). Right now the skill can't use them. Inspired by [@SebastianSardon](https://x.com/SebastianSardon/status/2035218637812806117) and consistent with the [openclaw](https://github.com/anthropics/claw) CLI philosophy: instead of pre-documenting every command, give the agent a way to query help dynamically, in a clean format, at the right granularity. Think of how a good CLI help system works — a top-level overview when you ask broadly, and the ability to drill into specific sub-options when you need detail.

## The anchoring effect

One of the most interesting findings from the eval: the skill's biggest contribution to the runner-only → full-skill delta isn't always syntax knowledge — it's **keeping the agent on task**. The runner-only agent frequently writes code for entirely different tasks (GMM code when asked for synthetic control, SEM code when asked for DiD). The full skill almost never does this. The reference files appear to anchor the agent's attention to the correct domain.

This is a generalizable lesson for skill development: even if the model "knows" the material, loading relevant context at inference time serves a focusing function that prevents the agent from drifting. It suggests that skills should be evaluated not just on "does this teach the model something new?" but also on "does this keep the model from doing something wrong?" The implication for lean/minimal skill design: you can't just strip a skill down to only the things the model doesn't know, because the "redundant" context may be doing important work as an attention anchor.
