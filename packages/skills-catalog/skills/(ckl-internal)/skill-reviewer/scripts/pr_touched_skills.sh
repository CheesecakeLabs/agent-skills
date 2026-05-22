#!/usr/bin/env bash
# Lists skill/plugin roots touched by a PR.
# Accepts a PR number (42, #42) or a GitHub PR URL (.../pull/42).
# Uses gh CLI; gracefully fails if gh is missing.
#
# Usage: pr_touched_skills.sh <pr-number-or-url>
# Output: one absolute path per line, deduped to skill roots
# Exit: 0 = found N skills (printed), 1 = no skills touched, 2 = usage, 3 = gh missing, 4 = gh failed

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <pr-number-or-url>" >&2
  exit 2
fi

RAW_INPUT="$1"

# Normalize input to a PR number
# Cases supported:
#   42                              → 42
#   #42                             → 42
#   PR 42                           → 42 (uncommon, but be permissive)
#   https://github.com/x/y/pull/42  → 42
#   https://github.com/x/y/pull/42#discussion-123 → 42
if [[ "$RAW_INPUT" =~ /pull/([0-9]+) ]]; then
  PR_NUMBER="${BASH_REMATCH[1]}"
elif [[ "$RAW_INPUT" =~ ^#?([0-9]+)$ ]]; then
  PR_NUMBER="${BASH_REMATCH[1]}"
elif [[ "$RAW_INPUT" =~ ([0-9]+) ]]; then
  PR_NUMBER="${BASH_REMATCH[1]}"
else
  echo "ERROR: could not extract PR number from input: $RAW_INPUT" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not installed" >&2
  exit 3
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Fetch changed files in the PR (filenames only)
if ! CHANGED="$(gh pr diff "$PR_NUMBER" --name-only 2>/tmp/skill-reviewer-gh.err)"; then
  echo "ERROR: gh pr diff failed:" >&2
  cat /tmp/skill-reviewer-gh.err >&2
  exit 4
fi

# Filter paths under skills-catalog or plugins/, then collapse to skill folder roots
#   packages/skills-catalog/skills/(cat)/name/SKILL.md      → packages/skills-catalog/skills/(cat)/name
#   packages/skills-catalog/skills/(cat)/name/scripts/x.sh  → packages/skills-catalog/skills/(cat)/name
#   plugins/foo/skills/bar/SKILL.md                         → plugins/foo/skills/bar
echo "$CHANGED" | awk '
  /^packages\/skills-catalog\/skills\/\([^/]+\)\/[^/]+\// {
    n = split($0, parts, "/")
    print parts[1]"/"parts[2]"/"parts[3]"/"parts[4]"/"parts[5]
  }
  /^plugins\/[^/]+\/skills\/[^/]+\// {
    n = split($0, parts, "/")
    print parts[1]"/"parts[2]"/"parts[3]"/"parts[4]
  }
' | sort -u | while read -r rel; do
  echo "$REPO_ROOT/$rel"
done

# If nothing was printed, exit 1 (caller distinguishes "no skill changes" from errors)
TOUCHED_COUNT="$(echo "$CHANGED" | awk '
  /^packages\/skills-catalog\/skills\/\([^/]+\)\/[^/]+\// { c++ }
  /^plugins\/[^/]+\/skills\/[^/]+\// { c++ }
  END { print c+0 }
')"

if [[ "$TOUCHED_COUNT" -eq 0 ]]; then
  exit 1
fi
