# Printer Studio KH — agent guide

Root instructions: the Developer project instructions (`/Users/you/Developer/CLAUDE.md`) and the canonical lead rules in `/Users/you/Developer/_orchestra/developer-handoff/LEAD-RULES.md`.

## Efficient delegation and parallel work (owner, 2026-11-10)

Canonical: [_orchestra/developer-handoff/LEAD-RULES.md](/Users/you/Developer/_orchestra/developer-handoff/LEAD-RULES.md) → "Efficient delegation and parallel work", with "Who does what", "Every task, at all cost" and "Hard limits"; that file wins. Use the global efficient-orchestration skill; app-specific commands and holds stay here.

- Delegate complete deliverables: a useful, inexpensive, suitable worker owns one bounded, non-overlapping deliverable (named files/worktree/base commit), its implementation and routine fix loop; the lead plans, checks the actual work, integrates and accepts. Developer keeps portfolio priorities, cross-app/protected decisions and final release/live acceptance; app leads accept worker results within their brief. Existing model routing stays unchanged.
- Independent app leads work in parallel; never park one app's independent work for another app's schedule. Serialize only real conflicts: a shared writer/worktree, or shared heavy tests and target actions. Shared heavy tests use the existing KHApps `testctl` schedule; device, security, paid/public, Production and quiet-point holds remain.
- Give workers realistic fixtures and early permitted read-only checks; verify a small result before handoff. Reuse source-bound unchanged passing results; rerun changed or failed checks and affected callers, using a full gate when reach requires it. This section adds no approval gate: existing release gates and holds still apply.
