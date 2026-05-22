---
name: skill-reviewer
description: 'Code review e audit de UMA skill por vez, repo-agnóstico e self-contained. Validator e security sweep são bundled (zero dep externa); só gh CLI é opcional. Aceita path local, número de PR, URL de PR, ou branch. Três modos: PR review (true inline via gh api + 1 top-level summary), audit local, review de branch. Sempre roda judgment LLM-driven (description quality, scope overlap, realismo de exemplos, MCP trust boundary, parallel subagent preconditions, convenções CKL e spec Anthropic), por severidade. Use when the user says "revisa essa skill aqui: PATH ou URL", "review esse PR de skill", "code review do skill X", "audita essa skill", "valida essa skill", "sugira melhorias pra essa skill", ou aponta path com SKILL.md, ou URL .../pull/N. Do NOT use for code review de código não-skill — TypeScript, Next.js (use ckl-delivery:pr-review), PRs majoritariamente não-skill, criação (use skill-architect), marketplace (use marketplace-plugin-creator), batch audit, nem PRs sem SKILL.md no diff.'
license: CC-BY-4.0
allowed-tools:
  - Read
  # Write deliberately not listed — this skill produces chat output only. The PR
  # comment payload is piped to post_pr_review.sh via stdin (a heredoc inside a
  # single bash call), so no Write tool call is needed. This is the chief
  # ergonomic win: no per-invocation approval prompt for file writes.
  - Task
  - Agent
  - Bash(scripts/run_validate.sh:*)
  - Bash(scripts/security_sweep.sh:*)
  - Bash(scripts/pr_touched_skills.sh:*)
  - Bash(scripts/post_pr_review.sh:*)
  - Bash(python3 scripts/validate_skill.py:*)
  - Bash(gh pr diff:*)
  - Bash(gh pr view:*)
  - Bash(gh pr checkout:*)
  - Bash(gh repo view:*)
  - Bash(gh api:*)
  - Bash(git rev-parse:*)
  - Bash(git remote get-url:*)
  - Bash(git log:*)
  - Bash(git diff:*)
  - Bash(git merge-base:*)
  - Bash(git checkout:*)
  - Bash(npx tsx tools/validate-skills.ts:*)
metadata:
  author: Cheesecake Labs
  version: 1.0.0
---

# Skill Reviewer

Repo-agnostic code review skill for Claude Code skills/plugins. Reviews skills against three sources of truth: (1) the Anthropic Skills spec encoded in `skill-architect`'s references, (2) CKL conventions documented in `references/ckl-skill-conventions.md`, and (3) `references/ckl-recurring-issues.md` (knowledge base that grows over time).

This skill is the **maintainer's review buddy** — it handles the mechanical and security-adjacent checks so the human reviewer can focus on business logic, scope decisions, and trade-offs. It works in any directory that contains skill files (`SKILL.md`), regardless of which CKL repo or external project they live in.

## Pre-requisites

- Working directory must contain at least one `SKILL.md` somewhere in the input path. The skill probes capabilities at runtime (see Step 0) — it does NOT require any specific repo, layout, or tooling beyond basic shell utilities.
- `bash`, `git`, `python3` (with `pyyaml`) are assumed to exist.
- **Optional tooling that unlocks more capability when present:**
  - `tools/validate-skills.ts` in the target repo → enables drift check between bundled validator and upstream (target == `agent-skills` monorepo)
  - `gh` CLI → enables PR fetching and inline comment posting (Modes A and C)
- The structural validator and security sweep are BUNDLED — they always run, no probe needed.
- If `gh` is absent, the skill degrades to local-only modes and surfaces what was skipped — never silent.

## Step 0 — Disambiguation gate (run BEFORE picking a mode)

Before doing anything, do two things: (a) confirm there's actually a skill in the input, and (b) detect which deterministic tooling this repo provides. The skill is **repo-agnostic** — it works on any directory containing `SKILL.md` files. New CKL repos, forks, single-skill repos, even a skill cloned standalone — all valid.

**Run these checks in order:**

1. **Does the input actually point to skill content?** This is the gate. It does NOT matter which repo you're in.

   **Locale for agent-spoken messages:** all the example messages below are written in English as the default. The agent should localize them to PT-BR only when the user is clearly conversing in PT-BR (same rule as the chat report locale in `references/output-templates.md`). User-side trigger phrases (e.g., "review esse PR", "audita essa skill") stay multi-language because users type in either.

   - **Local path input:** the path (or its children) must contain at least one `SKILL.md`. If not → refuse: *"This path has no SKILL.md. Point me at a folder that is a skill or contains skills."*. Stop.
   - **PR / branch input:** the diff must touch at least one `SKILL.md` (or files inside a folder that contains one). If `gh pr diff --name-only` returns zero `SKILL.md` references AND zero files under `*/skills/*` paths → refuse: *"This PR doesn't touch any skill. Use `ckl-delivery:pr-review` for generic code review."*. Stop.
   - **Mixed PRs:** if `skill_files / total_files < 0.3` → warn: *"This PR is mostly non-skill code (X% skills, Y% code). I only review the skill portion. Recommend running `ckl-delivery:pr-review` in parallel for the rest. Continue with just the skills?"*. Wait for explicit confirmation.

2. **Detect available tooling (capability probe).** Both the structural validator and the security sweep are bundled inside this skill — they ALWAYS run. The only optional capability is `gh` (for PR operations) and the upstream validator (for drift check):

   ```bash
   # Capability probes — only for optional steps
   HAS_GH=$(command -v gh >/dev/null 2>&1 && echo "yes" || echo "no")
   HAS_UPSTREAM_VALIDATOR=$(test -f tools/validate-skills.ts && echo "yes" || echo "no")  # for drift check only
   ```

   Record the capability matrix as part of the report header:

   ```
   Capabilities:
     ✓ Bundled structural validator    → always runs
     ✓ Bundled security sweep          → always runs
     ✓ gh CLI                          → PR operations enabled
     ✓ Upstream validator at tools/    → drift check enabled (target == agent-skills)
   ```

   If `gh` is missing, surface: *"gh CLI unavailable — PR fetching and inline posting disabled. Local-only modes still work."*

3. **Identify the skill path patterns relevant to THIS repo.** Different repos organize skills differently:

   - `packages/skills-catalog/skills/(category)/<name>/` (agent-skills layout)
   - `plugins/<plugin>/skills/<name>/` (ckl-ai-skills layout)
   - `skills/<name>/` (single-flat-skills repo)
   - `<name>/` directly at root (standalone skill repo)

   The `pr_touched_skills.sh` script already supports the first two patterns. For the latter two, fall back to finding any directory containing `SKILL.md` in the changed file list.

4. **Surface a one-line repo summary at the start of the report** so the user has zero confusion about what was scanned vs not:

   ```
   Repo: <detected from `git remote get-url origin` basename, or "local">
   Layout: <inferred from path patterns found>
   Mode: <Full | Degraded — no validator | Degraded — no scan | Degraded — judgment-only>
   ```

Only AFTER Step 0 passes do you pick the operating mode below.

## Three operating modes

After the disambiguation gate, detect which mode applies based on user input. Pick the matching script in `scripts/`. All three modes operate on **one skill at a time** — batch / multi-skill audit is intentionally out of scope.

### Mode A — PR review (preferred)

Trigger: user mentions a PR number (`PR 42`, `PR #42`, `do PR 42`), a GitHub PR URL (`https://github.com/ORG/REPO/pull/42`), or any URL containing `/pull/N`.

Input normalization:
- If input is a URL like `https://github.com/.../pull/42` → extract the number with `echo "$URL" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+'`. Pass the number to the scripts. The `gh` CLI actually accepts the URL directly too — both forms work.
- If input is just `42` or `#42` or `PR 42` → strip non-digits, pass the number.

1. Run `scripts/pr_touched_skills.sh <PR-ref>` to list skills/plugins changed in the PR (accepts number or URL — passes through to `gh`). The script uses `gh pr diff --name-only` and filters paths matching `packages/skills-catalog/skills/(*)/*/` or `plugins/*/skills/*/`.
2. For each touched skill: run validation and judgment checks (see Workflow).
3. **Compose the report directly in PR-comment-ready format.** The chat report IS the draft — there's no separate "draft" step. Use the inline-comment-style format from `references/output-templates.md` (per-finding includes `path:line`, severity, source attribution, suggested fix). Keep the structured JSON payload **in memory only** — do NOT write it to disk. When the user confirms the PR posting, the agent passes the JSON to `post_pr_review.sh` via stdin in a single bash call (heredoc — see Step 4 of Mode A and the post-script docs). This avoids the `Write` tool prompt entirely.
4. After showing the report, ask once: *"Post this as a PR review via `gh api`? (N inline comments + 1 top-level summary, event `COMMENT`)"*. Localize the prompt to PT-BR only if the chat is in PT-BR. Only `scripts/post_pr_review.sh` runs after explicit approval. **Invocation pattern — JSON via stdin (no Write tool call):**
   ```bash
   scripts/post_pr_review.sh <PR-NUMBER> - --confirm <<'JSON'
   [ ...the inline comments + summary array, exactly as composed in the chat report... ]
   JSON
   ```
   The `-` (single dash) tells the script to read JSON from stdin. The heredoc is part of the same bash command, so it matches the `Bash(scripts/post_pr_review.sh:*)` allowlist pattern — no extra prompt. The script always posts as `COMMENT` by default — that's deliberate, because `REQUEST_CHANGES` sticks on the PR until someone manually dismisses it, and that dismissal friction outweighs the benefit of the merge gate. The textual "Verdict: BLOCK MERGE" in the summary still calls out blockers clearly. If the user explicitly says they want to force the merge gate ("posta como request-changes"), call the script with `--event=request-changes`. If the user wants edits to the content, iterate on the chat report, then re-ask. Each round is one question, not two.

**Tone:** PR review uses blocker severity for spec violations. Blockers block the merge.

### Mode B — Local folder review (single skill audit)

Trigger: user mentions a folder path, says `local`, says `audita essa skill X`, says "audit this skill", or `gh` is unavailable.

1. Accept a path to a skill folder (or to a plugin root containing `skills/`).
2. If the path is a plugin, recursively review every skill inside.
3. Run validation and judgment checks, produce report. No PR posting step.

**Tone differs based on context:**
- If the skill is currently in a PR or unreleased branch → keep blocker severity.
- If the skill is already merged on `main` → demote `blocker` findings to `must-fix-soon` and frame the report as **hardening suggestions**, not merge gates. The skill is already live; no one can "block" it retroactively.

How to detect: run `git log -1 --format=%H -- <skill-path>/SKILL.md` and `git merge-base main HEAD`. If the skill's latest commit is reachable from main, it's merged → use audit tone.

### Mode C — Branch review (no PR yet)

Trigger: user mentions a branch name and says `branch` (e.g., "review skills da branch feat/foo").

1. `gh pr checkout <branch>` (graceful degrade: `git checkout <branch>` if gh is missing).
2. `git diff main...HEAD --name-only` to find touched skill paths.
3. Same flow as Mode A but no inline comments at the end (no PR to post to).

## What this skill explicitly does NOT do

- **Batch / multi-skill audit.** Each invocation reviews exactly one skill. If the user asks "audita todas as skills da categoria X" or wants a sweep of the repo, surface that this is out of scope: *"I only review one skill at a time. Point me at which skill you want audited."*. Suggest running `npm run validate` for a cheap structural sweep instead, and then pointing this skill at the specific outliers one at a time.
- **Posting PR comments without explicit confirmation.** Always require one explicit user confirmation before `gh pr review` runs. The chat report IS the draft — do not add a second "show me the draft" gate.
- **Modifying the skill being reviewed.** This skill produces findings — it does not edit the target. If the user asks for fixes, they should run `skill-architect` separately after reading the review.

## Subagent dispatch (adaptive — only when complexity warrants)

This skill MAY dispatch up to 3 subagents in parallel to split the read work across independent surface areas. Default is sequential. Dispatch only when the target's complexity makes sequential review wasteful.

### When to dispatch

Dispatch if ANY of these is true:
- Target SKILL.md body > 400 lines
- Target skill has > 8 files total (1 SKILL.md + refs + scripts)
- Target skill has ≥ 5 non-trivial files under `scripts/` or `references/`

Otherwise: sequential. Small skills don't benefit — dispatch overhead exceeds savings.

### The 3 analyzers — formal dispatch templates

Each analyzer is invoked via the Task/Agent tool with the exact prompt below. Treat these as canonical templates — do not improvise per dispatch. Each is `readonly` (analyzers read; main agent writes the final report) and `model: fast` (checklist application, not creative synthesis).

#### Body analyst (Subagent A)

```
metadata: { readonly: true, model: fast }

You are a Claude skill body analyst. You analyze a single SKILL.md body
and apply judgment checks J1–J16 from references/judgment-checks.md.

When invoked:
1. Read the target SKILL.md at the path provided.
2. Apply J1–J16 (description quality, workflow coherence, scope and
   composability, progressive disclosure, examples realism, CKL conventions).
3. Do NOT read scripts/ or references/ — those are handled by peer analyzers.

Return a JSON array of findings:
[
  {
    "severity": "blocker|must-fix|suggest|nit",
    "rule": "J<N>",
    "path": "<SKILL.md path>",
    "line": <int>,
    "evidence": "<short quote>",
    "fix": "<concrete suggestion>"
  }
]

If you cannot read the file, return {"error": "<reason>"}. Do not improvise findings without evidence.
```

#### Scripts analyst (Subagent B)

```
metadata: { readonly: true, model: fast }

You are a Claude skill scripts analyst. You analyze every file under the
target's scripts/ directory and apply J17–J24 + the bundled security sweep.

When invoked:
1. List every file in scripts/.
2. For each, apply J17 (shebang + set -euo pipefail), J18 (args validated),
   J19 (usage line), J20 (no PWD assumptions), J22–J24 (allowed-tools hygiene
   if referenced in SKILL.md frontmatter).
3. Execute scripts/security_sweep.sh from THIS reviewer skill against the
   target skill folder. Parse its line-prefixed output.
4. Do NOT read SKILL.md body or references/ — peer analyzers cover those.

Return a JSON object:
{
  "findings": [ { same shape as Body analyst } ],
  "security_sweep_raw": "<verbatim sweep output>"
}

If a script can't be read, surface as a finding (severity: blocker, rule: "structural") rather than failing silently.
```

#### References analyst (Subagent C)

```
metadata: { readonly: true, model: fast }

You are a Claude skill references analyst. You verify that every file under
references/ is well-formed, load-conditioned, and consistent with SKILL.md.

When invoked:
1. List every file in references/.
2. For each, apply J12 (size discipline: TOC required if > 300 lines),
   J13 (SKILL.md must state WHEN to load this file).
3. Cross-check: every references/foo.md must be mentioned in SKILL.md at
   least once; if not, flag as suggest (dead reference).
4. Do NOT read SKILL.md body in full (read only enough to verify reference
   mentions). Peer analyzers handle SKILL.md and scripts.

Return the same JSON findings array as Body analyst.

If references/ doesn't exist, return {"findings": [], "note": "no references directory — not an error"}.
```

### Main agent responsibilities (NOT delegated)

- Run `scripts/run_validate.sh` (fast, sequential — no benefit from dispatch)
- Apply J25 (Gotchas section), J27 (MCP trust boundary docs), J29 (parallel subagent preconditions in the target) — these need holistic view across all three surfaces
- Consolidate the 3 JSON responses + validator output into the final report
- Handle completion gate failures (see below)
- Compose the chat report + PR payload

### Preconditions (dogfood of J29)

When dispatching, state these in the report header — the skill must comply with the rule it enforces:

1. **3 unrelated domains:** body, scripts, references
2. **No shared state:** each analyzer reads disjoint paths
3. **Clear file boundaries:** A reads SKILL.md only, B reads scripts/* only, C reads references/* only

### Completion gate

- All 3 must return parseable JSON. If any returns an error or unparseable response, retry ONCE.
- If retry fails: main agent reads that surface itself (bounded fallback). Report header says *"3-way dispatch with N fallbacks"*. Never silent.
- Never spin in retry loops. One retry, then fallback.

### When NOT to dispatch

- Small skills (< 200-line SKILL.md, ≤ 4 files total)
- User explicitly says *"sequential"* or *"sem subagent"*
- The target being reviewed IS this skill itself (avoid recursive complexity that muddies J29 audit)

### Report header — always state the execution mode

```
Execution: sequential
```
or
```
Execution: 3-way subagent dispatch (Body + Scripts + References) — 0 fallbacks
```

Never omit. The reader must know whether parallelism ran.

## Workflow (per skill being reviewed)

For each skill path:

### Step 1 — Run deterministic validation (ALWAYS — validator is bundled)

The structural validator (`scripts/validate_skill.py`) ships inside this skill. It does NOT depend on the target repo having any tooling. Always run:

```bash
scripts/run_validate.sh <skill-path>
```

This calls the bundled Python validator and captures the output. Parse the checks: every failed check is at minimum **must-fix**, every warning is at minimum **suggest**. The validator is the source of truth for structural checks — do NOT re-implement these in the judgment layer.

If the validator fails to parse the frontmatter (`frontmatter_parse_error`), STOP for this skill and report as a **blocker** — downstream checks would be meaningless.

**Pre-requisites for Step 1:**
- `python3` available (assume yes — same constraint as the skill itself)
- `pyyaml` recommended (`pip3 install --user pyyaml`); validator has a fallback parser but with lower fidelity. The script prints a one-line WARN if missing — surface that in the report so the user knows.

**Validator sync caveat:**

The bundled validator was copied from `agent-skills` monorepo's `skill-architect`. If that upstream evolves (new checks, fixed bugs), the bundled copy drifts. On any review where the target IS the `agent-skills` repo AND `tools/validate-skills.ts` exists locally, ALSO run the local one and diff the outputs — surface drift as a meta-finding:

```bash
# Only when target == agent-skills monorepo
if [[ -f tools/validate-skills.ts ]]; then
  npx tsx tools/validate-skills.ts <skill-path> > /tmp/upstream.txt
  scripts/run_validate.sh <skill-path> > /tmp/bundled.txt
  diff /tmp/upstream.txt /tmp/bundled.txt > /tmp/drift.txt || \
    echo "Validator drift detected — bundled copy is behind upstream. Consider syncing scripts/validate_skill.py."
fi
```

Treat drift as a `(meta)` advisory in the report, severity nit. It's a maintainer signal, not a finding on the skill being reviewed.

### Step 2 — Run bundled security sweep (ALWAYS — sweep is bundled)

The security sweep (`scripts/security_sweep.sh`) ships inside this skill. It runs deterministic checks for the patterns that matter for skills specifically:

- **Classic code-execution risks:** hardcoded secrets, eval/exec on dynamic input, dangerous `rm -rf`, outbound network calls, path traversal, unscoped Bash allowlist entries.
- **Prompt-injection / obfuscation patterns (added based on mai/26 industry research — Snyk ToxicSkills, Embrace The Red, Skills Directory):**
  - `unicode_tag_smuggling` / `unicode_tag_present` — invisible instructions hidden in the U+E0000..U+E007F codepoint block. Legitimate skills do not use this range.
  - `excessive_zero_width` — ZWSP/ZWNJ/variation selectors above the emoji noise floor.
  - `long_base64_blob` — long base64-shaped tokens (with mixed case + digit heuristic to filter out hex hashes), a classic obfuscation pattern.
  - `env_var_exfil_same_line` / `env_var_exfil_proximity` — credential references (`$ANTHROPIC_API_KEY`, `$AWS_*`, etc.) within ±3 lines of a network call (`curl`, `wget`, `fetch`, etc.) — the canonical credential-exfiltration shape.
- **Crypto / wallet exposure** — relevant in CKL context because devs run skills inside client repos, including DeFi/crypto clients:
  - `crypto_cred_reference` — mnemonic/private-key env vars (`$MNEMONIC`, `$ETH_PRIVATE_KEY`, etc.), exchange API keys (`$BINANCE_API_KEY`, `$COINBASE_API_KEY`, etc.), and wallet file paths (`wallet.dat`, `~/.ethereum/keystore`, etc.). **Conditional severity:** BLOCKER by default, demoted to SUGGEST when the skill self-declares as blockchain domain in its description (heuristic keywords: `blockchain`, `crypto`, `defi`, `wallet`, `smart contract`, `web3`, `ethereum`, `solana`, `bitcoin`, `evm`, `polygon`, `arbitrum`, `nft`, `dapp`, `tokenomics`). A blockchain skill legitimately references these env vars — but reviewer should still confirm the value is handled safely (used by an SDK, not embedded in URLs/logs).
  - `eth_private_key_literal` / `btc_private_key_literal` — actual private key formats embedded inline. **Always BLOCKER**, regardless of blockchain context — no skill should embed a literal key, blockchain or otherwise; the correct pattern is env var reference.
- **Persistence install patterns** — relevant because a CKL dev laptop aggregates N client environments; a persistent backdoor on the laptop = compromise across every client they touch:
  - `persistence_command` — `crontab`, `systemctl enable`, `launchctl load` invocations.
  - `persistence_write` — write redirects to shell rc files, `~/.ssh/authorized_keys`, cron directories, or launch-agent locations.

```bash
scripts/security_sweep.sh <skill-path>
```

Output: one finding per line, prefixed by severity (`BLOCKER`, `MUST-FIX`, `SUGGEST`). Parse and merge into the report.

**What this sweep is and isn't:**

- ✓ Catches skill-specific risks (the patterns above)
- ✓ Works in any repo (bundled, zero external deps beyond bash + grep + find)
- ✗ NOT a CVE / dependency scanner (skills rarely have meaningful deps)
- ✗ NOT a replacement for proper SAST when reviewing complex application code (out of scope — this skill reviews skills, not apps)

If the target repo has its own `npm run scan` (snyk-agent-scan or similar) AND the user explicitly asks for deeper coverage, mention it as an *additional* step the user can run manually — but do NOT block on it and do NOT include it as a default step in this skill.

**Skip messaging:** there is no skip case for this step. The sweep always runs. If it crashes (shouldn't — it's bundled), report `(security sweep error)` as a meta-finding with the stderr output.

### Step 3 — Apply judgment checks (LLM-driven)

Load `references/judgment-checks.md` and walk the checklist. These are the checks that deterministic tools cannot do — quality of description, scope overlap, realism of examples, workflow coherence, CKL conventions beyond what `validate-skills.ts` catches.

Each finding must include: severity, the specific text/line that triggered it, the rule violated, and a concrete suggested change (not vague advice).

### Step 4 — Check against ckl-recurring-issues.md

Load `references/ckl-recurring-issues.md` and verify the skill doesn't trip any historical pattern. This file starts empty and grows as CKL maintainers document patterns that keep appearing in real reviews. Each entry maps a regex/heuristic to a severity and a suggested fix.

### Step 4b — Propose new recurring entries (HIGH BAR — quality over quantity)

After Steps 1–4 complete, look back at the findings produced **in this single review** and decide if any deserves to graduate into `ckl-recurring-issues.md`. Be ruthless about the bar:

**ALL of these must be true for a finding to qualify as a recurring suggestion:**

1. **Source attribution is NOT** `(validator)`, `(snyk)`, `(CKL conventions)`, or `(judgment:J<N>)` — meaning the finding was a novel LLM judgment, not codified
2. **It represents a PATTERN, not a one-off** — naming inconsistency = pattern; typo = one-off
3. **It would catch the same class of bug in OTHER skills** — generalizable, not specific to this PR
4. **Severity ≥ suggest** — nits never graduate
5. **The pattern can be expressed as a heuristic** an LLM could re-apply — vague observations don't qualify

**Cap: maximum 2 suggestions per review.** If you find 5 novel patterns, surface the 2 best and drop the rest. More than 2 means the bar wasn't ruthless enough.

**Before rendering, detect whether you are in the skill-reviewer's home repo.** The auto-append flow (vote `aceita R<N>` / `descarta R<N>`) only makes sense when the user can actually modify `references/ckl-recurring-issues.md` from the current working directory. In any other repo, the file at hand is either a read-only plugin copy or doesn't exist — auto-append fails silently and the user gets nothing useful.

Detection:

```bash
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
HOME_REPO="false"
if echo "$ORIGIN_URL" | grep -qiE 'cheesecakelabs/agent-skills(\.git)?$'; then
  HOME_REPO="true"
fi
```

**Render as an explicit final section in the report**, separated from the actual findings. Use one of the two modes below depending on `HOME_REPO`.

**Mode A — home repo (auto-append available):**

```markdown
## Recurring candidates (proposed for ckl-recurring-issues.md)

The reviewer flagged these *novel* patterns this round. Each meets the high bar for graduating to a permanent recurring rule. Vote yes/no with `aceita R<N>` or `descarta R<N>` — you're in `cheesecake-labs/agent-skills`, so I can append directly to `references/ckl-recurring-issues.md`.

### Candidate A — <short pattern name>
- **Source of this finding:** `(judgment: <ad-hoc-name>)`
- **The pattern:** <one-line>
- **Detection heuristic:** <regex or rule>
- **Would catch:** <what kind of bug elsewhere>
- **Suggested severity:** suggest | must-fix
- **From this review:** <skill name>:<line>
```

When the user says *"aceita R<N>"* or equivalent, append the entry to `references/ckl-recurring-issues.md` using the template at the top of that file. When the user says nothing or says *"descarta"*, don't persist it.

**Mode B — any other repo (paste-this, no auto-append):**

```markdown
## Recurring candidates (suggestion for skill-reviewer maintainers)

I noticed a pattern that might deserve to become a permanent recurring rule. You're not in the skill-reviewer's home repo (`cheesecake-labs/agent-skills`), so I can't add it to `ckl-recurring-issues.md` from here. If you agree the pattern is worth codifying, copy the block below and send it to the skill-reviewer maintainers — issue at `cheesecake-labs/agent-skills` or DM whoever owns the catalog:

---
### New recurring pattern proposal

- **Pattern name:** <short name>
- **Description:** <one-line of what the pattern is>
- **Detection heuristic:** <regex or rule>
- **Suggested severity:** suggest | must-fix
- **Real-world example:** `<skill path>:<line>` (caught during review of `<skill name>` on <YYYY-MM-DD>)
- **Found via:** skill-reviewer auto-suggestion
---
```

Do NOT ask the user to vote `aceita R<N>` in Mode B — they can't act on it from this repo. Just hand them the text to paste and move on.

If no findings qualify in either mode, OMIT the section entirely. Don't write *"No recurring candidates this round"* — silence is fine. The user knows the section appears only when there's a real candidate.

### Step 5 — Compose the report

Format using `references/output-templates.md`. Always produce:

1. **Executive summary** — counts per severity, pass/fail verdict, files reviewed
2. **Findings grouped by severity** — Blocker → Must-fix → Suggest → Nit, each with file, line (when applicable), rule cited, suggestion
3. **Skipped checks** — explicit list (e.g., gh CLI unavailable → PR features disabled; pyyaml absent → validator fell back to stdlib parser)

**Chat IS the output.** Do NOT write the report to a markdown file, do NOT write the PR payload to a JSON file. Both used to be persisted to `$HOME/.skill-reviewer/reports/` and `/tmp/skill-reviewer/` — that's been removed in v1.1.6 because the persistent files were overengineering: the user already has chat history and (for Mode A) PR comments on GitHub. The trade-off (lose grep-able local history) is small; the gain (zero `Write` tool prompts) is large.

**For Mode A PR posting:** compose the JSON payload in memory, pass to `post_pr_review.sh` via stdin (`-` as the file arg + heredoc inside the same bash call). See Mode A step 4 for the exact invocation pattern.

If the user explicitly asks for a saved copy ("salva esse review como md"), they can copy the chat report manually. The skill does not auto-persist.

## Severity definitions

Be strict about these — calibrating well prevents reviewer fatigue.

| Severity | Definition | Examples |
|---|---|---|
| **Blocker** | Must not merge. Spec-level violation or security risk. | name uses "claude"/"anthropic", README.md inside skill folder, secret hardcoded in script, frontmatter parse error, snyk critical |
| **Must-fix** | Merge only after fix. Standards violation or judgment issue with high confidence. | description without "Use when" / "Do NOT use for", folder ≠ name, scripts without error handling, references cited but missing, vague description, snyk high |
| **Suggest** | Reviewer feedback. Worth addressing but author decides. | SKILL.md > 500 lines without progressive disclosure, missing examples, non-standard frontmatter fields (`triggers:`, `user-invocable:`), naming inconsistent with peers, snyk medium |
| **Nit** | Cosmetic. Never block on these. | typos, markdown formatting, bullet style |

## Examples

### Example 1 — Review a PR with multiple touched skills

User says: *"review o PR 42 dos skills"*

Actions:

1. Run `scripts/pr_touched_skills.sh 42` → returns list `[skills/(development)/foo, skills/(security)/bar]`
2. For each: run validate, run scan (if token), apply judgment, check recurring
3. Compose report. Result example:

```
PR #42 — 2 skills touched

EXECUTIVE SUMMARY
- (development)/foo:  2 must-fix, 1 suggest
- (security)/bar:     1 blocker, 3 must-fix

BLOCKERS (1)
- (security)/bar/SKILL.md:1
  Rule: name_not_reserved (validate-skills.ts)
  Found: name: anthropic-secrets-checker
  Fix:   rename — name field must not contain "claude" or "anthropic"

MUST-FIX (5)
...
```

4. Ask: *"Post this as a PR review via `gh api`? (N inline comments + 1 top-level summary, event `COMMENT`)"* — wait for approval. (One-gate flow: the chat report above IS the draft. Localize to PT-BR only if the chat is in PT-BR.)

### Example 2 — Local review, gh CLI missing

User says: *"review essa skill aqui: packages/skills-catalog/skills/(quality)/new-thing"*

Actions:

1. Detect Mode B (local path).
2. Skip any gh-dependent step.
3. Validate, scan, judge, recurring → report.
4. No PR-posting prompt at the end (nothing to post to).

### Example 3 — Complex skill triggers subagent dispatch

User says: *"audita essa skill aqui: packages/skills-catalog/skills/(creation)/skill-architect"*

Actions:

1. Step 0 disambiguation: input path → Mode B (local audit).
2. Inspect target complexity: SKILL.md body ≈ 530 lines, 3 references, 1 script. Trigger condition met (body > 400) → dispatch in 3-way.
3. Main agent invokes Body analyst, Scripts analyst, References analyst in parallel using the formal templates above. All three return parseable JSON.
4. Main agent runs `run_validate.sh` and `security_sweep.sh` locally (fast — not delegated).
5. Apply J25 (Gotchas), J27 (MCP trust boundary), J29 (parallel subagent preconditions in the TARGET) on the consolidated view.
6. Compose report with header: *"Execution: 3-way subagent dispatch (Body + Scripts + References) — 0 fallbacks"*. Skill is already on `main` → use audit tone (hardening suggestions, not merge gates).

## Error handling

### gh CLI not installed

Detect with `command -v gh`. If missing: switch to Mode B (local). Do not error out — surface to the user: *"`gh` not found, running in local-only mode."*

### `npm run validate` fails to execute

If `tools/validate-skills.ts` itself crashes (not "found errors" — actually crashes): report this as a **blocker** with the stderr output. The skill being reviewed cannot be assessed.

### Bundled security sweep crash

If `scripts/security_sweep.sh` itself crashes (returns non-zero with no findings parseable from stdout), surface as: *"Security sweep error — sweep script crashed mid-run."* with stderr captured, and mark the security check as **inconclusive**, NOT pass. This shouldn't happen — the sweep is bundled and tested — but treat as blocker if it does (the skill's security posture cannot be assessed).

### Skill folder has wrong structure (no SKILL.md)

Validator will catch this. Report as **blocker** — there's nothing else to review.

### Input doesn't point to any skill content

The disambiguation gate in Step 0 already handles this — refuse with a message pointing to a generic code-review skill if no `SKILL.md` is found. The skill does NOT require any specific repo or layout to operate.

## Gotchas

Real failure modes caught during development and use of this skill — including YAML `#` truncation, validator drift, security-sweep false positives on its own comments, allowlist path-matching pitfalls, and J17 detection window calibration. See `references/gotchas.md`.

**When to consult:** load `references/gotchas.md` in Step 3 (judgment) when looking for known patterns to flag in the target skill, AND whenever debugging odd behavior in this skill itself. Update the file when a non-obvious failure mode surfaces — this is the highest-signal section per Anthropic best practices.

## References

Load these on demand — do NOT load all upfront:

- `references/ckl-skill-conventions.md` — load before Step 3 (judgment checks) when reviewing the description, frontmatter, or naming.
- `references/judgment-checks.md` — load before Step 3 always. Contains the full checklist.
- `references/ckl-recurring-issues.md` — load in Step 4. Starts empty.
- `references/gotchas.md` — load in Step 3 (judgment) alongside `judgment-checks.md`. Real failure modes seen in the field; check the target for matching patterns.
- `references/output-templates.md` — load in Step 5 when composing the report or PR comment draft.
- `references/rule-explanations.md` — load in Step 5 when composing findings. Contains the plain-language "Why it matters" one-liner for every rule, so PR comments land for both engineers and non-developer skill authors.

## Scripts

- `scripts/validate_skill.py` — bundled structural validator (Python, no JS deps). Copied from `agent-skills` skill-architect; see "Validator sync caveat" above.
- `scripts/run_validate.sh <skill-path>` — wrapper that invokes the bundled Python validator. Always works, in any repo.
- `scripts/security_sweep.sh <skill-path>` — bundled regex security sweep (secrets, eval/exec, rm -rf, network calls, path traversal, unscoped Bash allowlist). Always runs.
- `scripts/pr_touched_skills.sh <pr-number-or-url>` — uses `gh pr diff --name-only`, filters skill/plugin paths, deduplicates to skill roots. Requires `gh`.
- `scripts/post_pr_review.sh <pr-number> <comments-file> --confirm` — posts **true inline comments** on the PR Files tab + 1 top-level summary via `gh api .../pulls/N/reviews` REST endpoint (NOT `gh pr review`, which collapses everything into one body). Each finding sits on its actual diff line. Refuses to run without explicit `--confirm`.

## Updating ckl-recurring-issues.md

When the user says something like *"essa eu sempre pego, anota aí"* or *"adiciona como recurring: ..."*, append a new entry to `references/ckl-recurring-issues.md` following the template at the top of that file. This is how the skill gets calibrated to real CKL review patterns over time.
