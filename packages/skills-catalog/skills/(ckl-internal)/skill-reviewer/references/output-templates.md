# Output Templates

Two output formats: the **chat report** (always) and the **PR comment draft** (only Mode A, only after user approval).

## Chat report template

Use this verbatim structure. The user reads this top-to-bottom — keep the executive summary tight.

```markdown
# Skill Review — <PR #N | path>

## Executive summary

| Severity | Count |
|---|---|
| 🔴 Blocker | N |
| 🟡 Must-fix | N |
| 🔵 Suggest | N |
| ⚪ Nit | N |

**Verdict:** <PASS | PASS WITH NOTES | BLOCK MERGE>
**Skills reviewed:** N → list paths
**Skipped:** <list any skipped check, e.g. "PR features (gh CLI missing)">

---

## 🔴 Blockers

### `<skill-path>/SKILL.md`:<line-or-blank>
**Rule:** <rule_name> *(human source label)*
**Why it matters:** <one-line plain-language explanation — see references/rule-explanations.md>
**Found:** <exact evidence — quote the offending line or describe the structural issue>
**Fix:** <concrete replacement, not vague advice. Include before/after example when the fix isn't obvious.>

(repeat per blocker)

---

## 🟡 Must-fix

(same shape)

---

## 🔵 Suggest

(same shape)

---

## ⚪ Nit

(same shape — keep these grouped, nits don't deserve individual headers)

```

**No "Saved to" footer.** Earlier versions ended the chat report with a path to a persisted markdown copy. v1.1.6 removed that — the chat IS the record. If the user wants a saved copy, they grab it from chat. The persistence was overengineering.

### Why this 4-line shape

The `Rule / Why it matters / Found / Fix` shape is calibrated for a mixed audience. CKL skills are increasingly authored by non-developers (product managers, designers experimenting with `skill-architect`), so the comment has to land both for a senior engineer and for someone whose first skill PR this is.

- **Rule** — gives the engineer the rule name to grep and the source label to push back on if needed.
- **Why it matters** — one plain-language sentence (10–25 words) explaining the consequence in product / human terms, not in jargon. Pulled from `references/rule-explanations.md`. Omit only if the rule name is already self-explanatory (e.g., `description_required`).
- **Found** — concrete evidence so neither audience has to hunt for what triggered the rule.
- **Fix** — actionable. When the fix isn't obvious (e.g., J21 YAML quoting, J24 dual-name `allowed-tools`), include a before/after snippet. When it's trivial (e.g., "rename folder"), one sentence is enough.

### Verdict rules

- 1+ blocker → **BLOCK MERGE**
- 0 blockers, 1+ must-fix → **PASS WITH NOTES** (author must address)
- 0 blockers, 0 must-fix → **PASS** (suggest/nit don't block)

### Source attribution

Always append the source in italics after the rule name. **Use the human-readable label first, then the internal ID in parens** — so a non-engineer reading the comment doesn't have to decode `judgment:J21` to understand where the rule came from:

| Internal source | Label to render in comment | What it means |
|---|---|---|
| Bundled validator | `*(structural validator)*` | The skill failed an automated structural check (frontmatter shape, file layout, naming). |
| Bundled security sweep | `*(security scan)*` | A regex pass flagged a security-sensitive pattern (secrets, eval, dangerous rm). |
| `references/judgment-checks.md` | `*(reviewer judgment — J<N>)*` | Quality / convention rule that needs human-style judgment, codified by CKL maintainers. |
| `references/ckl-recurring-issues.md` | `*(recurring CKL pattern — R<N>)*` | A pattern CKL kept catching in real reviews and chose to make permanent. |
| CKL CONTRIBUTING.md | `*(CKL contribution guide)*` | Convention from the canonical CKL skill contributing doc. |

The numeric ID stays in the label so engineers can still grep / cross-reference; the prose around it carries the meaning for non-engineers.

**Anti-pattern:** rendering bare `*(validator)*` or `*(judgment:J21)*` without the human prose. A product manager who just started writing skills will not know what either of those means — and the whole point of these labels is to tell them where to read more.

Without source attribution, the author can push back legitimately on any finding.

## PR comment payload (write proactively, post on single confirmation)

The chat report IS the draft. There is no separate "draft" step — write the structured PR payload at the same time the chat report is rendered. The user reads the chat report, says "posta", you post. One confirmation gate, not two.

### Posting model: 1 top-level summary + N TRUE inline comments

GitHub PRs have two comment surfaces:

1. **The Conversation tab** — top-level review summary (the "Files +X / -Y" overview, the executive verdict)
2. **The Files tab** — comments that sit on the actual diff lines, where reviewers naturally look

**Always use BOTH.** A single consolidated body in the Conversation tab is the wrong UX — reviewers and AI fix-agents can't focus on one finding at a time, and inline references become broken hyperlinks instead of anchored discussion threads.

The `post_pr_review.sh` script uses the GitHub REST API via `gh api repos/OWNER/REPO/pulls/N/reviews` directly (NOT `gh pr review`, which collapses everything into one body). Each finding with a `path` + `line` becomes a true inline comment; entries without `path` become the summary body.

### Payload shape

Compose the JSON payload **in memory only** — do NOT write it to a file. When the user confirms the post, pass the JSON to `post_pr_review.sh` via stdin (the `-` arg + heredoc inside a single bash call). The script reads stdin and creates its own temp file to work with, then cleans up on exit. From the agent harness's perspective there is no `Write` tool call, so no approval prompt.

Example payload that the agent composes mentally and then pipes to the script:

```json
[
  {
    "path": "plugins/foo/skills/bar/SKILL.md",
    "line": 5,
    "side": "RIGHT",
    "body": "**🔴 Blocker** — Rule: `name_not_reserved` *(structural validator)*\n\n**Why it matters:** The skill name appears in the file path and in user-facing trigger phrases. Using \"claude\" or \"anthropic\" implies an official endorsement and conflicts with reserved namespaces.\n\n**Found:** `name: anthropic-tracker`\n\n**Fix:** rename the skill and the folder. Example: `pr-tracker` or `release-tracker`."
  },
  {
    "path": "plugins/foo/skills/bar/SKILL.md",
    "line": 12,
    "side": "RIGHT",
    "body": "**🟡 Must-fix** — Rule: `description_has_negative_scope` *(structural validator)*\n\n**Why it matters:** Without a `Do NOT use for` clause, the agent can't tell which similar skill to delegate to instead — and ends up triggering yours when another would be the correct fit.\n\n**Found:** description ends after `Use when ...` with no negative-scope clause.\n\n**Fix:** add a closing sentence like `Do NOT use for X (use peer-skill-name instead).`"
  },
  {
    "body": "## Skill Reviewer — automated review\n\n**Verdict: BLOCK MERGE** (1 blocker, 1 must-fix)\n\nReviewed: 1 skill. See inline comments on the Files tab for each finding."
  }
]
```

Notes on shape:

- `path` + `line` REQUIRED for inline comments. Without them the entry becomes part of the summary body.
- `side` defaults to `"RIGHT"` (the new version of the file). Use `"LEFT"` only for findings on deleted lines.
- For multi-line findings, add `start_line` + `start_side`. The single-line `line` is the END of the range.
- The summary entry should always exist (top-level review needs a body) — if all findings are inline, generate one summary entry automatically with the verdict + counts.

### Where to put each severity

**Inline (Files tab):** every Blocker, Must-fix, and Suggest. Each one sits on its own line — reviewers click, address, mark resolved. That's the GitHub workflow.

**Top-level summary (Conversation tab):**
- Executive summary (verdict + counts per severity)
- Skipped checks (validator/scan unavailable reasons)
- The Notable strengths section (positives don't need to be inline)
- Recurring candidates section (proposed graduations, see SKILL.md Step 4b)

**Nits:** roll into ONE inline comment per file if numerous (5+), or one inline each if 1–4. Don't spam the Files tab with 30 typo comments.

### Common posting failures and recovery

| Symptom | Cause | Fix |
|---|---|---|
| `Pull request review thread line must be part of the diff` | The finding's path:line wasn't actually changed in the PR | Move that finding to the summary body, or use the right line that IS in the diff |
| `Pull request review thread path` rejected | File path uses pre-rename name | Use the post-rename path (gh API expects current names) |
| 502 from GitHub API | Transient | Retry once before falling back to a single-comment summary |
| `start_line` > `line` | Reverse range | Swap them in the payload |

### GitHub review event (always `COMMENT` by default)

The script always posts as `COMMENT` regardless of how many blockers are in the payload. **This is deliberate.** We tried mapping verdict to event automatically (BLOCK MERGE → `REQUEST_CHANGES`) and walked it back: `REQUEST_CHANGES` sticks on the PR until someone manually dismisses or re-approves the review. In a working loop where the reviewer runs once, the author fixes the issues, and nobody re-runs the skill, the "Changes requested" status stays glued to the PR forever — friction that outweighs the benefit of the auto-gate.

| Event | When the script uses it | What GitHub shows |
|---|---|---|
| `COMMENT` | Default for every review the skill posts | Neutral. Inline comments still land on the Files tab; the PR is not gated by this review. Nothing to dismiss later. |
| `REQUEST_CHANGES` | Only when `--event=request-changes` is passed explicitly | "Changes requested" badge. Branch protection rules can gate the merge. The reviewer must dismiss or re-approve to clear it. |
| `APPROVE` | Only when `--event=approve` is passed explicitly | Rubber-stamps the PR. Avoid — automation shouldn't carry the weight of a code-owner sign-off. |

The textual `Verdict: BLOCK MERGE` in the top-level summary still calls out blockers loudly. Humans reading the PR see the block recommendation; they just don't see the merge UI gated by the bot.

**When to override.** If the user explicitly says they want the merge gate (e.g., "posta como request-changes mesmo, é um blocker grave"), call the script with `--event=request-changes` and warn them that dismissal will be on their plate later. Don't auto-promote without explicit ask.

### The single confirmation

After the chat report (which mirrors the payload content), ask one question:

> *"Post this as a PR review via `gh api`? (N inline comments + 1 top-level summary)"*

On explicit yes:

```bash
scripts/post_pr_review.sh <pr-number> - --confirm <<'JSON'
[ ...the inline comments + summary array, exactly as in the chat report... ]
JSON
```

The `-` (single dash) tells the script to read JSON from stdin. The heredoc is part of the same bash call, so it matches the `Bash(scripts/post_pr_review.sh:*)` allowlist pattern with zero extra prompts. The script reads stdin into a temp file (cleaned up on exit) and proceeds normally. To override the GitHub review event, pass `--event=comment|request-changes|approve` after `--confirm`.

On "edit this first" or any iteration request: update the chat report AND the payload file, then re-ask the same question. Each iteration is still one question, not two.

The script refuses to run without `--confirm` by design. The chat confirmation is the human-facing gate; `--confirm` is the script-level belt.

### What you get back

The script prints inline-comment count, summary-presence, review ID, and review URL. Include these in the chat acknowledgement after posting:

> *"Posted: 5 inline + 1 summary. Review live at https://github.com/.../pull/N#pullrequestreview-12345"*

## Locale

**Default: English.** PR comments, payload JSON, and the chat report all use English by default. The repos this skill reviews are open-source / international — non-CKL contributors read the PRs, and English is the lingua franca.

- Headers: English (`Executive summary`, `Saved to`)
- Rule names + sources: English verbatim (`name_not_reserved`, `(validator)`)
- Suggestion prose: English, imperative, direct
- File paths and CLI commands: never localize

**Switch to Portuguese ONLY when:**

- The user invoking the skill writes their request 100% in Portuguese AND
- They explicitly say something like *"manda em português"*, *"comentário em ptbr"*, or *"resposta em português"*

In that case, switch the chat report to PT-BR but keep the **PR payload (the JSON piped to `post_pr_review.sh`) in English** — what gets posted to GitHub must stay English regardless of how you're talking to the user. The repo audience is international; the chat audience is one person.

If the user mixes PT-BR and EN in the same prompt (common with CKL folks), default to English — the bilingual chat-vs-payload split breaks down otherwise.

Example finding in final shape (PT-BR chat report — note the human source label and the Why line):

```markdown
### `packages/skills-catalog/skills/(quality)/foo/SKILL.md`:1
**Rule:** `name_not_reserved` *(structural validator)*
**Por que importa:** O nome aparece no path e nos triggers — usar "claude" ou "anthropic" sugere endosso oficial e conflita com namespaces reservados.
**Encontrado:** `name: anthropic-tracker`
**Correção:** Renomeia a skill e a pasta. Exemplo: `pr-tracker` ou `release-tracker`.
```

## Anti-patterns

Do NOT:

- Use 🎉 ✨ or other positive-vibe emojis. This is a review tool — neutral palette only.
- Group findings by file before grouping by severity. Severity wins so the human triages fast.
- Hide skipped checks. Always list what was NOT run, with the reason.
- Write summaries like "Great job!" or "Looks good overall". The report is mechanical — qualitative pats belong to the human reviewer.
- Round counts. If there's 1 blocker, say 1, not "a few issues".
