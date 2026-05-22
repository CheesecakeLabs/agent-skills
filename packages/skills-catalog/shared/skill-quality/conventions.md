# CKL Skill Conventions

This is the canonical CKL reference for skill quality, applicable to **any repo** that hosts CKL skills (the `agent-skills` monorepo, the `ckl-ai-skills` plugin marketplace, future repos, or external projects following CKL conventions). When in doubt about what's "correct" in a CKL skill, this document wins over generic Anthropic spec.

Origin: rules in this file are distilled from the `CONTRIBUTING.md` of the `agent-skills` monorepo (sections "Skill Structure", "SKILL.md Format", "Description Quality Standards", "Best Practices") plus the Anthropic Skills spec encoded in `skill-architect`. The CONTRIBUTING.md may or may not be present in every repo this skill reviews — these conventions still apply.

## Description format — mandatory structure

Every description **must** follow:

```
[What it does] + [Use when ...] + [Do NOT use for ...]
```

The validator (`tools/validate-skills.ts`) only checks for the *presence* of these markers. The judgment layer must check **quality**:

| Marker | Quality bar |
|---|---|
| `[What it does]` | Concrete capability, not buzzwords. "Deploys Next.js apps to Vercel" is good. "Helps with deployments" is bad. |
| `Use when …` | At least 2 user-facing trigger phrases in quotes. Phrases the user would actually say, in their actual language (PT-BR is fine for CKL-internal skills). |
| `Do NOT use for …` | At least one negative trigger pointing to a peer skill. Forces the author to think about scope overlap. |

Hard limits enforced by the validator:

- Description ≤ 1024 characters
- No XML angle brackets (`<` or `>`) anywhere in the description
- Description on a SINGLE LINE (no YAML multiline operators `>-`, `|`, etc.)

## Frontmatter — expected fields

```yaml
---
name: kebab-case-name
description: [single line, follows format above]
license: CC-BY-4.0
metadata:
  author: github.com/<username>  OR  "Cheesecake Labs"
  version: '1.0.0'
---
```

- `name` must equal the folder name (case-sensitive).
- `name` must NOT contain "claude" or "anthropic" (reserved).
- `metadata.version` and `metadata.author` are warnings if missing (not blockers).
- `license` is conventional CC-BY-4.0 in this repo. Missing license is a **suggest**, not blocker.

## Non-standard fields seen in CKL skills

These fields appear in some existing skills but are NOT in the official Anthropic spec or in `validate-skills.ts`:

- `triggers:` (list of trigger phrases)
- `user-invocable: true`

**Severity:** suggest (warning), not blocker. Flag as: *"Non-standard frontmatter field `triggers:` — Anthropic spec embeds triggers inside description. Either remove or document why it's intentional."*

Do NOT block on these — CKL's review policy is flag-not-block for non-standard frontmatter fields, since they may be intentional extensions for tooling outside the skill spec.

## Folder structure

```
packages/skills-catalog/skills/(category)/skill-name/
├── SKILL.md            ← required, exact casing
├── scripts/            ← optional, executable scripts (.sh, .py, .ts)
├── templates/          ← optional, file templates copied verbatim
└── references/         ← optional, on-demand docs (load only when SKILL.md tells you to)
```

- Folder name MUST be kebab-case (validator enforces).
- No `README.md` inside the skill folder (Skills are for agents, not humans).
- Category folder name is parenthesized: `(creation)`, `(security)`, `(ckl-internal)`. The parens are part of the name on disk.
- New categories require a `_category.json` entry in the parent.

## Body content rules

| Rule | Severity if violated |
|---|---|
| SKILL.md body ≤ 500 lines | suggest (move detail to `references/`) |
| Must include at least one example block | suggest |
| Must include error handling guidance | suggest |
| References cited in SKILL.md must exist as files | must-fix |
| Reference files must be referenced in SKILL.md (otherwise dead weight) | suggest |

## Progressive disclosure

The three-level system (frontmatter → SKILL.md body → linked files) is load-bearing. Violations to call out:

- A SKILL.md > 500 lines with no `references/` folder → suggest splitting
- A 1000-line `references/foo.md` with no table of contents → suggest TOC
- `references/foo.md` exists but SKILL.md never says when to load it → must-fix (it's effectively dead code)

## Scope and composability

Skills coexist. When reviewing a new skill:

- Does its description's `Do NOT use for` correctly point to overlapping skills?
- Does it assume it's the only skill loaded? (Bad sign: phrases like "I will handle X" without acknowledging other skills exist.)
- Does it trigger on phrases that another existing skill ALSO triggers on? If yes — flag overlap as suggest.

## Imperative writing style

- Instructions use imperative form ("Run X" not "You should run X" or "The agent will run X").
- Avoid "MUST" walls. Explain WHY when something matters.
- Use code blocks for deterministic commands, prose for judgment.

## What the validator covers (so judgment layer can skip)

`tools/validate-skills.ts` already catches:

- Folder kebab-case
- SKILL.md presence + casing
- README.md presence
- Frontmatter YAML validity
- name presence, kebab-case, no reserved, matches folder
- description presence, ≤1024 chars, no XML, has "Use when" / "Do NOT use for"
- metadata.version, metadata.author
- Body line count
- Examples regex
- Error handling regex
- References linked from SKILL.md

**Do not re-implement these in the judgment layer.** Trust the validator. Add your own logic ONLY for things it can't check.
