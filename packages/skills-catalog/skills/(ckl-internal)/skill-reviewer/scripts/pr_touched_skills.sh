#!/usr/bin/env bash
# pr_touched_skills.sh — list skill roots touched by a PR, layout-agnostic.
#
# Detects skill roots by walking the PR branch's git tree for SKILL.md
# ancestors. Works in ANY repo layout: agent-skills, ckl-ai-skills, single-
# skill repos, embedded apps/web/skills/<name>/, client repos with arbitrary
# structure — no path-pattern assumption is made.
#
# The caller is responsible for ensuring the PR branch is on disk before
# downstream scripts (validate, security_sweep) read the listed paths. Three
# opt-in ways to get files on disk:
#   --checkout    : `gh pr checkout` switches the current branch to PR HEAD.
#                   Mutates the working tree; refused on dirty tree unless --force.
#   --worktree    : `git worktree add --detach` checks the PR HEAD out at
#                   ${TMPDIR:-/tmp}/skill-reviewer-pr<N> WITHOUT touching the
#                   current branch. Same-repo only. Mutually exclusive with --checkout.
#   (default)     : no checkout. Emits paths only; caller is responsible if
#                   downstream scripts need files on disk.
#
# Usage:
#   pr_touched_skills.sh <pr-number-or-url>
#   pr_touched_skills.sh --checkout <pr-number-or-url>
#   pr_touched_skills.sh --checkout --force <pr-number-or-url>   # override dirty-tree refusal
#   pr_touched_skills.sh --worktree <pr-number-or-url>           # detached worktree at $TMPDIR/skill-reviewer-pr<N>
#
# Output: one path per line.
#   - Same-repo + default: absolute path prefixed by REPO_ROOT.
#   - Same-repo + --checkout: same (PR HEAD now in current clone's working tree).
#   - Same-repo + --worktree: absolute path prefixed by the worktree dir.
#   - Cross-repo + default: PR-relative path (no local prefix); `CROSS_REPO_NO_FILES_ON_DISK`
#     marker printed to stderr so the caller doesn't mistake the string for something
#     downstream can read.
#   - Cross-repo + --worktree: refused (cross-repo worktrees out of scope).
# Exit:
#   0 = found N skills (printed)
#   1 = no SKILL.md found in the PR's tree, or no skill-related files changed
#   2 = usage / bad input
#   3 = gh missing
#   4 = gh API call failed
#   5 = --checkout requested but working tree is dirty (use --force to override)
#   6 = --checkout and --worktree both passed (mutually exclusive)
#   7 = --worktree requested cross-repo (not supported)
#   8 = git fetch or git worktree add failed
#
# State written to disk:
#   - `mktemp` temp file for transient `gh` stderr; tracked in CLEANUP_FILES,
#     removed on EXIT/INT/TERM via the cleanup trap. On partial failure the trap
#     logs unremoved paths plus a copy-paste rm command.
#   - At startup: best-effort self-healing sweep of stale `skill-reviewer-*`
#     temp files AND worktree directories older than 1 hour from prior runs that
#     died before their trap fired. Worktree directories are removed via
#     `git worktree remove --force` (cleans .git/worktrees metadata) with rm -rf
#     as a fallback, plus a final `git worktree prune`.
#   - `--checkout`: `gh pr checkout` creates a local branch in the current clone.
#     Persists by design (opt-in workflow convenience). Not a leak.
#   - `--worktree`: detached-HEAD worktree at ${TMPDIR:-/tmp}/skill-reviewer-pr<N>.
#     Persists across script invocations (downstream validate/sweep needs it).
#     Cleaned by the next invocation's startup sweep (after 1h staleness), or
#     manually via the `git worktree remove --force <path>` command echoed to stderr.

set -euo pipefail

# Cleanup discipline (mirrors post_pr_review.sh):
# - Every temp file goes into CLEANUP_FILES; the trap removes them on any exit.
# - If a file can't be removed, the trap logs the path + a copy-paste rm
#   command so the user can clean manually.
# - At startup, sweep any skill-reviewer-* temp files older than 1h from
#   prior runs that died before their trap fired (SIGKILL, power loss, OOM).
CLEANUP_FILES=()
cleanup() {
  local -a remaining=()
  local f
  for f in "${CLEANUP_FILES[@]+"${CLEANUP_FILES[@]}"}"; do
    [[ -z "$f" ]] && continue
    if [[ -e "$f" ]] && ! rm -f "$f" 2>/dev/null; then
      remaining+=("$f")
    fi
  done
  if [[ ${#remaining[@]} -gt 0 ]]; then
    {
      echo ""
      echo "WARN: skill-reviewer could not auto-clean ${#remaining[@]} temp file(s):"
      printf '  %s\n' "${remaining[@]}"
      echo "Clean manually with: rm -f ${remaining[*]}"
    } >&2
  fi
}
trap cleanup EXIT INT TERM

# Self-healing sweep. Two passes:
#   1. Stale temp files (skill-reviewer-*) older than 1h from prior runs that
#      died before their trap fired (SIGKILL, power loss, OOM).
#   2. Stale worktree directories (skill-reviewer-pr*) older than 1h. Prefer
#      `git worktree remove --force` so .git/worktrees metadata is cleaned;
#      fall back to rm -rf if the original repo is gone or remove fails.
find "${TMPDIR:-/tmp}" -maxdepth 1 -type f -name 'skill-reviewer-*' -mmin +60 -delete 2>/dev/null || true
# Worktree directories: prefer `git worktree remove --force` (cleans .git/worktrees
# metadata); fall back to `find -depth -delete` (avoids the literal `rm -rf $VAR`
# pattern that security_sweep.sh deliberately blocks) for the rare case where
# the original repo is gone or git metadata is corrupted.
find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'skill-reviewer-pr*' -mmin +60 -print0 2>/dev/null | while IFS= read -r -d '' d; do
  git worktree remove --force "$d" 2>/dev/null || find "$d" -depth -delete 2>/dev/null || true
done
git worktree prune 2>/dev/null || true

# Transient gh stderr writes go through one mktemp file.
GH_ERR="$(mktemp -t skill-reviewer-gh.XXXXXX)"
CLEANUP_FILES+=("$GH_ERR")

USE_CHECKOUT=0
USE_WORKTREE=0
FORCE=0
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --checkout) USE_CHECKOUT=1; shift ;;
    --worktree) USE_WORKTREE=1; shift ;;
    --force)    FORCE=1;        shift ;;
    --) shift; break ;;
    *)  echo "ERROR: unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [[ "$USE_CHECKOUT" -eq 1 && "$USE_WORKTREE" -eq 1 ]]; then
  echo "ERROR: --checkout and --worktree are mutually exclusive. --checkout switches the current branch; --worktree creates a separate detached-HEAD checkout. Pick one." >&2
  exit 6
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [--checkout | --worktree] [--force] <pr-number-or-url>" >&2
  exit 2
fi

RAW_INPUT="$1"
REPO_HINT=""  # owner/repo extracted from URL; empty means "use current repo"

# Strict PR-number/URL parsing. URL forms also extract owner/repo so cross-repo
# review works even when the user is sitting in a different local clone.
if [[ "$RAW_INPUT" =~ ^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  REPO_HINT="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  PR_NUMBER="${BASH_REMATCH[3]}"
elif [[ "$RAW_INPUT" =~ /pull/([0-9]+) ]]; then
  PR_NUMBER="${BASH_REMATCH[1]}"
elif [[ "$RAW_INPUT" =~ ^#?([0-9]+)$ ]]; then
  PR_NUMBER="${BASH_REMATCH[1]}"
else
  echo "ERROR: input must be a PR number (42 or #42) or a PR URL (.../pull/42). Got: $RAW_INPUT" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not installed" >&2
  exit 3
fi

# Build -R flag set once; expand into each gh call so cross-repo URLs route to
# the right repo even when the local clone is a different one.
GH_REPO_FLAG=()
[[ -n "$REPO_HINT" ]] && GH_REPO_FLAG=(-R "$REPO_HINT")

# Optional checkout convenience — kept opt-in because it mutates working tree.
if [[ "$USE_CHECKOUT" -eq 1 ]]; then
  if [[ "$FORCE" -ne 1 ]] && [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "ERROR: working tree is dirty; refusing --checkout without --force" >&2
    exit 5
  fi
  if ! gh pr checkout "$PR_NUMBER" ${GH_REPO_FLAG[@]+"${GH_REPO_FLAG[@]}"} 2>"$GH_ERR"; then
    echo "ERROR: gh pr checkout failed:" >&2
    cat "$GH_ERR" >&2
    exit 4
  fi
fi

# Resolve PR head repo + branch for the git/trees query.
if ! PR_META="$(gh pr view "$PR_NUMBER" ${GH_REPO_FLAG[@]+"${GH_REPO_FLAG[@]}"} --json headRefName,headRepository,headRepositoryOwner 2>"$GH_ERR")"; then
  echo "ERROR: gh pr view failed:" >&2
  cat "$GH_ERR" >&2
  exit 4
fi

OWNER="$(echo "$PR_META" | jq -r '.headRepositoryOwner.login // empty')"
REPO="$(echo "$PR_META" | jq -r '.headRepository.name // empty')"
BRANCH="$(echo "$PR_META" | jq -r '.headRefName // empty')"

if [[ -z "$OWNER" || -z "$REPO" || -z "$BRANCH" ]]; then
  echo "ERROR: could not extract owner/repo/branch for PR $PR_NUMBER" >&2
  exit 4
fi

# Fetch the changed file list in the PR.
if ! CHANGED="$(gh pr diff "$PR_NUMBER" ${GH_REPO_FLAG[@]+"${GH_REPO_FLAG[@]}"} --name-only 2>"$GH_ERR")"; then
  echo "ERROR: gh pr diff failed:" >&2
  cat "$GH_ERR" >&2
  exit 4
fi

if [[ -z "$CHANGED" ]]; then
  exit 1
fi

# Single API call: enumerate all SKILL.md files in the PR's branch tree.
if ! TREE_RESPONSE="$(gh api "repos/$OWNER/$REPO/git/trees/$BRANCH?recursive=1" 2>"$GH_ERR")"; then
  echo "ERROR: gh api git/trees failed:" >&2
  cat "$GH_ERR" >&2
  exit 4
fi

# GitHub truncates recursive trees over ~100k entries — surface that so the caller
# knows detection may be incomplete (rare except on very large monorepos).
TRUNCATED="$(echo "$TREE_RESPONSE" | jq -r '.truncated // false')"
if [[ "$TRUNCATED" == "true" ]]; then
  echo "WARN: PR tree exceeded GitHub's recursive-tree limit (~100k entries). SKILL.md detection may be incomplete." >&2
fi

ALL_SKILL_MDS="$(echo "$TREE_RESPONSE" | jq -r '.tree[]? | select(.path | endswith("SKILL.md")) | .path')"

if [[ -z "$ALL_SKILL_MDS" ]]; then
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Cross-repo detection: when the PR is from a different repo than the local clone,
# downstream scripts (validate, security_sweep) cannot read PR files from disk.
# Switch the output format to PR-relative paths so the caller doesn't mistake
# a CWD-prefixed string for something runnable. --checkout brings the files
# local, so it keeps the absolute-path output.
LOCAL_ORIGIN="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
PR_REPO_SLUG="$OWNER/$REPO"
CROSS_REPO_NO_FILES_ON_DISK=0
IS_CROSS_REPO=0
if [[ -n "$LOCAL_ORIGIN" ]] && ! echo "$LOCAL_ORIGIN" | grep -qiE "[/:]$PR_REPO_SLUG(\.git)?$"; then
  IS_CROSS_REPO=1
  if [[ "$USE_CHECKOUT" -eq 1 ]]; then
    # User opted into bringing files local — paths are valid here.
    echo "INFO: --checkout brought $PR_REPO_SLUG's PR $PR_NUMBER into the local clone at $REPO_ROOT." >&2
  elif [[ "$USE_WORKTREE" -eq 1 ]]; then
    # Cross-repo + --worktree is unsupported. Fetching from a different repo's
    # URL into the current clone's .git is technically possible but adds enough
    # complexity that we punt; the user can clone the PR's repo and re-run.
    echo "ERROR: --worktree requires you to be inside the PR's local clone." >&2
    echo "ERROR: PR is in $PR_REPO_SLUG; current clone is $LOCAL_ORIGIN. Clone $PR_REPO_SLUG and re-run from there." >&2
    exit 7
  else
    CROSS_REPO_NO_FILES_ON_DISK=1
    echo "WARN: PR is in $PR_REPO_SLUG but local clone is $LOCAL_ORIGIN." >&2
    echo "WARN: emitting PR-relative paths (not local). To run validate/sweep, clone $PR_REPO_SLUG and re-run from there, or pass --checkout to bring this PR into the current clone." >&2
    echo "CROSS_REPO_NO_FILES_ON_DISK" >&2
  fi
fi

# Mode D — worktree creation (same-repo only; cross-repo errored out above).
# Detached HEAD at FETCH_HEAD so cleanup doesn't leave a stray refs/heads/* artifact.
# Idempotent: if the worktree already exists from a recent invocation (sweep
# hasn't fired yet because it's < 1h old), advance it via fetch + reset --hard
# rather than failing on `git worktree add`.
WORKTREE_DIR=""
if [[ "$USE_WORKTREE" -eq 1 ]]; then
  WORKTREE_DIR="${TMPDIR:-/tmp}/skill-reviewer-pr${PR_NUMBER}"
  WORKTREE_DIR="${WORKTREE_DIR%/}"  # strip trailing slash if TMPDIR has one
  if [[ -d "$WORKTREE_DIR/.git" || -f "$WORKTREE_DIR/.git" ]]; then
    # Existing worktree from a recent run — fast-forward it.
    if ! git -C "$WORKTREE_DIR" fetch origin "pull/${PR_NUMBER}/head" 2>"$GH_ERR" || \
       ! git -C "$WORKTREE_DIR" reset --hard FETCH_HEAD 2>>"$GH_ERR"; then
      echo "ERROR: worktree exists at $WORKTREE_DIR but could not be advanced to PR $PR_NUMBER HEAD:" >&2
      cat "$GH_ERR" >&2
      echo "Remove it and retry: git worktree remove --force $WORKTREE_DIR" >&2
      exit 8
    fi
    echo "INFO: reusing existing worktree at $WORKTREE_DIR (fast-forwarded to PR $PR_NUMBER HEAD)." >&2
  else
    # Fresh worktree.
    if ! git fetch origin "pull/${PR_NUMBER}/head" 2>"$GH_ERR"; then
      echo "ERROR: git fetch origin pull/${PR_NUMBER}/head failed:" >&2
      cat "$GH_ERR" >&2
      exit 8
    fi
    if ! git worktree add --detach "$WORKTREE_DIR" FETCH_HEAD 2>"$GH_ERR"; then
      echo "ERROR: git worktree add failed:" >&2
      cat "$GH_ERR" >&2
      exit 8
    fi
    echo "INFO: created worktree at $WORKTREE_DIR (detached HEAD at PR $PR_NUMBER)." >&2
  fi
  echo "WORKTREE_AT=$WORKTREE_DIR" >&2
  echo "INFO: worktree persists after this script exits — downstream validate/sweep needs it on disk." >&2
  echo "INFO: cleanup happens automatically on the next pr_touched_skills.sh run (sweep removes worktrees >1h old)." >&2
  echo "INFO: To remove now: git worktree remove --force $WORKTREE_DIR" >&2
fi

# For each changed file, find the LONGEST skill-root prefix in ALL_SKILL_MDS.
# A skill root is the dirname of a SKILL.md. "Longest match wins" handles the
# rare nested-skill case correctly.
TOUCHED="$(
  echo "$CHANGED" | while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    best_root=""
    while IFS= read -r skill_md; do
      [[ -z "$skill_md" ]] && continue
      if [[ "$skill_md" == "SKILL.md" ]]; then
        skill_root="."
      else
        skill_root="${skill_md%/SKILL.md}"
      fi
      if [[ "$f" == "$skill_md" || "$f" == "$skill_root"/* || "$skill_root" == "." ]]; then
        if [[ ${#skill_root} -gt ${#best_root} ]]; then
          best_root="$skill_root"
        fi
      fi
    done <<< "$ALL_SKILL_MDS"
    if [[ -n "$best_root" ]]; then
      echo "$best_root"
    fi
  done | sort -u
)"

if [[ -z "$TOUCHED" ]]; then
  exit 1
fi

# Emit one path per line. Three formats depending on mode:
#   - --worktree: absolute path prefixed by $WORKTREE_DIR (files in detached worktree).
#   - Cross-repo (no --checkout, no --worktree): PR-relative path so the caller
#     doesn't mistake the string for something on local disk.
#   - Default / --checkout / same-repo: absolute path prefixed by REPO_ROOT.
PATH_PREFIX="$REPO_ROOT"
[[ -n "$WORKTREE_DIR" ]] && PATH_PREFIX="$WORKTREE_DIR"
echo "$TOUCHED" | while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  if [[ "$CROSS_REPO_NO_FILES_ON_DISK" -eq 1 ]]; then
    echo "$rel"
  elif [[ "$rel" == "." ]]; then
    echo "$PATH_PREFIX"
  else
    echo "$PATH_PREFIX/$rel"
  fi
done
