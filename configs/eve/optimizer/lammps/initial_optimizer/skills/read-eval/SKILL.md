---
name: read-eval
description: "Use when interpreting a LAMMPS InterfaceBond energy/force/velocity evaluation to update optimizer guidance."
---

Use this skill when a solver eval or historical solver log needs to inform the next optimizer update.

1. Extract `score`, `score_metric`, and `score_components` from `logs/evaluate/eval_summary.json` or `score.yaml`.
2. Read the live target first. If `score_metric` is `stable_observables`, the score is neutral and the useful evidence is in parsed energy, force, and velocity components.
3. Inspect `score_components.energy`, `score_components.force`, `score_components.velocity`, `first_thermo`, and `final_thermo` before declaring a change promising.
4. Treat output-only hacks, missing logs/dumps, unstable final temperature, or bypassed LAMMPS runs as invalid even if a scalar score appears high.
5. When writing guidance, separate visible evidence from speculation. Cite the specific solver example and score component you used.
6. Prefer short, reusable lessons over one-off stories tied to a single lucky run.

Primary references:

- `guidance/docs/problem.md`
- `guidance/docs/directions.md`
- `guidance/docs/mutation_surface.md`
- `guidance/docs/lammps_guidance.md`
