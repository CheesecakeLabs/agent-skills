# Rules — Judgment Checks

These are the checks the deterministic validator and security sweep cannot do. Each rule has:

- **Pattern:** what the smell looks like
- **Why:** one-line plain-language reason (copy verbatim into PR comments)
- **Detection:** how to find it
- **Severity:** blocker | must-fix | suggest | nit
- **Fix:** concrete suggestion

Cite findings as `(reviewer judgment — J<N>)`. The Why line is mandatory in the PR comment — non-engineers (PMs, designers) read these too.

For validator-rule Why lines and security-sweep Why lines (used when composing PR comments for deterministic findings), see `output-templates.md`. This file covers only the judgment checks.

---

## Description quality

### J1 — Description is concrete, not generic

- **Pattern:** description starts with vague verbs ("helps", "assists", "supports", "manages") without specifying what.
- **Why:** Vague descriptions match too many triggers and waste agent attention on irrelevant work.
- **Detection:** look at the first 20 words.
- **Severity:** suggest
- **Fix:** specific capability ("Reviews skill PRs against CKL conventions and runs security scan").

### J2 — Trigger phrases are realistic

- **Pattern:** triggers sound like documentation, not speech (e.g. *"Use when user requests skill validation procedures"*).
- **Why:** Trigger phrases that read like docs never match real user speech.
- **Detection:** look for first-person, present-tense user quotes. Phrases without `"..."` user-voiced strings are suspect.
- **Severity:** must-fix when no user-quoted phrases at all; suggest when partial.
- **Fix:** rewrite with actual user phrases (`"review essa skill"`, `"valida o PR 42"`).

### J3 — Negative scope points to a real peer

- **Pattern:** `Do NOT use for` lists abstract things ("not for code review") instead of a specific peer skill.
- **Why:** Abstract negative scope leaves the agent guessing; naming the peer removes the ambiguity.
- **Detection:** check whether each negative scope item names a peer skill (e.g. `ckl-delivery:pr-review`, `skill-architect`, `marketplace-plugin-creator`).
- **Severity:** suggest
- **Fix:** replace each abstract item with `(use <peer-skill>)`.

### J4 — Description length sanity

- **Pattern:** description is too thin or hugging the 1024 cap.
- **Why:** Descriptions under 80 chars under-describe the skill; over 900 chars risk hitting the cap with no room to grow.
- **Detection:** `awk '/^description:/{print length}'`.
- **Severity:** suggest in both cases.
- **Fix:** target 200–700 chars.

---

## Workflow coherence

### J5 — Pre-requisites are stated

- **Pattern:** the skill invokes external tools (`gh`, `acli`, `npm run X`, an MCP server) without listing them in pre-requisites.
- **Why:** A skill that silently depends on `gh` or an MCP fails cryptically when the dependency is missing.
- **Detection:** grep body for tool invocations, cross-check against pre-requisites section.
- **Severity:** must-fix
- **Fix:** add a pre-requisites row per external dependency.

### J6 — Error paths are addressed

- **Pattern:** error sections say "if it fails, retry" without specifying what.
- **Why:** Generic error advice tells the agent nothing useful. State what to do when each specific failure hits.
- **Severity:** suggest
- **Fix:** enumerate each known failure mode and its handling.

### J7 — Examples are realistic

- **Pattern:** examples are skeletal ("do the thing"); no concrete user phrase, no specific output.
- **Why:** Skeletal examples don't teach the agent the actual workflow.
- **Severity:** suggest
- **Fix:** each example needs `user-quoted phrase + specific actions + specific expected output`.

### J8 — Decision points are explicit

- **Pattern:** branches described with fuzzy conditions ("if appropriate", "when relevant").
- **Why:** Fuzzy conditions get picked randomly by the agent.
- **Severity:** must-fix
- **Fix:** state the trigger condition unambiguously.

---

## Scope and composability

### J9 — Scope overlap with existing skills

- **Pattern:** trigger phrases overlap > 50% with a peer skill in the same category, or the `[What]` clause is interchangeable with a peer.
- **Why:** Two skills with overlapping triggers race to handle the same request — the agent picks one non-deterministically.
- **Detection:** list siblings in the same category, read their descriptions. (For cross-repo, see [[ckl-recurring-issues]] R8.)
- **Severity:** suggest
- **Fix:** distinguish triggers or ask the author to merge.

### J10 — Skill respects other skills' territory

- **Pattern:** skill announces it'll do work owned by a peer (e.g. posting to Jira when the `jira` skill exists).
- **Why:** Duplicate work bypasses the peer's workflow guards.
- **Severity:** suggest
- **Fix:** delegate via the peer skill's interface, don't reimplement.

### J11 — Naming consistency

- **Pattern:** skill name differs in pattern from peers (verb-noun vs. noun-noun, `pr-review` vs. `pull-request-review`).
- **Why:** Naming inconsistency across peers makes discovery harder and signals lack of coordination.
- **Severity:** suggest
- **Fix:** match the category's dominant naming pattern.

---

## Progressive disclosure

### J12 — SKILL.md size discipline

- **Pattern:** SKILL.md 400–500 lines with no `references/` folder, or contains long inline tables (>40 rows).
- **Why:** A monolithic SKILL.md loads in full every invocation. Split into references so only the relevant section loads.
- **Severity:** suggest
- **Fix:** extract reference material to `references/<topic>.md` and load on demand.

### J13 — Reference load-conditions are stated

- **Pattern:** a file in `references/` is named in SKILL.md without a "load when X" instruction, OR SKILL.md says "load all references".
- **Why:** A reference without a load condition either never loads (dead) or always loads (defeats progressive disclosure).
- **Severity:** must-fix
- **Fix:** add a one-line load pointer per reference, ideally in a `## References` table near the top of SKILL.md.

---

## CKL-specific patterns

### J14 — Non-standard frontmatter fields

- **Pattern:** frontmatter contains fields beyond `name | description | license | metadata | allowed-tools` (e.g. `triggers:`, `user-invocable:`).
- **Why:** Non-standard fields pass the validator but aren't in the Anthropic spec; they may break in future harness releases.
- **Severity:** suggest
- **Fix:** remove the field or add a comment justifying it.

### J15 — Description in mixed PT-BR/EN

- **Pattern:** description has trigger phrases only in one language while the team speaks both; or skill name in EN with 100% PT-BR description (or vice versa) without trigger phrases bridging.
- **Why:** A monolingual description will miss either Portuguese or English user requests.
- **Severity:** suggest
- **Fix:** include user-quoted trigger phrases in both languages.

### J16 — User perspective, not internal jargon

- **Pattern:** description uses internal jargon ("remediate CI pipeline failures") instead of user voice ("fix my build").
- **Why:** "User perspective" descriptions match how people actually speak. Internal jargon matches nothing.
- **Severity:** must-fix
- **Fix:** rewrite each problematic phrase in user voice.

---

## Scripts and security (quality, beyond the security sweep)

### J17 — Scripts have shebang + `set -euo pipefail`

- **Pattern:** shell script missing `#!/usr/bin/env bash` or `set -euo pipefail` at the top.
- **Why:** Shell scripts without `set -euo pipefail` swallow errors silently — a typo can succeed with empty output and corrupt downstream steps.
- **Severity:** must-fix
- **Fix:** add both at the top.

### J18 — Scripts validate their args

- **Pattern:** script uses positional args but doesn't check `$#`.
- **Why:** Scripts that don't validate arity produce confusing errors. The user has no idea what went wrong.
- **Severity:** must-fix
- **Fix:** check `[[ $# -ne N ]]` and print usage.

### J19 — Scripts have usage line

- **Pattern:** script doesn't print usage on bad input or `-h`.
- **Why:** Without a usage line, the user has no way to discover how to call the script.
- **Severity:** suggest
- **Fix:** add a usage echo + exit 2 on bad input.

### J20 — Scripts don't assume PWD

- **Pattern:** script does `cat tools/something` without first cd-ing or resolving to repo root.
- **Why:** Scripts that assume `pwd` is the repo root break when called from a subdirectory.
- **Severity:** must-fix
- **Fix:** use `$(git rev-parse --show-toplevel)` or resolve relative to the script's own location (`$(dirname "$0")`).

---

## YAML frontmatter pitfalls

### J21 — Unquoted `#` in description truncates YAML

- **Pattern:** description contains `#` followed by a non-`/` char (e.g. `"PR #42"`, `"channel #engineering"`) AND is not wrapped in quotes.
- **Why:** A `#` in an unquoted YAML description silently truncates the description at the `#`. Downstream checks then run against a truncated string while the file looks correct.
- **Detection:**
  1. Read the frontmatter from disk.
  2. If the description value starts unquoted AND contains ` #` (space + hash) → flag.
  3. Cross-check: parsed length vs. raw file length. Mismatch = confirmation.
- **Severity:** must-fix
- **Fix:** wrap the description in single quotes, OR remove the `#` (use `"PR 42"`). Do not use YAML multiline operators (`>-`, `|`) — those violate the single-line rule.

---

## allowed-tools frontmatter (least-authority + portability)

Origin: codified from real findings during 2026-05-21 PR review of `ckl-delivery:pr-review`.

### J22 — Dead allowed-tools entries

- **Pattern:** an entry in `allowed-tools` that is never invoked anywhere in SKILL.md body or scripts.
- **Why:** Dead entries grant permissions the skill never uses, weakening least-authority for zero gain.
- **Detection:** for each `Bash(<cmd>:*)` entry, grep body and scripts for the command name. Zero matches → flag. Exception: commands appearing only in "do NOT do this" examples.
- **Severity:** suggest
- **Fix:** remove the entry, or add a comment explaining why it's pre-approved despite not being invoked.

### J23 — Inconsistent narrowness across allowed-tools entries

- **Pattern:** some entries narrowed to subcommands (`Bash(npm run *)`) while equivalent peers grant the whole CLI (`Bash(pnpm:*)`).
- **Why:** A scoped `Bash(pnpm run *)` next to an unscoped `Bash(pnpm:*)` defeats narrowing — the wide grant lets the agent run `pnpm exec <anything>`.
- **Detection:** group entries by base command; if any in the group is narrowed, peers should be narrowed similarly. Exception: tools whose subcommand surface is small enough that narrowing is impractical (`make`, `git`).
- **Severity:** suggest
- **Fix:** narrow the wide entries to match (`Bash(pnpm run *), Bash(pnpm test *), Bash(pnpm install)`).

### J24 — Subagent-dispatch tool name varies by harness

- **Pattern:** body mentions subagent dispatch but `allowed-tools` lists only one of `Task` / `Agent`.
- **Why:** Subagent-dispatch is called `Task` in some harnesses and `Agent` in others. Listing only one breaks cross-harness portability without granting extra capability.
- **Detection:** grep body for `Task`, `Agent`, `subagent`, `dispatch`, `parallel agents`. If hits, both names should appear in `allowed-tools`.
- **Severity:** suggest
- **Fix:** list both: `allowed-tools: [..., Task, Agent]`.

---

## State-of-the-art 2026 (externally validated)

**Deliberately NOT codified (decision logged 2026-05-21):**

- **J26 (MCP wildcard narrowing)** — would fire on most existing CKL skills using Atlassian/Slack MCP wildcards even when intentional; calibration of first-party vs. third-party MCPs needs more real-world data. Revisit when 3+ real PRs show wildcards being abused.
- **J28 (untrusted-input threat model docs)** — risk-tier classification (HIGH/MEDIUM/LOW) requires the LLM to judge skill intent accurately; FP risk is real. `security-threat-model` skill exists as manual escalation, documented in J27. Revisit when real-world incidents land.

### J25 — Mature skills must have a Gotchas section

- **Pattern:** SKILL.md has no `## Gotchas`, `## Common pitfalls`, `## Known issues`, or equivalent.
- **Why:** Without a Gotchas section, real failure modes get forgotten and re-introduced. Anthropic engineering calls this *"the most valuable content in any skill"*.
- **Detection:** look for a heading containing "gotcha", "pitfall", "known issue", "common mistake", "troubleshoot" (case-insensitive). Skill is "mature" if version ≥ 1.0.0 OR git log shows ≥ 3 commits to SKILL.md OR another skill depends on it.
- **Severity:** new skill → suggest; mature skill → must-fix.
- **Fix:** add `## Gotchas` near the bottom; empty placeholder is acceptable for a new skill.
- **Source:** [Anthropic skill authoring best practices](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/best-practices).

### J27 — Skills using MCP servers must document the trust boundary

- **Pattern:** SKILL.md invokes MCP tools but doesn't document (a) WHICH server is required, (b) WHAT data flows through it, (c) WHAT happens when the MCP is unavailable.
- **Why:** Every MCP server is a trust boundary. A skill that silently depends on one fails unpredictably and creates unaudited attack surface.
- **Detection:** grep SKILL.md for `mcp__`, "MCP server", "MCP tool", "via the X MCP", names of common MCPs (Atlassian, Slack, GitHub, Notion). If hits ≥ 1, check for the three points above.
- **Severity:** must-fix
- **Fix:** add a `## MCP dependencies` subsection naming the server, the data flow, and the unavailability branch.
- **Escalation:** for skills handling genuinely sensitive data (credentials, PII, multi-tenant boundaries), recommend invoking the `security-threat-model` skill separately for a formal threat model.
- **Source:** [Lasso Security — Indirect prompt injection in Claude Code](https://www.lasso.security/blog/the-hidden-backdoor-in-claude-coding-assistant). [TrueFoundry — Enterprise prompt injection guide](https://www.truefoundry.com/blog/claude-code-prompt-injection).

### J29 — Parallel subagent dispatch requires preconditions in SKILL.md

- **Pattern:** SKILL.md describes parallel dispatch via Task/Agent but doesn't state the three required preconditions.
- **Why:** Parallel subagent dispatch without explicit preconditions (independence, no shared state, file boundaries) causes race conditions, lost results, or silent data corruption.
- **Detection:** grep for "parallel", "in parallel", "concurrent", "fan-out", "dispatch N". If parallel dispatch is described, verify SKILL.md states ALL three:
  - tasks are independent (no shared state)
  - each task targets distinct files (no overlap)
  - minimum N tasks for parallelism (acknowledge when sequential is better)
  - **completion gate**: what happens when not all subagents return usable results (bounded retry, partial-mode honesty, fail-fast — pick one and state it).
- **Severity:** must-fix
- **Fix:** add a `## Parallel dispatch preconditions` subsection with the four lines above.
- **Source:** [Create custom subagents — Claude Code Docs](https://code.claude.com/docs/en/sub-agents). [Sub-Agents Best Practices — claudefa.st](https://claudefa.st/blog/guide/agents/sub-agent-best-practices).

---

## Output discipline

Cite each finding's source. Use the human-readable label first, then the internal ID in parentheses — so a non-engineer reading the PR comment doesn't have to decode the technical name:

- `(structural validator)` — from `scripts/validate_skill.py`
- `(security scan)` — from `scripts/security_sweep.sh`
- `(CKL contribution guide)` — from CKL CONTRIBUTING.md
- `(reviewer judgment — J<N>)` — from this file
- `(recurring CKL pattern — R<N>)` — from `ckl-recurring-issues.md`

Always include the `**Why it matters:**` one-liner alongside the rule name. For judgment rules, copy the **Why** line from the matching entry in this file. For validator and security-sweep rules, copy from the Why tables in `output-templates.md`.

Without source attribution AND a Why line, the author can't push back if the rule is wrong, and the non-engineer audience can't understand what they did wrong. Always cite, always explain.
