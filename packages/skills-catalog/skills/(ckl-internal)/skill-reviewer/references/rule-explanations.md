# Rule Explanations — Why Lines

One-line plain-language explanation for every rule the skill cites. The reviewer composing the report looks up each finding's rule here and copies the matching `Why it matters` line verbatim into the PR comment.

**Audience principle:** these lines are read by both senior engineers AND first-time skill authors (often product managers experimenting with `skill-architect`). Avoid shell idioms, regex syntax, and YAML jargon in the Why line. Keep the rule name as-is (engineers grep it); put the human prose in the Why.

**Length guideline:** 10–25 words per line. One sentence. No hedging.

## How to use this file

When composing a finding for the report or PR comment:

1. Look up the rule by exact name in the matching table below.
2. Copy the `Why it matters` text verbatim into the PR comment body, right after the `Rule:` line.
3. If the rule is genuinely self-explanatory from its name (e.g., `description_required`), the Why line is optional — but the default is to include it.
4. If a rule is missing from this file, add it here before publishing the finding. This file is the single source of truth for the Why line; never improvise in the report.

## Structural validator (`scripts/validate_skill.py`)

| Rule name | Why it matters |
|---|---|
| `name_required` | Without a `name`, no agent or harness can resolve which skill to invoke when triggers match. |
| `name_kebab_case` | Kebab-case is the spec convention. Mixed casing breaks slash-command invocation and file path matching across harnesses. |
| `name_not_reserved` | The name appears in the file path and in user-facing trigger phrases. Using "claude" or "anthropic" implies an official endorsement and conflicts with reserved namespaces. |
| `name_matches_folder` | The harness assumes the folder name equals the skill's `name` field. A mismatch hides the skill from discovery or loads the wrong one. |
| `description_required` | Without a description, the agent has nothing to match against the user's request — the skill will never be triggered. |
| `description_under_1024_chars` | Anthropic's spec hard-caps description at 1024 characters. Past that, the description is truncated server-side and the cut-off section is invisible to the matching logic. |
| `description_no_xml_brackets` | Angle brackets (`<` and `>`) inside the description break the YAML/markdown parser and can be misread as XML tags by downstream tools. |
| `description_has_use_when` | The `Use when ...` clause tells the agent the specific triggers (user phrases, contexts) that should activate this skill. Without it, matching is guesswork. |
| `description_has_negative_scope` | Without a `Do NOT use for ...` clause, the agent can't tell which similar skill to delegate to instead — and ends up triggering yours when another would be the correct fit. |
| `license_required` | Skills get shared and forked. A missing license blocks adoption in repos with compliance gates and creates ambiguity about reuse rights. |
| `frontmatter_parse_error` | The YAML at the top of the file did not parse. Every downstream check (name, description, license) is meaningless until this is fixed. |
| `skill_md_under_500_lines` | Skill body over 500 lines gets loaded into context every invocation. Move deep material into `references/` so it loads only when needed (progressive disclosure). |
| `no_readme_in_skill_folder` | A `README.md` next to `SKILL.md` confuses tooling that scans for the skill entrypoint and bloats the load. The skill body should be the only top-level doc. |
| `references_dir_organization` | `references/` must contain only files referenced from `SKILL.md` with explicit load conditions. Orphan files load nothing and clutter discovery. |
| `scripts_dir_organization` | Scripts should sit under `scripts/`, named after what they do, invoked relative to the skill root. Anything else breaks the harness's allowlist matching. |

## Security sweep (`scripts/security_sweep.sh`)

| Rule name | Why it matters |
|---|---|
| `hardcoded_secret` | A literal token, API key, or password in a skill file leaks every time the skill is shared, forked, or pushed to a public repo. |
| `eval_or_exec_on_dynamic_input` | Running `eval` or `exec` on agent-provided text turns a prompt-injection vulnerability into arbitrary code execution. |
| `dangerous_rm_rf` | A wide `rm -rf` (especially with variables that may be empty) can wipe the user's working tree, home directory, or worse. |
| `outbound_network_call` | A skill that reaches the network silently can exfiltrate data the user did not consent to share. Networking should be explicit in the workflow. |
| `path_traversal` | Unsanitized path components (`../foo`) let a malicious input read or write files outside the intended directory. |
| `unscoped_bash_allowlist` | `Bash(:*)` or `Bash(*)` in `allowed-tools` grants the agent permission to run any shell command without prompting. This defeats the least-authority principle. |
| `unicode_tag_smuggling` | A run of invisible Unicode Tag codepoints (U+E0000..U+E007F) carries instructions the LLM reads but a human reviewer cannot see — a documented backdoor technique that bypasses code review entirely. |
| `unicode_tag_present` | A handful of Unicode Tag codepoints in a skill file is unusual and worth a manual look — emojis do not use this codepoint block, so even sparse counts are suspect. |
| `excessive_zero_width` | Zero-width characters above the noise floor (more than emojis legitimately need) suggest obfuscation: hidden text or invisible instructions stuffed between visible content. |
| `long_base64_blob` | A long base64-shaped token inside instructions is a classic obfuscation pattern — usually decoded and piped to a shell, hiding the real payload from review. |
| `env_var_exfil_same_line` | A credential variable reference on the same line as a network call is the canonical exfiltration shape — the value of the secret leaves the machine immediately. |
| `env_var_exfil_proximity` | A credential reference within a few lines of a network call is structurally suspicious — even when the link isn't direct, this is the pattern malicious skills use to drain secrets. |
| `crypto_cred_reference` | A reference to a wallet mnemonic, private-key env var, exchange API key, or canonical wallet file path has no legitimate place in a typical skill — and CKL developers run skills inside crypto-client repos, where this would be a direct hit. **Conditional severity:** BLOCKER for non-blockchain skills, demoted to SUGGEST when the skill self-declares as blockchain domain in its description (keywords: blockchain, crypto, defi, wallet, smart contract, web3, ethereum, solana, bitcoin, evm, polygon, arbitrum, nft, dapp, tokenomics). A blockchain skill legitimately references these env vars — reviewer must still confirm safe handling. |
| `eth_private_key_literal` | A literal `0x` followed by exactly 64 hex chars matches the Ethereum private key format. A skill should never embed a wallet private key inline. |
| `btc_private_key_literal` | A token matching the Bitcoin WIF private key format (`[5KL]` + base58, 51–52 chars) has no innocent explanation in a skill file. |
| `persistence_command` | `crontab`, `systemctl enable`, and `launchctl load` install code that re-triggers after the session ends. For a CKL dev whose laptop aggregates multiple client environments, a persistent backdoor compromises every client they touch. |
| `persistence_write` | Writing to `~/.bashrc`, `~/.zshrc`, `~/.ssh/authorized_keys`, `/etc/cron.*`, `/etc/systemd/system/`, or `~/Library/LaunchAgents/` installs persistent code or trust outside the current session. Skills should not modify these files. |

## Reviewer judgment (`references/judgment-checks.md`)

Each judgment rule has a `**Why it matters:**` paragraph in `judgment-checks.md`. The Why line below is the one-sentence condensation for use in PR comments — the full prose stays in the judgment-checks file for the author to read on click-through.

| Rule | Why it matters (one-line) |
|---|---|
| J1 | Vague descriptions match too many triggers and waste agent attention on irrelevant work. |
| J2 | Trigger phrases that read like docs ("Use when user requests skill validation procedures") never match real user speech. |
| J3 | Abstract negative scope ("not for code review") leaves the agent guessing; pointing at a specific peer skill removes the ambiguity. |
| J4 | Descriptions under 80 chars under-describe the skill; over 900 char descriptions risk hitting the 1024 cap with no room to grow. |
| J5 | A skill that silently depends on `gh`, `npm run X`, or an MCP server fails cryptically when the dependency is missing. List pre-requisites up front. |
| J6 | Error sections like "if it fails, retry" tell the agent nothing useful. State what to do when each specific failure mode hits. |
| J7 | Skeletal examples ("do the thing") don't teach the agent the actual workflow. Use concrete user phrases and outputs. |
| J8 | Branches with fuzzy conditions ("if appropriate") get picked randomly. Conditions must be unambiguous. |
| J9 | Two skills with overlapping triggers race to handle the same request — the agent picks one non-deterministically. Distinguish them or merge. |
| J10 | A skill that quietly does work owned by a peer skill creates duplicate effort and bypasses the peer's workflow guards. |
| J11 | Naming inconsistency across peers in the same category makes discovery harder and signals lack of coordination. |
| J12 | A monolithic 500+ line SKILL.md loads in full every invocation. Split into `references/` so only the relevant section is loaded. |
| J13 | A reference file mentioned without a "load this when X" instruction either never loads (dead reference) or always loads (defeats progressive disclosure). |
| J14 | Non-standard frontmatter fields like `triggers:` or `user-invocable:` pass the validator but aren't in the Anthropic spec — they may break in future harness releases. |
| J15 | A skill named in EN with a 100% PT-BR description without bridging trigger phrases will miss either Portuguese or English user requests. |
| J16 | "User perspective" descriptions ("fix my build") match how people actually speak. Internal jargon ("remediate CI pipeline failures") matches nothing. |
| J17 | Shell scripts without `set -euo pipefail` swallow errors silently — a typo in a command can succeed-with-empty-output and corrupt downstream steps. |
| J18 | Scripts that don't validate `$#` produce confusing errors when called with wrong arity. The user has no idea what went wrong. |
| J19 | A script with no usage line on `-h` or bad input gives the user no way to discover how to call it. |
| J20 | Scripts that assume `pwd` is the repo root break when called from a subdirectory. Resolve paths relative to the script or use `git rev-parse`. |
| J21 | A `#` in an unquoted YAML description silently truncates the description at the `#`. Every downstream check then runs against a truncated string while the file on disk looks correct. |
| J22 | Dead `allowed-tools` entries grant permissions the skill never uses, weakening the least-authority defense for zero gain. |
| J23 | A scoped `Bash(pnpm run *)` next to an unscoped `Bash(pnpm:*)` defeats narrowing — the wide grant lets the agent run `pnpm exec <anything>`. |
| J24 | Subagent-dispatch is called `Task` in some harnesses and `Agent` in others. Listing only one breaks cross-harness portability without granting extra capability. |
| J25 | Without a Gotchas section, real failure modes get forgotten and re-introduced. The section is the highest-signal documentation in any mature skill. |
| J27 | Every MCP server is a trust boundary. A skill that silently depends on one fails unpredictably (no auth → cryptic errors) and creates unaudited attack surface. |
| J29 | Parallel subagent dispatch without explicit preconditions (independence, no shared state, file boundaries) causes race conditions, lost results, or silent data corruption. |

## Recurring CKL patterns (`references/ckl-recurring-issues.md`)

This file grows over time as CKL maintainers approve patterns from the "Recurring candidates" section of reviews. Each rule R<N> has its own `Why it matters` line stored alongside the rule definition in `ckl-recurring-issues.md`. When citing a recurring rule in a finding, copy that file's Why line — do NOT duplicate the explanations here. Keeping the Why line next to the rule definition prevents drift between the two files.

## Maintenance

When a new judgment check (J<N>) is added to `judgment-checks.md`, add its one-line Why here in the matching table. When a new recurring pattern graduates from a review, the Why line is added to `ckl-recurring-issues.md` directly (not duplicated here).

If a Why line ages out — for example, the spec changes and a rule's rationale shifts — update this file in the same commit as the rule change. The Why line must always reflect the current reason, not the historical one.
