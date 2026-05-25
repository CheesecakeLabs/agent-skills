#!/usr/bin/env bash
# Runs the bundled structural validator against a single skill path.
# The validator (validate_skill.py) is bundled INSIDE this skill, so it works
# in any repo — the target repo does NOT need to ship its own validator.
#
# Source of the validator: copied from agent-skills monorepo's
# packages/skills-catalog/skills/(creation)/skill-architect/scripts/validate_skill.py
# Keep periodic sync — see "Validator sync" section in SKILL.md.
#
# Usage:
#   run_validate.sh <skill-path>
#   run_validate.sh <skill-path> --json-out FILE
#
# Exit codes:
#   0 = validator pass (warnings allowed), 1 = validator found errors,
#   2 = usage error, 4 = missing python3 or pyyaml

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <skill-path> [--json-out FILE]" >&2
  exit 2
fi

SKILL_PATH="$1"
shift || true

if [[ ! -d "$SKILL_PATH" ]]; then
  echo "ERROR: not a directory: $SKILL_PATH" >&2
  exit 2
fi

# Resolve absolute path so the validator works regardless of cwd
SKILL_ABS="$(cd "$SKILL_PATH" && pwd)"

# The bundled validator lives next to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate_skill.py"

if [[ ! -f "$VALIDATOR" ]]; then
  echo "ERROR: bundled validator not found at $VALIDATOR — skill installation is incomplete." >&2
  exit 4
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to run the bundled validator." >&2
  exit 4
fi

# pyyaml is a soft dependency — the validator has a fallback parser, but pyyaml gives better diagnostics
python3 -c "import yaml" 2>/dev/null || \
  echo "WARN: pyyaml not installed — using fallback YAML parser (lower fidelity). Install with: pip3 install --user pyyaml" >&2

python3 "$VALIDATOR" "$SKILL_ABS" "$@"
