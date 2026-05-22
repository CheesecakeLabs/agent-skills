# Judgment Checks

These are checks the deterministic validator CANNOT do. They require reading the skill's content and applying reviewer judgment. Run all of them in Step 3 of the workflow.

For each finding, output: `[severity] [path:line] [rule] — [specific evidence] — [concrete suggestion]`.

## Description quality (beyond presence)

The validator checks that `Use when` and `Do NOT use for` exist. The judgment layer checks they're GOOD.

### J1 — Description is concrete, not generic

**Bad smell:** description starts with vague verbs like "helps", "assists", "supports", "manages" without specifying what.

Example flag (suggest):
> Description starts with "helps with skill creation" — too vague. Replace with a specific capability: "Reviews skill PRs against CKL conventions and runs security scan".

### J2 — Trigger phrases are realistic

**Bad smell:** trigger phrases sound like documentation, not speech.

- Bad: `Use when user requests skill validation procedures`
- Good: `Use when user says "review essa skill" or "valida o PR 42"`

Flag (must-fix): triggers missing user-quoted phrases.

### J3 — Negative scope points to a real peer

**Bad smell:** `Do NOT use for` lists abstract things ("not for code review") instead of pointing to a specific peer skill.

Look up peer skills:
- For PR review tasks → should mention `pr-review` (ckl-delivery)
- For creating skills → should mention `skill-architect`
- For marketplace work → should mention `marketplace-plugin-creator`

Flag (suggest) when scope is abstract.

### J4 — Description length sanity

Validator only checks ≤1024 chars. Judgment:

- < 80 chars → suggest "description too thin, expand"
- 200–700 chars → ideal
- > 900 chars → suggest "approaching the 1024 limit, can probably be tighter"

## Workflow coherence

### J5 — Pre-requisites are stated

If the skill calls external tools (gh, acli, npm scripts, MCP), are pre-requisites listed?

Flag (must-fix) when:
- Skill invokes `gh ...` without listing gh as pre-requisite
- Skill invokes `npm run X` without confirming X exists in package.json
- Skill calls an MCP server tool without listing the MCP as required

### J6 — Error paths are addressed

The validator regex catches "error|fail|troubleshoot". Judgment checks that the error handling is SPECIFIC, not just a generic "if it fails, retry".

Flag (suggest) when error sections say things like "handle errors appropriately" without specifying what.

### J7 — Examples are realistic

Walk the examples in SKILL.md. Each should have:
- Concrete user phrase (in quotes)
- Specific actions (not "do the thing")
- Specific expected output

Flag (suggest) when examples are skeletal placeholders.

### J8 — Decision points are explicit

When the skill has branches (different modes, conditional steps), are the conditions for each branch unambiguous?

Flag (must-fix) when branching is described but the trigger condition is fuzzy ("if appropriate", "when relevant").

## Scope and composability

### J9 — Scope overlap with existing skills

List the skills in the same category folder. Read their descriptions. Does the new skill duplicate any of them?

Flag (suggest) when:
- Trigger phrases overlap >50% with an existing skill
- The description's `[What]` clause is interchangeable with a peer

When in doubt, ask the user during review: *"This trigger is very similar to `skill-X` in `(category)` — what's the real distinction?"* (Localize to PT-BR only if the chat is in PT-BR.)

### J10 — Skill respects other skills' territory

Flag (suggest) when:
- Skill says "I will handle X" where X is owned by another skill (e.g., posting to Jira when the `jira` skill exists)
- Skill recommends running commands that bypass an existing skill's workflow

### J11 — Naming consistency

Compare skill name to peers in the same category. Flag (suggest) when:
- Naming pattern is inconsistent (e.g., verb-noun in one, noun-noun in another)
- Naming uses different abbreviations than peers (`pr-review` vs `pull-request-review`)

## Progressive disclosure

### J12 — SKILL.md size discipline

Beyond the 500-line validator check:

- SKILL.md 400–500 lines with no references/ folder → flag (suggest) extracting reference material
- SKILL.md has long inline tables (>40 rows) → flag (suggest) moving to references

### J13 — Reference load-conditions are stated

For each file in `references/`, SKILL.md must say WHEN to load it. Otherwise the agent loads everything upfront, defeating progressive disclosure.

Flag (must-fix) when:
- A reference is named in SKILL.md but no load-condition is given
- Multiple references but SKILL.md says "load all references" (defeats the design)

## CKL-specific patterns

### J14 — Non-standard frontmatter fields

Flag (suggest) — NOT blocker per CKL review policy:
- `triggers:` field present
- `user-invocable:` field present
- Any other field outside `name | description | license | metadata`

Wording: *"Non-standard field `<field>`. Validator passes but spec doesn't include this. If intentional, add a comment justifying it; otherwise remove."*

### J15 — Description in mixed PT-BR/EN

CKL skills frequently mix PT-BR and EN. That's fine for content, but:

Flag (suggest) when:
- Description has trigger phrases ONLY in one language, but the team speaks both
- Skill name is in EN but description is 100% PT-BR (or vice versa) without trigger phrases bridging both

### J16 — Test phrases from CONTRIBUTING.md "Description Quality Standards"

Walk the table:

- [ ] Includes `Use when` with user-facing trigger phrases
- [ ] Includes `Do NOT use for` with negative triggers
- [ ] Under 1024 characters (validator)
- [ ] No XML brackets (validator)
- [ ] User perspective, not internal jargon

The first two are validator-checked for presence. Judgment checks the quality (see J2, J3).

The last bullet — "user perspective, not internal jargon" — is judgment-only. Flag (must-fix) phrases like "remediate CI pipeline failures" instead of "fix my build".

## Scripts and security (beyond snyk)

snyk-agent-scan covers security; these are quality checks on scripts:

### J17 — Scripts have shebang + set -euo pipefail

For shell scripts: missing `#!/usr/bin/env bash` or `set -euo pipefail` is a **must-fix** because failure modes become silent.

### J18 — Scripts validate their args

Flag (must-fix) when a script takes positional args but doesn't check `$#`.

### J19 — Scripts have usage line

Flag (suggest) when a script doesn't print usage on bad input or `-h`.

### J20 — Scripts assume PWD

Scripts should resolve paths relative to the script's own location or use `git rev-parse --show-toplevel`, not assume `pwd` is the repo root.

Flag (must-fix) when a script does `cat tools/something` without first cd-ing or resolving.

## YAML frontmatter pitfalls

### J21 — Unquoted `#` in description truncates YAML

**Bad smell:** description contains `#` followed by a non-`/` char (e.g., `"PR #42"`, `"issue #N"`, `"channel #engineering"`) and is NOT wrapped in quotes.

**Why it matters:** YAML treats `#` (when preceded by whitespace) as a start-of-comment marker. The description gets silently truncated at the `#`, and downstream checks (length, "Use when", "Do NOT use for") may pass against a *truncated* string while the file on disk still shows the full text. This is a particularly nasty bug because the file looks correct but the parser sees only half.

**Detection heuristic:**
- Read the frontmatter from disk.
- If the description value starts unquoted AND contains ` #` (space + hash) — flag.
- Cross-check: read what the YAML parser returns vs raw file. If lengths differ, you've hit this.

**Severity:** **must-fix** — silent truncation means the validator's other checks lied.

**Suggested fix:**
- Wrap the description in single quotes: `description: 'text with #N here'`
- Or remove the `#` from trigger phrases (use "PR 42" instead of "PR #42")
- Do NOT use YAML multiline operators (`>-`, `|`) — those violate the single-line rule.

**Real example seen in dogfood:**
First version of this skill itself had `"PR #N"` in the description, unquoted. YAML truncated the description at the `#`, the validator returned a description string ~50% of the actual content, and reported "Missing 'Do NOT use for...'" — even though it was present in the file. Quoted with single quotes; check passed. Logged here as a permanent lesson.

## allowed-tools frontmatter (least-authority and harness portability)

These checks apply to SKILL.md files that declare an `allowed-tools` list (the canonical Anthropic mechanism for pre-approving tool invocations without prompting). Origin: codified from real findings during PR review of `ckl-delivery:pr-review` in 2026-05-21 — the patterns recurred and were worth permanent rules.

### J22 — Dead allowed-tools entries

**Bad smell:** an entry in `allowed-tools:` that is never invoked anywhere in the SKILL.md body (or in scripts the SKILL.md says it'll call). Common shape: `Bash(echo:*)`, `Bash(wc:*)` or similar utility entries that look defensive but aren't actually used.

**Why it matters:** the whole point of a scoped allowlist is **least authority** — each entry is a permission grant that loosens the prompt-injection defense. Dead entries weaken the security argument while granting authority for nothing. Worse, future agents reading the SKILL.md may assume the grant is intentional and start using it.

**Detection heuristic:**
- For each `Bash(<cmd>:*)` entry in `allowed-tools`, grep the SKILL.md body and any `scripts/*` files for the bare command name. If zero matches anywhere → flag.
- Exception: commands that appear in anti-pattern / "do NOT do this" examples don't count as real usage.

**Severity:** suggest. Author may have intentional reason; let them confirm or remove.

**Suggested fix:** remove the entry, or add an inline comment in SKILL.md explaining why it's pre-approved despite not being invoked.

### J23 — Inconsistent narrowness across allowed-tools entries

**Bad smell:** some entries in `allowed-tools` are narrowed to subcommands (`Bash(npm run *)`, `Bash(npm test *)`) while others grant the whole CLI (`Bash(pnpm:*)`, `Bash(yarn:*)`). This is inconsistent within the same allowlist.

**Why it matters:** narrowing one tool but leaving its peers wide-open defeats the purpose. If the SKILL.md only ever runs `pnpm run test` and `pnpm install`, granting `Bash(pnpm:*)` allows `pnpm exec <anything>`, `pnpm dlx`, etc. The narrowness should be consistent across equivalent tools.

**Detection heuristic:**
- Group entries by base command (npm, pnpm, yarn, etc.).
- If any entry in the group is narrowed to subcommands, ALL peer entries should be narrowed similarly.
- Exception: commands whose subcommand surface is small enough that narrowing is impractical (e.g. `make`, `git`) — flag with lower confidence.

**Severity:** suggest.

**Suggested fix:** narrow the wide entries to match. Example: `Bash(pnpm:*)` → `Bash(pnpm run *), Bash(pnpm test *), Bash(pnpm install)`.

### J24 — Subagent-dispatch tool name varies by harness

**Bad smell:** SKILL.md acknowledges that the subagent-dispatch tool is named differently across harnesses (commonly `Task` in some Claude Code releases, `Agent` in others) but `allowed-tools` only lists one of the names.

**Why it matters:** the SKILL.md will fail with permission-prompt friction in the harness where the listed name doesn't match the actual tool name. The whole point of `allowed-tools` is **cross-harness pre-approval** — listing only one name defeats portability without granting extra capability (both names refer to the same operation).

**Detection heuristic:**
- Grep SKILL.md body for mentions of subagent dispatch tooling (`Task`, `Agent`, `subagent`, `dispatch`, `parallel agents`).
- If the body mentions both names OR explicitly says "may be called X in some harnesses" — check that BOTH appear in `allowed-tools`.

**Severity:** suggest.

**Suggested fix:** list both: `allowed-tools: [..., Task, Agent]`. No additional capability is granted — these are alternative names for the same operation.

## State-of-the-art 2026 (validated externally)

These checks were added based on Anthropic engineering team guidance and industry research published in 2026. Each cites its source so authors can verify the rule.

**Deliberately NOT codified (decision logged 2026-05-21):**

- **J26 (MCP wildcard narrowing)** — pattern is valid but team chose to NOT codify yet. Reasons: (a) would fire on most existing CKL skills using Atlassian/Slack MCP wildcards even when intentional, (b) calibration of first-party vs third-party MCPs needs more real-world data, (c) spec around `mcp__server__*` patterns is still consolidating in May 2026. Revisit when 3+ real PRs show wildcards being abused.
- **J28 (untrusted-input threat model docs)** — pattern is valid but team chose to NOT codify yet. Reasons: (a) risk-tier classification (HIGH/MEDIUM/LOW) requires the LLM to judge skill intent accurately, false-positive risk is real, (b) threat-modeling spec for skills is still imature, (c) `security-threat-model` skill exists as manual escalation path already documented in J27. Revisit when real-world incidents show prompt injection landing on a CKL skill.

### J25 — Mature skills must have a Gotchas section

**Bad smell:** SKILL.md has no `## Gotchas`, `## Common pitfalls`, `## Known issues`, or equivalent section despite the skill being non-trivial.

**Why it matters:** Anthropic engineering team explicitly recommends this section as *"the most valuable content in any skill"* and *"highest-signal"* — common failure modes specific to the domain, kept updated as new issues appear. Skills without it accumulate domain-specific bugs in a black box and re-introduce them.

**Detection heuristic:**
- Look for a heading containing "gotcha", "pitfall", "known issue", "common mistake", "troubleshoot" (case-insensitive).
- Skill is "mature" if: (a) version ≥ 1.0.0 in metadata, OR (b) git log shows ≥ 3 commits to the SKILL.md, OR (c) the skill is invoked from another skill (cross-skill dependency).

**Severity:**
- New skill (version 0.x, ≤ 2 commits): **suggest** ("Add a Gotchas section as the skill matures — track real failure modes there")
- Mature skill (criteria above): **must-fix**

**Suggested fix:** Add a `## Gotchas` section near the bottom of SKILL.md, structured as bullets describing failure modes the team has actually hit. Empty placeholder is acceptable for a new skill.

**Source:** [Anthropic skill authoring best practices](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/best-practices). Reinforced by Tort Mario (Anthropic engineer) Medium guide, April 2026.

### J27 — Skills using MCP servers must document the trust boundary

**Bad smell:** SKILL.md invokes MCP tools (e.g., `mcp__*` tool calls, references to "atlassian MCP", "slack MCP", etc.) but doesn't document: (a) WHICH server is required, (b) WHAT data flows through it, (c) WHAT happens when the MCP is unavailable/unauthenticated.

**Why it matters:** *"Every MCP connection is a trust boundary, and every trust boundary is an attack vector"* (Lasso Security, 2026). Anthropic's own testing shows prompt-injection success rates climb from 0% in pure coding to 1-5% with MCP/web/browser tools. Skills that depend silently on MCP servers fail unpredictably (no auth → cryptic errors) and create unaudited attack surface.

**Detection heuristic:**
- Grep SKILL.md for `mcp__`, "MCP server", "MCP tool", "via the X MCP", names of common MCPs (Atlassian, Slack, GitHub, Notion, etc.).
- If hits ≥ 1, check that SKILL.md has at least:
  - A pre-requisite line naming the MCP server explicitly
  - A "what data flows" sentence (e.g., "Reads ticket titles from Jira, never writes")
  - An "if MCP unavailable" branch in the workflow

**Severity:** **must-fix.** This is a security + reliability rule, not a nicety.

**Suggested fix:** Add a `## MCP dependencies` subsection under Pre-requisites with the three points above. Example:

```markdown
## MCP dependencies

- **Atlassian MCP** (required for Step 2). Reads ticket title and status; never writes.
- **If unavailable:** skill cannot proceed beyond Step 1. Surface the error and stop — do not fabricate ticket data.
```

**Source:** [Lasso Security on indirect prompt injection in Claude Code](https://www.lasso.security/blog/the-hidden-backdoor-in-claude-coding-assistant). [TrueFoundry enterprise prompt injection guide](https://www.truefoundry.com/blog/claude-code-prompt-injection). Anthropic's own measurements published in the security playbook.

**Escalation path:** for skills that depend on MCP servers handling genuinely sensitive data (credentials, PII, multi-tenant boundaries), recommend invoking `security-threat-model` skill separately for a formal threat model with explicit trust boundaries, assets, attacker capabilities, and abuse paths. That skill produces a markdown threat-model file; do NOT run it as part of skill-reviewer's default flow — it's a manual escalation when the maintainer judges the surface area justifies the cost.

### J29 — Parallel subagent dispatch requires preconditions in SKILL.md

**Bad smell:** SKILL.md describes a workflow that dispatches multiple subagents via the Task/Agent tool in parallel, but doesn't state the three preconditions Anthropic requires for legitimate parallel dispatch.

**Why it matters:** Anthropic's subagent docs specify three conditions that MUST all be true for parallel dispatch: (1) 3+ unrelated tasks or independent domains, (2) no shared state between tasks, (3) clear file boundaries with no overlap. Skills that dispatch in parallel without these conditions hit race conditions, lost results, or worse — silent data corruption when two subagents write the same file. The April 2026 update parallelized subagent + MCP init, which changed failure modes (a failed MCP init no longer blocks peer subagents — they proceed with stale or absent context).

**Detection heuristic:**
- Grep SKILL.md for: "parallel", "in parallel", "concurrent", "fan-out", "dispatch N", "Task tool" / "Agent tool" in proximity to "multiple" or numerical patterns ("6 agents", "N parallel").
- If parallel dispatch is described, verify SKILL.md states ALL three:
  - "Tasks are independent" / "no shared state" / equivalent
  - "Each task targets distinct files" / "no file overlap" / equivalent
  - "Minimum N tasks for parallelism" / acknowledgment of when sequential is better
- Also verify a **completion gate**: SKILL.md describes what happens when not all subagents return usable results (bounded retry, partial-mode honesty, fail-fast — pick one and state it).

**Severity:** **must-fix.** Race conditions in production are not theoretical — the agent-skills monorepo's own pr-review skill went through real bugs caught by reviewers on this exact axis.

**Suggested fix:** Add a `## Parallel dispatch preconditions` subsection where the parallel work is described. Three lines, plus completion gate behavior.

**Source:** [Create custom subagents — Claude Code Docs](https://code.claude.com/docs/en/sub-agents). [Sub-Agents Best Practices — claudefa.st](https://claudefa.st/blog/guide/agents/sub-agent-best-practices). [Claude Code Agents 2026 (CloudZero)](https://www.cloudzero.com/blog/claude-code-agents/) for the April 2026 init-parallelism update.

## Output discipline

Always cite the source of each rule in the report. **Use the human-readable label first, then the internal ID in parentheses** — so a non-engineer reading the comment doesn't have to decode the technical name:

- `(structural validator)` for things from the bundled `scripts/validate_skill.py`
- `(security scan)` for things from the bundled `scripts/security_sweep.sh`
- `(CKL contribution guide)` for things from the CKL CONTRIBUTING.md
- `(reviewer judgment — J<N>)` for things from this file
- `(recurring CKL pattern — R<N>)` for things from `ckl-recurring-issues.md`

The numeric ID stays in the label so engineers can grep and cross-reference; the prose around it carries the meaning for non-engineers (often PMs or designers writing their first skill).

In addition to the source label, include a **`Why it matters:`** one-line plain-language sentence pulled from `references/rule-explanations.md`. This is what makes the comment readable for someone whose first skill PR this is. Omit only when the rule name is genuinely self-explanatory (rare).

Without source attribution AND a Why line, the author can't push back if the rule is wrong, and the non-engineer audience can't understand what they did wrong. Always cite, always explain.
