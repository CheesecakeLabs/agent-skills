#!/usr/bin/env bash
# pr_touched_skills.sh — list skill roots touched by a PR, layout-agnostic.
#
# Detects skill roots by walking the PR branch's git tree for SKILL.md
# ancestors. Works in ANY repo layout: agent-skills, ckl-ai-skills, single-
# skill repos, embedded apps/web/skills/<name>/, client repos with arbitrary
# structure — no path-pattern assumption is made.
#
# The caller is responsible for ensuring the PR branch is checked out before
# downstream scripts (validate, security_sweep) read the listed paths.
# Pass --checkout to do it here as a convenience.
#
# Usage:
#   pr_touched_skills.sh <pr-number-or-url>
#   pr_touched_skills.sh --checkout <pr-number-or-url>
#   pr_touched_skills.sh --checkout --force <pr-number-or-url>   # override dirty-tree refusal
#
# Output: one path per line.
#   - Same-repo (or --checkout used): absolute path prefixed by REPO_ROOT.
#   - Cross-repo without --checkout: PR-relative path (no local prefix), so the
#     caller doesn't mistake a non-existent local path for something downstream
#     can read. A `CROSS_REPO_NO_FILES_ON_DISK` marker is also printed to stderr.
# Exit:
#   0 = found N skills (printed)
#   1 = no SKILL.md found in the PR's tree, or no skill-related files changed
#   2 = usage / bad input
#   3 = gh missing
#   4 = gh API call failed
#   5 = --checkout requested but working tree is dirty (use --force to override)

set -euo pipefail

USE_CHECKOUT=0
FORCE=0
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --checkout) USE_CHECKOUT=1; shift ;;
    --force)    FORCE=1;        shift ;;
    --) shift; break ;;
    *)  echo "ERROR: unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [--checkout] [--force] <pr-number-or-url>" >&2
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
  if ! gh pr checkout "$PR_NUMBER" ${GH_REPO_FLAG[@]+"${GH_REPO_FLAG[@]}"} 2>/tmp/skill-reviewer-gh.err; then
    echo "ERROR: gh pr checkout failed:" >&2
    cat /tmp/skill-reviewer-gh.err >&2
    exit 4
  fi
fi

# Resolve PR head repo + branch for the git/trees query.
if ! PR_META="$(gh pr view "$PR_NUMBER" ${GH_REPO_FLAG[@]+"${GH_REPO_FLAG[@]}"} --json headRefName,headRepository,headRepositoryOwner 2>/tmp/skill-reviewer-gh.err)"; then
  echo "ERROR: gh pr view failed:" >&2
  cat /tmp/skill-reviewer-gh.err >&2
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
if ! CHANGED="$(gh pr diff "$PR_NUMBER" ${GH_REPO_FLAG[@]+"${GH_REPO_FLAG[@]}"} --name-only 2>/tmp/skill-reviewer-gh.err)"; then
  echo "ERROR: gh pr diff failed:" >&2
  cat /tmp/skill-reviewer-gh.err >&2
  exit 4
fi

if [[ -z "$CHANGED" ]]; then
  exit 1
fi

# Single API call: enumerate all SKILL.md files in the PR's branch tree.
if ! TREE_RESPONSE="$(gh api "repos/$OWNER/$REPO/git/trees/$BRANCH?recursive=1" 2>/tmp/skill-reviewer-gh.err)"; then
  echo "ERROR: gh api git/trees failed:" >&2
  cat /tmp/skill-reviewer-gh.err >&2
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
if [[ -n "$LOCAL_ORIGIN" ]] && ! echo "$LOCAL_ORIGIN" | grep -qiE "[/:]$PR_REPO_SLUG(\.git)?$"; then
  if [[ "$USE_CHECKOUT" -eq 1 ]]; then
    # User opted into bringing files local — paths are valid here.
    echo "INFO: --checkout brought $PR_REPO_SLUG's PR $PR_NUMBER into the local clone at $REPO_ROOT." >&2
  else
    CROSS_REPO_NO_FILES_ON_DISK=1
    echo "WARN: PR is in $PR_REPO_SLUG but local clone is $LOCAL_ORIGIN." >&2
    echo "WARN: emitting PR-relative paths (not local). To run validate/sweep, clone $PR_REPO_SLUG and re-run from there, or pass --checkout to bring this PR into the current clone." >&2
    echo "CROSS_REPO_NO_FILES_ON_DISK" >&2
  fi
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

# Emit one path per line. Cross-repo (no --checkout) → PR-relative, so the caller
# can tell at a glance it isn't pointing at local disk. Otherwise → absolute.
echo "$TOUCHED" | while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  if [[ "$CROSS_REPO_NO_FILES_ON_DISK" -eq 1 ]]; then
    echo "$rel"
  elif [[ "$rel" == "." ]]; then
    echo "$REPO_ROOT"
  else
    echo "$REPO_ROOT/$rel"
  fi
done
