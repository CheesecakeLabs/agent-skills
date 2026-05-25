# Reviewer-specific gotchas

Workspace and orchestration gotchas specific to `skill-reviewer`. Universal authoring, security, and review-heuristic gotchas live in `references/gotchas.md` (a symlink to the shared `skill-quality` substrate, consumed by both `skill-architect` and `skill-reviewer`).

Update this file when a non-obvious failure mode surfaces that only applies to `skill-reviewer`'s own implementation — design history, allowed-tools quirks, orphan-script cleanup, and similar.

## Persistent markdown report was overengineering — removed in v1.1.6

Versions up to v1.1.5 wrote the chat report to `$HOME/.skill-reviewer/reports/<skill>-<date>.md` for "grep-able history". In practice, three problems showed up:

1. **Approval friction.** Every invocation across a new project triggered a `Write` tool prompt, since `Write` was in `allowed-tools` but Claude Code prompts per new path. Users felt the prompt churn before they felt any value from the history.
2. **Duplicate of existing records.** Mode A already creates the canonical record (PR comments on GitHub). Mode B/C have chat history.
3. **The PR payload file (`/tmp/skill-reviewer/pr-N-comments.json`) had the same issue** — written by `Write`, then read by `post_pr_review.sh`.

**Fix in v1.1.6:**
- Dropped the markdown report entirely. Chat is the output.
- `post_pr_review.sh` now accepts `-` as the JSON arg, reading from stdin. The agent pipes a heredoc in the same bash call that invokes the script — no separate `Write` call.
- `Write` removed from `allowed-tools`. Zero Write prompts.

**Implication:** if the user explicitly wants a saved markdown copy, they grab it from chat manually. Not auto-persisted.

## Stray `run_security_scan.sh` may be present on disk

Earlier versions used `run_security_scan.sh` to call snyk-agent-scan. That dependency was dropped in favor of the bundled `security_sweep.sh` (now living in the shared substrate). SKILL.md no longer references the old script, but if you installed pre-drop and your filesystem doesn't allow file deletion (mounted folders, sandboxes), the orphan persists.

**Fix:** `rm scripts/run_security_scan.sh` manually. Not blocking — skill ignores the file.

## State the skill writes to disk

What the skill creates on the user's machine, and what cleans it up:

| Source | What | Lifecycle |
|---|---|---|
| `scripts/post_pr_review.sh` | `mktemp` temp files (`skill-reviewer-stdin.*`, `skill-reviewer-repo.*`, `skill-reviewer-post.*`) for stdin payload, `gh` stderr capture, and API response | Tracked in a `CLEANUP_FILES` array, removed by `trap cleanup EXIT INT TERM` at the top of the script |
| `scripts/pr_touched_skills.sh` | `mktemp` temp file (`skill-reviewer-gh.*`) for `gh` stderr capture, reused across all `gh` invocations | Tracked in `CLEANUP_FILES`, same trap pattern |
| `scripts/pr_touched_skills.sh --checkout` | A local git branch via `gh pr checkout` | **Persistent by design.** The user opted into `--checkout` because they want the PR branch available for follow-up work. The script does NOT delete it. |
| `scripts/pr_touched_skills.sh --worktree` | A detached-HEAD git worktree at `${TMPDIR:-/tmp}/skill-reviewer-pr<N>` | **Persists across invocations.** The trap does NOT remove it because downstream `run_validate.sh` / `security_sweep.sh` need to read from it after `pr_touched_skills.sh` exits. Cleaned by the next invocation's startup sweep (>1h old). User can also `git worktree remove --force <path>` immediately — the script echoes that command to stderr on creation. |

No state under `$HOME` (the v1.1.5 `$HOME/.skill-reviewer/reports/` directory was removed in v1.1.6 — see the "Persistent markdown report" gotcha above).

If a future script adds a new temp file, push it onto the `CLEANUP_FILES` array (both scripts now use the same pattern). The shared `cleanup()` function removes everything in the array on `EXIT/INT/TERM`. Don't add fixed-path `/tmp/skill-reviewer-*` files — they leak across invocations and race when two reviews run concurrently.

### Cleanup-failure fallback

Two defensive mechanisms cover the case where the trap can't or didn't run cleanly:

1. **Logging on partial failure.** If `cleanup()` runs but `rm -f` returns non-zero for any file (rare — possible on shared filesystems with ACLs, immutable flags, etc.), the function logs the unremoved paths to stderr plus a copy-paste `rm -f <paths...>` command for manual cleanup. The user always knows where any lingering file is.

2. **Self-healing at next startup.** If the trap doesn't fire at all (SIGKILL, power loss, OOM kill), files linger. The next invocation of either script sweeps `${TMPDIR:-/tmp}` in two passes:
   - **Stale temp files** (`skill-reviewer-*`, file type) older than 1 hour → deleted via `find … -delete`.
   - **Stale worktree directories** (`skill-reviewer-pr*`, directory type) older than 1 hour → removed via `git worktree remove --force <path>` (cleans `.git/worktrees/` metadata) with `rm -rf` as fallback if the original repo is gone. A final `git worktree prune` cleans any lingering metadata.
   
   The 1h threshold is comfortably past any realistic single-run duration and avoids racing concurrent invocations. The worktree sweep is deliberately scoped to the documented prefix (`skill-reviewer-pr*`) — it will NOT touch arbitrary directories or worktrees the user created themselves.

This pairing handles every realistic failure mode: the trap covers normal exits + Ctrl-C + SIGTERM; the logging covers partial failures within the trap; the self-healing sweep covers trap bypass entirely. Beyond that (e.g., the user's `/tmp` permission changes mid-run), the log message tells them what to do manually.

## Adding to this file

Each entry follows `## <short name>` + prose + `**Fix:**` or `**Implication:**`. Keep entries short. Move an entry to `references/gotchas.md` (the shared substrate) if it generalizes to skill authoring or review beyond `skill-reviewer`'s own orchestration.
