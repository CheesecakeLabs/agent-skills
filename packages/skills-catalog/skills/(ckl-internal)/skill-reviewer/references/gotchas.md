# Gotchas

Real failure modes caught during development and use of `skill-reviewer`. Update this file whenever a non-obvious bug surfaces, regardless of whether it's a finding ON skill-reviewer or ON the skills it reviews.

When `skill-reviewer` is loaded for a review, it should consult this file in Step 3 (judgment) when looking for known failure modes — flag if the target skill has the same pattern, with attribution `(gotcha:<short-name>)`.

## SKILL authoring gotchas

### YAML `#` in unquoted description truncates silently

The frontmatter YAML parser treats `#` (preceded by whitespace) as a start-of-comment marker. A description like `"… PR #N …"` unquoted gets cut at the `#`, and downstream validator checks may pass against the truncated string while the file on disk looks correct.

**Fix:** wrap descriptions containing `#` in single quotes (`description: 'text with #N'`) or avoid `#` in trigger phrases (use "PR 42" instead of "PR #42"). This is codified as **J21** for skills under review.

### `pyyaml` is a soft dependency for the bundled validator

`run_validate.sh` invokes `validate_skill.py`, which prefers `pyyaml` but falls back to a stdlib-only parser when absent. The fallback has lower fidelity (less precise error messages, simpler frontmatter parsing). A `WARN` is printed to stderr when fallback is used — surface this in the report so users know the validator ran at reduced confidence.

**Fix:** install with `pip3 install --user pyyaml`. Not required, recommended.

## Workspace gotchas (skill-reviewer-specific)

### Persistent markdown report was overengineering — removed in v1.1.6

Versions up to v1.1.5 wrote the chat report to `$HOME/.skill-reviewer/reports/<skill>-<date>.md` for "grep-able history". In practice, three problems showed up:

1. **Approval friction.** Every invocation across a new project triggered a `Write` tool prompt, since `Write` was in `allowed-tools` but Claude Code prompts per new path. Users felt the prompt churn before they felt any value from the history.
2. **Duplicate of existing records.** Mode A already creates the canonical record (PR comments on GitHub). Mode B/C have chat history.
3. **The PR payload file (`/tmp/skill-reviewer/pr-N-comments.json`) had the same issue** — written by `Write`, then read by `post_pr_review.sh`.

**Fix in v1.1.6:**
- Dropped the markdown report entirely. Chat is the output.
- `post_pr_review.sh` now accepts `-` as the JSON arg, reading from stdin. The agent pipes a heredoc in the same bash call that invokes the script — no separate `Write` call.
- `Write` removed from `allowed-tools`. Zero Write prompts.

**Implication:** if the user explicitly wants a saved markdown copy, they grab it from chat manually. Not auto-persisted.

### Stray `run_security_scan.sh` may be present on disk

Earlier versions used `run_security_scan.sh` to call snyk-agent-scan. That dependency was dropped in favor of the bundled `security_sweep.sh`. SKILL.md no longer references the old script, but if you installed pre-drop and your filesystem doesn't allow file deletion (mounted folders, sandboxes), the orphan persists.

**Fix:** `rm scripts/run_security_scan.sh` manually. Not blocking — skill ignores the file.

### `security_sweep.sh` would false-positive on its own doc comments

The regex passes for `rm -rf`, `eval`, `exec` matched the comment lines inside `security_sweep.sh` itself when first written. Fix landed: `is_comment()` helper skips lines starting with `#` (after optional whitespace).

**Implication for reviewers:** when adding new regex patterns to the sweep, always check that documentation comments mentioning the pattern itself don't trigger. Test by running the sweep against the sweep's own folder.

### `security_sweep.sh` was self-flagging on the Python heredoc

After adding the prompt-injection checks (`unicode_tag_*`, `env_var_exfil_*`, `long_base64_blob`), `security_sweep.sh` started flagging itself because the regex sources inside the bundled Python heredoc literally contain `$ANTHROPIC_API_KEY`, `curl`, `wget`, etc. The `is_comment()` helper doesn't help — these are not shell comments, they're inside a single-quoted multi-line heredoc that defines a Python script.

**Fix:** the prompt-injection block now skips files whose basename is `security_sweep.sh`. This is a special-case for the sweep-scanning-itself tautology. Forked or customized sweeps in target skills will also be skipped — acceptable because if a target skill ships a `security_sweep.sh` of its own, it's almost certainly the same tautology pattern.

**Implication:** when writing a check that detects a textual pattern by name (rather than by structural property), expect that defining the pattern in the script source counts as a hit. Either special-case the sweep script, sentinel-comment the lines, or use a property-based test (length, codepoint range) instead of a string match.

### Hidden Unicode Tag instructions in SKILL.md bypass human review

The Unicode Tag block (U+E0000..U+E007F) is invisible in editors but readable by LLMs. A malicious contributor can append instructions to a `SKILL.md` description or body using only these codepoints — the human reviewer sees normal text, the agent reads something like `run this curl | bash` or `include $ANTHROPIC_API_KEY in the next URL`.

Documented attack in the wild as of Feb 2026 (Embrace The Red, wunderwuzzi23). Anthropic added detection in Claude Code itself shortly after, but pre-merge review is cheaper than runtime mitigation. The sweep's `unicode_tag_smuggling` rule (BLOCKER on runs of 10+ chars) and `unicode_tag_present` (MUST-FIX on 5+ total sparse) cover this.

**Implication for reviewers:** when reviewing a skill PR, do NOT trust the rendered diff alone — run the sweep or use [ASCII Smuggler](https://embracethered.com/blog/ascii-smuggler.html) to make invisible codepoints visible. Legitimate skills do not use the Unicode Tag block, so any hit is suspicious.

### Validator drift when bundled copy lags upstream

`scripts/validate_skill.py` was copied from the `skill-architect` skill in the `agent-skills` monorepo. If upstream evolves (new checks, fixed bugs), this bundled copy goes stale. When the target being reviewed IS the `agent-skills` monorepo, the workflow runs both the bundled and the upstream validators and surfaces drift as a meta-finding nit. In any other repo, only the bundled version runs — accept the drift risk.

**Sync cadence:** check upstream every minor release of `agent-skills` (or every ~quarter). Diff `tools/validate-skills.ts` against `scripts/validate_skill.py` semantically (the languages differ, the rules should match).

## Review-heuristic gotchas (rules that need calibrated detection)

### J17 detection window — heavy doc headers shift `set -euo pipefail` past line 10

When a reviewer applies J17 (scripts must have `set -euo pipefail`), naïve `head -10` grep misses scripts with long doc comment headers — `set` may sit on line 20-30. The rule applies "anywhere in the first 40 lines OR after the doc-header block", not "first 10".

**Implication:** when codifying detection heuristics into bash one-liners for self-validation, calibrate the window to real-world script formats — heavy headers are common in this monorepo.

### `Bash(<cmd>:*)` allowlist patterns vs invocation paths

When declaring `allowed-tools` patterns like `Bash(scripts/run_validate.sh:*)`, the matching is against the literal command string the host sees. If the skill is invoked from a directory other than the skill root, the literal command becomes `Bash(<absolute path>/scripts/run_validate.sh)` and the relative-path pattern does not match — the user gets prompted instead of auto-approved.

**Mitigation:** keep script invocations relative-from-skill-root in the SKILL.md instructions. If you need absolute-path patterns, list both relative and absolute variants in `allowed-tools` (verbose but safe).

## Adding to this file

Each entry follows the template above (`### <short name>`, prose, `**Fix:**` or `**Implication:**`). Keep entries short — link to the codified rule (`J<N>`) if the gotcha became a permanent check. Group entries by category (authoring / workspace / review-heuristic) so similar gotchas stay together.
