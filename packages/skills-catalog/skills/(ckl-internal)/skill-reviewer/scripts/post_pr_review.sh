#!/usr/bin/env bash
# Posts a PR review with TRUE inline comments + one top-level summary.
# Uses the GitHub REST API via `gh api` so inline comments sit on the actual
# diff lines (the Files tab), not collapsed into one PR-level comment.
#
# REFUSES to run without --confirm. The human must explicitly confirm.
#
# Usage:
#   post_pr_review.sh <pr-number> <comments-json-file-or-dash> --confirm [--event=MODE]
#
# The second arg is either a path to a JSON file OR `-` (a single dash) meaning
# "read JSON from stdin". The stdin form is preferred because it avoids a
# separate Write tool call in the agent harness — the agent can pipe a heredoc
# in the same bash command that invokes this script.
#
# Example (stdin via heredoc):
#   scripts/post_pr_review.sh 42 - --confirm <<'JSON'
#   [ { "path": "...", "line": 5, "body": "..." }, { "body": "summary" } ]
#   JSON
#
# --event=MODE controls the GitHub review event:
#   comment          (default) Neutral review. Inline comments still post; no
#                    merge gate; nothing to dismiss afterwards. This is the
#                    default by design — REQUEST_CHANGES was tried and removed
#                    because the manual dismissal step it requires creates
#                    unacceptable friction in the review loop.
#   request-changes  Explicit opt-in. Blocks merge under branch protection AND
#                    sticks until someone dismisses or re-approves the review.
#                    Use only when you actually want that gate.
#   approve          Explicit opt-in. Rare — only when the user wants the bot
#                    to carry a code-owner-style sign-off (usually they don't).
#
# The comments JSON file must be a flat array where:
#   - Entries WITH `path` + `line` become inline comments anchored to the diff
#   - Entries WITHOUT `path`/`line` are concatenated into the review body
#
# Required fields per inline entry:
#   { "path": "src/foo.ts", "line": 42, "body": "..." }
#
# Optional fields per inline entry:
#   "side":       "RIGHT" (default) or "LEFT"
#   "start_line": for multi-line comments (must pair with "start_side")
#   "start_side": "RIGHT" or "LEFT"
#
# Top-level entry shape (one or many — they get joined):
#   { "body": "..." }
#
# Exit codes:
#   0 = posted, 2 = usage error, 3 = missing --confirm,
#   4 = gh missing, 5 = jq missing, 6 = github api failed, 7 = no comments at all,
#   8 = bad --event value
#
# State written to disk:
#   - All transient temp files use `mktemp` and are tracked in CLEANUP_FILES,
#     removed on EXIT/INT/TERM via the cleanup trap below. No fixed-path files.

set -euo pipefail

# Track every temp file created so the cleanup trap can remove them on any
# exit (normal, error, signal). Add new temp paths with CLEANUP_FILES+=("$path").
CLEANUP_FILES=()
cleanup() {
  for f in "${CLEANUP_FILES[@]+"${CLEANUP_FILES[@]}"}"; do
    [[ -n "$f" ]] && rm -f "$f"
  done
}
trap cleanup EXIT INT TERM

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <pr-number> <comments-json-file> --confirm [--event=comment|request-changes|approve]" >&2
  exit 2
fi

PR_NUMBER="$1"
COMMENTS_FILE="$2"
CONFIRM_FLAG="$3"
shift 3

if [[ "$CONFIRM_FLAG" != "--confirm" ]]; then
  echo "REFUSED: missing --confirm flag. Review the draft first, then re-run with --confirm." >&2
  exit 3
fi

# Parse optional flags after --confirm. Default event mode is COMMENT
# (no dismissal friction); REQUEST_CHANGES / APPROVE are opt-in.
EVENT_MODE="comment"
for arg in "$@"; do
  case "$arg" in
    --event=*)
      EVENT_MODE="${arg#--event=}"
      ;;
    *)
      echo "ERROR: unknown flag: $arg" >&2
      echo "Supported flags after --confirm: --event=comment|request-changes|approve" >&2
      exit 2
      ;;
  esac
done

case "$EVENT_MODE" in
  comment|request-changes|approve) ;;
  *)
    echo "ERROR: --event must be one of: comment, request-changes, approve (got: $EVENT_MODE)" >&2
    exit 8
    ;;
esac

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not installed" >&2
  exit 4
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required for building the inline-comments payload. Install jq." >&2
  exit 5
fi

if [[ "$COMMENTS_FILE" == "-" ]]; then
  # Read JSON from stdin into a temp file. This lets the caller pipe a heredoc
  # in the same bash command that invokes the script, avoiding a separate
  # Write tool call (and the approval prompt it would trigger).
  TEMP_INPUT="$(mktemp -t skill-reviewer-stdin.XXXXXX)"
  CLEANUP_FILES+=("$TEMP_INPUT")
  cat > "$TEMP_INPUT"
  COMMENTS_FILE="$TEMP_INPUT"
fi

if [[ ! -f "$COMMENTS_FILE" ]]; then
  echo "ERROR: comments file not found: $COMMENTS_FILE" >&2
  exit 2
fi

# Validate input is an array
if ! jq -e 'type == "array"' "$COMMENTS_FILE" >/dev/null; then
  echo "ERROR: comments file must be a JSON array" >&2
  exit 2
fi

# Resolve OWNER/REPO. Prefer `git remote get-url origin` over `gh repo view`
# because gh's "default repo" can resolve to an upstream tracker when the local
# clone is a fork — which would post the review to the wrong repo silently.
# git origin is what the user thinks of as "their" remote, and matches the PR
# they're reviewing 99% of the time. Fall back to gh repo view if git is absent
# or the remote URL doesn't parse.
ORIGIN_URL="$(git -C "$(pwd)" remote get-url origin 2>/dev/null || true)"
OWNER=""
REPO=""
if [[ -n "$ORIGIN_URL" ]]; then
  # Parse via bash parameter expansion (no ERE regex, which lacks non-greedy quantifiers).
  # Handles both SSH (git@github.com:OWNER/REPO.git) and HTTPS (https://github.com/OWNER/REPO.git) forms.
  TRIMMED="${ORIGIN_URL%.git}"   # strip trailing .git
  TRIMMED="${TRIMMED%/}"          # strip trailing /
  REPO="${TRIMMED##*/}"           # last path component is REPO
  REST="${TRIMMED%/$REPO}"        # everything before /REPO
  OWNER="${REST##*[/:]}"          # last segment before / or :
fi

if [[ -z "$OWNER" || -z "$REPO" ]]; then
  REPO_ERR="$(mktemp -t skill-reviewer-repo.XXXXXX)"
  CLEANUP_FILES+=("$REPO_ERR")
  REPO_INFO="$(gh repo view --json owner,name 2>"$REPO_ERR")" || {
    echo "ERROR: could not resolve OWNER/REPO from git origin or gh repo view:" >&2
    cat "$REPO_ERR" >&2
    exit 6
  }
  OWNER="$(echo "$REPO_INFO" | jq -r '.owner.login')"
  REPO="$(echo "$REPO_INFO" | jq -r '.name')"
fi

echo "Target: $OWNER/$REPO PR #$PR_NUMBER" >&2

# Build the inline comments array (entries with path+line)
INLINE_COMMENTS="$(jq '
  map(select(.path and .line) | {
    path,
    line,
    side: (.side // "RIGHT"),
    body
  } + (
    if .start_line then {start_line: .start_line, start_side: (.start_side // "RIGHT")}
    else {}
    end
  ))
' "$COMMENTS_FILE")"

# Build the top-level summary body (concatenate all entries without path)
TOP_BODY="$(jq -r '
  map(select(.path == null or .line == null) | .body) | join("\n\n---\n\n")
' "$COMMENTS_FILE")"

# If both lists are empty, refuse — nothing to post
INLINE_COUNT="$(echo "$INLINE_COMMENTS" | jq 'length')"
if [[ "$INLINE_COUNT" -eq 0 && -z "$TOP_BODY" ]]; then
  echo "ERROR: comments file produced zero inline comments AND empty summary. Nothing to post." >&2
  exit 7
fi

# Default summary header if the caller didn't provide one
if [[ -z "$TOP_BODY" ]]; then
  TOP_BODY="## Skill Reviewer — automated review

Generated by the \`skill-reviewer\` skill. See inline comments on the Files tab."
fi

# Resolve the GitHub review event from EVENT_MODE.
# DEFAULT IS COMMENT. The auto-promotion to REQUEST_CHANGES based on blocker count
# was deliberately removed — REQUEST_CHANGES requires manual dismissal afterwards,
# and the friction of that dismissal step is unacceptable to CKL maintainers.
# The textual "Verdict: BLOCK MERGE" in the top-level summary still calls out
# blockers loudly; we just don't carry that into a GitHub-level merge gate.
# REQUEST_CHANGES and APPROVE remain available as explicit opt-in overrides
# for the rare case where the user actually wants them.
case "$EVENT_MODE" in
  comment)
    RESOLVED_EVENT="COMMENT"
    EVENT_REASON="default: COMMENT (no dismissal friction)"
    ;;
  request-changes)
    RESOLVED_EVENT="REQUEST_CHANGES"
    EVENT_REASON="explicit opt-in: --event=request-changes (you will need to dismiss this review manually later)"
    ;;
  approve)
    RESOLVED_EVENT="APPROVE"
    EVENT_REASON="explicit opt-in: --event=approve (rare — confirm this was intentional)"
    ;;
esac

echo "Event mode: $EVENT_MODE → $RESOLVED_EVENT" >&2
echo "Reason:     $EVENT_REASON" >&2

# Build the full review payload
PAYLOAD="$(jq -n \
  --arg body "$TOP_BODY" \
  --arg event "$RESOLVED_EVENT" \
  --argjson comments "$INLINE_COMMENTS" \
  '{event: $event, body: $body, comments: $comments}')"

# POST to the reviews endpoint — this is the call that creates true inline comments
RESPONSE_FILE="$(mktemp -t skill-reviewer-post.XXXXXX)"
POST_ERR="$(mktemp -t skill-reviewer-post.err.XXXXXX)"
CLEANUP_FILES+=("$RESPONSE_FILE" "$POST_ERR")
HTTP_STATUS=0

if ! echo "$PAYLOAD" | gh api \
  "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
  --method POST \
  --input - \
  > "$RESPONSE_FILE" 2>"$POST_ERR"; then
  HTTP_STATUS=$?
fi

if [[ "$HTTP_STATUS" -ne 0 ]]; then
  echo "ERROR: GitHub API POST /reviews failed:" >&2
  cat "$POST_ERR" >&2
  echo "" >&2
  echo "Common causes:" >&2
  echo "  - A finding's path:line wasn't part of the PR diff (GitHub rejects orphan inline comments)." >&2
  echo "  - File path uses an old name (rename — use the post-rename path)." >&2
  echo "  - Multi-line comment with start_line > line." >&2
  exit 6
fi

REVIEW_ID="$(jq -r '.id // empty' "$RESPONSE_FILE")"
REVIEW_URL="$(jq -r '.html_url // empty' "$RESPONSE_FILE")"

echo "Posted PR review:"
echo "  Inline comments:  $INLINE_COUNT"
echo "  Top-level summary: $([ -n "$TOP_BODY" ] && echo "yes" || echo "no")"
echo "  Event:            $RESOLVED_EVENT"
echo "  Event reason:     $EVENT_REASON"
echo "  Review ID:        $REVIEW_ID"
echo "  URL:              $REVIEW_URL"
