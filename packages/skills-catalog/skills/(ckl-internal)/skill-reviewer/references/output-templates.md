# Output Templates

Two output formats: the **chat report** (always) and the **PR comment draft** (only Mode A, only after user approval).

## Chat report template

Use this verbatim structure. The user reads this top-to-bottom — keep the executive summary tight.

```markdown
# 🔍 Skill Reviewer — <PR #N | path>

<VERDICT-EMOJI> **<PASS | PASS WITH NOTES | BLOCK MERGE>** — `<skill-path>`: <one-line tally>

| Check | Result |
|---|---|
| Structural validator | <✅ X/X | ⚠️ X/Y (Z warn) | ❌ X failed> |
| Security sweep | <✅ 0 findings | ⚠️ N findings | 🔴 N findings (M blockers)> |
| 🔴 Blocker | N |
| 🟡 Must-fix | N |
| 🔵 Suggest | N |
| ⚪ Nit | N |

_Skipped: <reason>._  *(only when something was actually skipped — omit the line entirely otherwise; the gates rows already prove what ran)*

---

## 🔴 Blockers

### `<skill-path>/SKILL.md`:<line-or-blank>
**Rule:** <rule_name> *(human source label)*
**Why it matters:** <one-line plain-language explanation — see references/rules.md (judgment Why lines) / output-templates.md §Why-line lookup tables (validator + security)>
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
- **Why it matters** — one plain-language sentence (10–25 words) explaining the consequence in product / human terms, not in jargon. Pulled from `references/rules.md (judgment Why lines) / output-templates.md §Why-line lookup tables (validator + security)`. Omit only if the rule name is already self-explanatory (e.g., `description_required`).
- **Found** — concrete evidence so neither audience has to hunt for what triggered the rule.
- **Fix** — actionable. When the fix isn't obvious (e.g., J21 YAML quoting, J24 dual-name `allowed-tools`), include a before/after snippet. When it's trivial (e.g., "rename folder"), one sentence is enough.

### Verdict rules

| Counts | Verdict | Emoji |
|---|---|---|
| 1+ blocker | **BLOCK MERGE** | 🔴 |
| 0 blockers, 1+ must-fix | **PASS WITH NOTES** (author must address) | 🟡 |
| 0 blockers, 0 must-fix | **PASS** (suggest/nit don't block) | 🟢 |

The emoji is part of the rendered verdict line — pinning it to the count tier keeps every review visually consistent at the top.

### Gate-cell phrasing

The gates rows are the determinism signal. Phrasing is fixed by check + outcome:

| Check | Outcome | Cell |
|---|---|---|
| Structural validator | all passed | `✅ X/X` (e.g. `✅ 27/27`) |
| Structural validator | partial, with warnings | `⚠️ X/Y (Z warn)` (X passed of Y total, Z soft warnings) |
| Structural validator | any failed | `❌ X failed` (followed by inline-comment findings on the Files tab) |
| Security sweep | clean | `✅ 0 findings` |
| Security sweep | findings, no blockers | `⚠️ N findings` |
| Security sweep | findings include blockers | `🔴 N findings (M blockers)` |

Always show the counts numerically — re-reviews are easier to scan when the deltas are visible (e.g., `✅ 27/27` → `❌ 2 failed` between runs is unambiguous).

### Source attribution

Always append the source in italics after the rule name. **Use the human-readable label first, then the internal ID in parens** — so a non-engineer reading the comment doesn't have to decode `judgment:J21` to understand where the rule came from:

| Internal source | Label to render in comment | What it means |
|---|---|---|
| Bundled validator | `*(structural validator)*` | The skill failed an automated structural check (frontmatter shape, file layout, naming). |
| Bundled security sweep | `*(security scan)*` | A regex pass flagged a security-sensitive pattern (secrets, eval, dangerous rm). |
| `references/rules.md` | `*(reviewer judgment — J<N>)*` | Quality / convention rule that needs human-style judgment, codified by CKL maintainers. |
| `references/ckl-recurring-issues.md` | `*(recurring CKL pattern — R<N>)*` | A pattern CKL kept catching in real reviews and chose to make permanent. |
| CKL CONTRIBUTING.md | `*(CKL contribution guide)*` | Convention from the canonical CKL skill contributing doc. |

The numeric ID stays in the label so engineers can still grep / cross-reference; the prose around it carries the meaning for non-engineers.

**Anti-pattern:** rendering bare `*(validator)*` or `*(judgment:J21)*` without the human prose. A product manager who just started writing skills will not know what either of those means — and the whole point of these labels is to tell them where to read more.

Without source attribution, the author can push back legitimately on any finding.

## PR comment payload (write proactively, post on single confirmation)

The chat report IS the draft. There is no separate "draft" step — write the structured PR payload at the same time the chat report is rendered. The user reads the chat report, says "posta", you post. One confirmation gate, not two.

### PR top-level summary template (canonical)

The summary entry in the PR payload — the one without `path`+`line` that becomes the top-level review body — is always exactly this shape, regardless of skill, regardless of run:

```markdown
# 🔍 Skill Reviewer

<VERDICT-EMOJI> **<PASS | PASS WITH NOTES | BLOCK MERGE>** — `<skill-path>`: <one-line tally>

| Check | Result |
|---|---|
| Structural validator | <✅ X/X | ⚠️ X/Y (Z warn) | ❌ X failed> |
| Security sweep | <✅ 0 findings | ⚠️ N findings | 🔴 N findings (M blockers)> |
| 🔴 Blocker | N |
| 🟡 Must-fix | N |
| 🔵 Suggest | N |
| ⚪ Nit | N |

_Skipped: <reason>._
```

This is the chat report's executive header verbatim — the chat report extends it with per-finding sections below (🔴 Blockers / 🟡 Must-fix / 🔵 Suggest / ⚪ Nit), but the PR summary stops here because per-finding details belong on the Files tab as inline comments.

**Rules:**

- Render the verdict line with the **emoji from the verdict-rules table above** — not the one your chat-report mood suggests.
- The unified table has **6 rows always**: two gates + four severities. Don't split into two tables.
- The `_Skipped:_` line is **asymmetric** — render only when something was actually skipped (`gh CLI missing — PR features disabled`, `pyyaml absent — validator fell back to stdlib parser`). When nothing was skipped, omit the line entirely; the gates rows showing ✅ already prove what ran.
- For **multi-skill reviews** (N > 1, rare for this skill), the verdict line becomes a bullet list — one bullet per skill with its individual tally — and the unified table aggregates across all skills:

  ```markdown
  <VERDICT-EMOJI> **<verdict>** — <N> skills:
  - `<path-a>`: 1 blocker, 2 must-fix
  - `<path-b>`: 0 blockers, 1 must-fix
  ```

**Intentionally NOT in the summary** (GitHub's review UI already shows them, so duplicating is noise):

- Commit SHA being reviewed (GitHub shows it above every review)
- Timestamp (GitHub shows it above every review)
- "See inline comments on the Files tab" prose pointer (GitHub shows the inline count + Files tab natively)
- Any "Skills reviewed: 1" line when N=1 (the verdict line already names the path)
- Any positive-vibe section ("Notable strengths") — anti-pattern per the list at the bottom of this file

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
    "body": "# 🔍 Skill Reviewer\n\n🔴 **BLOCK MERGE** — `plugins/foo/skills/bar`: 1 blocker, 1 must-fix\n\n| Check | Result |\n|---|---|\n| Structural validator | ❌ 1 failed |\n| Security sweep | ✅ 0 findings |\n| 🔴 Blocker | 1 |\n| 🟡 Must-fix | 1 |\n| 🔵 Suggest | 0 |\n| ⚪ Nit | 0 |"
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
- Pad the PR summary with commit SHA, timestamp, or "where to look on the Files tab" prose pointers — GitHub's review UI shows that natively above every review. Adding it to the body is noise.
- Render two separate tables (one for gates, one for severities) in the PR summary — the canonical template fuses them into one 6-row scoreboard. Two adjacent small tables read as over-structure.
- Improvise the verdict-line emoji per run. The verdict-rules table fixes the mapping: 🔴 BLOCK MERGE, 🟡 PASS WITH NOTES, 🟢 PASS. Pick from there, not from your chat-report mood.
- Hide skipped checks. Always list what was NOT run, with the reason.
- Write summaries like "Great job!" or "Looks good overall". The report is mechanical — qualitative pats belong to the human reviewer.
- Round counts. If there's 1 blocker, say 1, not "a few issues".

---

## Why-line lookup tables (for deterministic findings)

When composing a PR comment for a validator-rule or security-sweep finding, copy the matching **Why it matters** sentence verbatim. Judgment-rule Why lines live inline next to each `J<N>` in `references/rules.md`; recurring-rule Why lines live inline next to each `R<N>` in `references/ckl-recurring-issues.md` — do NOT duplicate them here.

**Length guideline:** 10–25 words per line. One sentence. No hedging.

### Structural validator (`scripts/validate_skill.py`)

| Rule name | Why it matters |
|---|---|
| `name_required` | Without a `name`, no agent or harness can resolve which skill to invoke when triggers match. |
| `name_kebab_case` | Kebab-case is the spec convention. Mixed casing breaks slash-command invocation and file-path matching across harnesses. |
| `name_not_reserved` | The name appears in the file path and in user-facing triggers. Using "claude" or "anthropic" implies official endorsement and conflicts with reserved namespaces. |
| `name_matches_folder` | The harness assumes the folder name equals the skill's `name` field. A mismatch hides the skill from discovery or loads the wrong one. |
| `description_required` | Without a description, the agent has nothing to match against the user's request — the skill will never be triggered. |
| `description_under_1024_chars` | Anthropic's spec hard-caps description at 1024 characters. Past that, the description is truncated server-side and the cut-off section is invisible to matching logic. |
| `description_no_xml_brackets` | Angle brackets (`<` and `>`) inside the description break the YAML/markdown parser and can be misread as XML tags by downstream tools. |
| `description_has_use_when` | The `Use when ...` clause tells the agent the specific triggers (user phrases, contexts) that should activate this skill. Without it, matching is guesswork. |
| `description_has_negative_scope` | Without a `Do NOT use for ...` clause, the agent can't tell which similar skill to delegate to instead — and ends up triggering yours when another would be the correct fit. |
| `license_required` | Skills get shared and forked. A missing license blocks adoption in compliance-gated repos and creates ambiguity about reuse rights. |
| `frontmatter_parse_error` | The YAML at the top of the file did not parse. Every downstream check (name, description, license) is meaningless until this is fixed. |
| `skill_md_under_500_lines` | A SKILL.md over 500 lines loads in full every invocation. Move deep material into `references/` so it loads only when needed (progressive disclosure). |
| `no_readme_in_skill_folder` | A `README.md` next to `SKILL.md` confuses tooling that scans for the skill entrypoint and bloats the load. SKILL.md should be the only top-level doc. |
| `references_dir_organization` | `references/` should contain only files referenced from SKILL.md with explicit load conditions. Orphans load nothing and clutter discovery. |
| `scripts_dir_organization` | Scripts should sit under `scripts/`, named after what they do, invoked relative to the skill root. Other layouts break the harness's allowlist matching. |

### Security sweep (`scripts/security_sweep.sh`)

| Rule name | Why it matters |
|---|---|
| `hardcoded_secret` | A literal token, API key, or password in a skill file leaks every time the skill is shared, forked, or pushed to a public repo. |
| `eval_or_exec_on_dynamic_input` | Running `eval` or `exec` on agent-provided text turns a prompt-injection vulnerability into arbitrary code execution. |
| `dangerous_rm_rf` | A wide `rm -rf` (especially with variables that may be empty) can wipe the user's working tree, home directory, or worse. |
| `outbound_network_call` | A skill that reaches the network silently can exfiltrate data the user did not consent to share. Networking should be explicit in the workflow. |
| `path_traversal` | Unsanitized path components (`../foo`) let a malicious input read or write files outside the intended directory. |
| `unscoped_bash_allowlist` | `Bash(*)` in `allowed-tools` grants the agent permission to run any shell command without prompting. This defeats the least-authority principle. |
| `mcp_uuid_hardcoded` | An MCP tool referenced by UUID is bound to one machine's MCP install ID and won't activate on any other dev's laptop. Use the named-server form. |
| `unicode_tag_smuggling` | A run of invisible Unicode Tag codepoints (U+E0000..U+E007F) carries instructions the LLM reads but a human reviewer cannot see — a documented backdoor technique. |
| `unicode_tag_present` | A handful of Unicode Tag codepoints is unusual and worth a manual look — emojis do not use this codepoint block, so even sparse counts are suspect. |
| `excessive_zero_width` | Zero-width characters above the noise floor suggest obfuscation: hidden text or invisible instructions stuffed between visible content. |
| `long_base64_blob` | A long base64-shaped token inside instructions is a classic obfuscation pattern — usually decoded and piped to a shell, hiding the real payload from review. |
| `env_var_exfil_same_line` | A credential variable reference on the same line as a network call is the canonical exfiltration shape — the secret leaves the machine immediately. |
| `env_var_exfil_proximity` | A credential reference within a few lines of a network call is structurally suspicious — even when the link isn't direct, this is the pattern malicious skills use to drain secrets. |
| `var_in_url_query` | An env var embedded in a URL query string (`?token=$VAR`) leaks the secret to URL logs, browser history, and caches. Pass credentials in headers or request body instead. |
| `homoglyph_mixed_script` | A word that mixes Latin with Cyrillic or Greek codepoints is a visual spoof. Attackers use this to register near-identical skill names that look trustworthy. |
| `crypto_cred_reference` | A reference to a wallet mnemonic, private-key env var, exchange API key, or wallet file path has no legitimate place in a typical skill — and CKL developers run skills inside crypto-client repos, where this would be a direct hit. **Conditional severity:** BLOCKER for non-blockchain skills, demoted to SUGGEST when the skill self-declares as blockchain domain. |
| `eth_private_key_literal` | A literal `0x` + 64 hex chars matches the Ethereum private key format. A skill should never embed a wallet private key inline. |
| `btc_private_key_literal` | A token matching the Bitcoin WIF format (`[5KL]` + base58, 51–52 chars) has no innocent explanation in a skill file. |
| `fetch_and_execute` | `curl ... \| sh` pipes remote content into a shell — the skill is running code it has not seen. Classic supply-chain shape. |
| `silent_dependency_install` | A script that runs `npm i` / `pip install` / `brew install` without explicit user confirmation mutates the environment without consent. |
| `hardcoded_user_path` | `/Users/<name>/...` or `/home/<name>/...` breaks portability. Use `$HOME`, `~`, or computed paths. |
| `hardcoded_credential_path` | A hardcoded path under `~/.ssh`, `~/.aws`, `~/.config/gh`, etc. is either a credential leak or an attempt to read someone else's creds. |
| `stale_model_id` | References to retired Claude families (`claude-2`, `claude-3-*`, `claude-instant`) will fail at runtime once Anthropic removes them. |
| `persistence_command` | `crontab`, `systemctl enable`, and `launchctl load` install code that re-triggers after the session ends. For a CKL dev whose laptop aggregates multiple client environments, a persistent backdoor compromises every client they touch. |
| `persistence_write` | Writing to `~/.bashrc`, `~/.zshrc`, `~/.ssh/authorized_keys`, `/etc/cron.*`, or `~/Library/LaunchAgents/` installs persistent code or trust outside the current session. |

### Maintenance

When a new validator or security rule lands, add its Why line here in the same commit. The Why line must always reflect the *current* reason, not the historical one — if a spec changes, update both the rule and its Why line atomically.
