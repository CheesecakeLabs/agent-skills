# CKL Recurring Issues

> **Status:** empty knowledge base. Grows over time as CKL maintainers document patterns that keep showing up in real PR reviews.

This file is the **evolution layer** of `skill-reviewer`. The deterministic validator and the judgment-checks are static. This file captures **what's actually happening in CKL PRs over time** — patterns that no generic rule catches but that the team keeps tripping on.

## How to add a new entry

When the reviewer says something like *"essa eu sempre pego, anota aí"* or *"adiciona como recurring: X"*, append a new entry below using this template:

```markdown
### R<N> — <short pattern name>

**First flagged:** YYYY-MM-DD
**Severity:** blocker | must-fix | suggest | nit
**Where it shows up:** <file pattern, e.g. SKILL.md description, scripts/*.sh, frontmatter>
**The pattern:** <one-line description of what the smell looks like>

**Detection heuristic:**
- Regex or simple rule the LLM should apply when scanning.

**Why it matters:**
- The CKL-specific reason this is a problem.

**Suggested fix:**
- Concrete replacement.

**Examples seen in the wild:**
- (anonymized snippet from a real PR)
```

## Why this file matters

The skill's judgment checks (J1–J20) are derived from the official Anthropic spec + CONTRIBUTING.md. They don't know what CKL keeps doing wrong. **This file is where institutional knowledge accumulates.** A rule here can be more aggressive (e.g., promote a generic "suggest" to "must-fix") because the team has agreed it's a real problem.

## Empty for now

No entries yet — this knowledge base is new and no patterns have surfaced through real reviews. The skill-reviewer should mention this in its output:

> *"No recurring CKL issues registered yet. As patterns emerge, add them to `references/ckl-recurring-issues.md`."*

## Cross-reference

When a finding maps to a recurring issue, cite it with `(recurring:R<N>)` in the report — same convention as `(judgment:J<N>)`. This lets the author trace the rule back to its origin.

<!-- ENTRIES GO BELOW THIS LINE -->
