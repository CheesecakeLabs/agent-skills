# 🤝 Contributing to Agent Skills

First of all, thank you for taking the time to contribute! 🎉

> **Note**: This document provides all the necessary information to get your local environment set up, understand the architecture, create new skills, and safely submit your contributions.

## 🛠 Prerequisites

- **Node.js** ≥ 22
- **npm** (comes with Node.js)

## 🚀 Setup

```bash
git clone https://github.com/tech-leads-club/agent-skills.git
cd agent-skills
npm ci
npm run build
```

## 💻 Development Commands

| Command                            | Description                        |
| ---------------------------------- | ---------------------------------- |
| `npm run start:dev:cli`            | Run CLI locally (interactive mode) |
| `npm run start:dev:mcp`            | Build MCP and open Inspector       |
| `npm run generate:skill <name>`    | Generate a new skill               |
| `npm run validate`                 | Validate all skills                |
| `npm run build`                    | Build all packages                 |
| `npm run test`                     | Run all tests                      |
| `npm run lint`                     | Lint codebase                      |
| `npm run format`                   | Format code with Prettier          |
| `npm run scan`                     | Run incremental security scan      |
| `nx run marketplace:dev`           | Run marketplace locally            |
| `nx run marketplace:generate-data` | Update marketplace skills data     |

## ⭐ Creating a New Skill

> **Important**: When creating a new skill or adding an external skill to the catalog, you **must** use the **`skill-architect`** skill to guide the process and ensure the skill follows our quality standards. If you're an AI agent, load the `skill-architect` skill before proceeding. If contributing manually, review the [Description Quality Standards](#description-quality-standards) below.

```bash
# With category (recommended)
nx g @tech-leads-club/skill-plugin:skill my-skill --category=development

# Full options
nx g @tech-leads-club/skill-plugin:skill my-skill \
  --description="What my skill does" \
  --category=development \
  --author="github.com/username" \
  --skillVersion="1.0.0"
```

The generator creates:

- `packages/skills-catalog/skills/(development)/my-skill/SKILL.md`

After generating the scaffold, refine the `SKILL.md` content (especially the `description` field) following the quality standards below.

## 🧩 Adding a Skill to the CKL Marketplace

> **CKL fork only.** Exposes any skill in `packages/skills-catalog/skills/(<category>)/<skill-name>/` as a Claude marketplace plugin so teammates can run `/plugin install <plugin>@ckl-agent-skills`. Works the same way for upstream skills AND net-new CKL-authored skills.

### Recommended: ask Claude (works inside this repo)

Open a Claude Code session in this repo and say something like *"add the docs-writer skill to the marketplace"* or *"expose tlc-spec-driven via our marketplace"*. The project-scoped `marketplace-plugin-creator` skill at `.claude/skills/` auto-loads when you're in this working tree and:

1. Runs the right npm script with the right arguments
2. Surfaces the standalone-candidate advisory (if the skill is heavy-payload or vendor-prefixed) so you choose the plugin shape — bundled in its category, or standalone
3. Reports back what changed

You never need to remember the CLI surface. This is the path for non-expert teammates and for anyone working through Claude.

### Explicit: run the scripts directly

For scripting, automation, or expert use:

```bash
# Add one skill (defaults plugin name to <category>)
npm run marketplace:add -- <skill-name>

# Add an entire category in one shot
npm run marketplace:add-category -- <category>

# Force a standalone plugin (skips candidacy detection)
npm run marketplace:add -- <skill-name> --plugin=<plugin-name>

# Bundle into the category plugin even if the script would flag the skill as a standalone candidate
npm run marketplace:add -- <skill-name> --bundle
```

Idempotent — re-running with the same arguments is a safe no-op. If a skill name exists in multiple categories, re-run with `--category=<cat>` to disambiguate.

### Standalone-candidate detection (exit code 2)

When `marketplace:add` is invoked without `--plugin=` or `--bundle`, the script checks whether the skill looks like a flagship that warrants its own plugin (heavy reference payload, ≥500-line SKILL.md, or vendor/methodology naming prefix like `tlc-`, `ckl-`, `aws-`). If so, the script **halts with exit code 2** and prints the signals plus two re-run commands. No state changes — you pick standalone or bundle and re-run.

Examples that fire: `tlc-spec-driven` (16 refs + `tlc-` prefix), `cloudflare-deploy` (307 refs), `create-technical-design-doc` (1485 LOC).
Examples that don't fire: `skill-architect`, `tactical-ddd`, `docs-writer` (lightweight, no vendor prefix).

The Claude-driven flow (above) handles exit 2 automatically — it surfaces the signals and asks you which path you want.

### Net-new CKL skills

If you're authoring a brand-new skill that isn't from upstream:

1. **Scaffold the skill** using the Nx generator (`nx g @tech-leads-club/skill-plugin:skill ...`) — see [Creating a New Skill](#-creating-a-new-skill) above. For CKL-specific skills, use `--category=ckl-internal`; otherwise pick whichever existing category fits.
2. **Write the SKILL.md content** with `skill-architect`'s guidance.
3. **Expose it via the marketplace** with the same `marketplace:add` workflow (or the Claude-driven ask) — the script doesn't care where the skill came from.

### Validate the install

```bash
/plugin marketplace update
/plugin install <plugin-name>@ckl-agent-skills
```

Then in a fresh Claude Code session, ask something that should trigger the skill and confirm it loads via the Skill tool.

## 📁 Project Structure

```
agent-skills/
├── packages/
│   ├── cli/                      # @tech-leads-club/agent-skills CLI
│   ├── marketplace/              # Next.js static site for the skill registry
│   └── skills-catalog/           # Skills collection
│       └── skills/               # All skill definitions
│           ├── (category-name)/  # Categorized skills
│           └── _category.json    # Category metadata
├── tools/
│   └── skill-plugin/             # Nx skill generator
├── skills-registry.json          # Auto-generated catalog
├── .github/
│   └── workflows/                # CI/CD pipelines
└── nx.json                       # Nx configuration
```

## 📝 Skill Structure

```
packages/skills-catalog/skills/
├── (category-name)/              # Category folder
│   └── my-skill/                 # Skill folder
│       ├── SKILL.md              # Required: main instructions
│       ├── scripts/              # Optional: executable scripts
│       ├── templates/            # Optional: file templates
│       └── references/           # Optional: on-demand docs
└── _category.json                # Category metadata
```

### SKILL.md Format

```markdown
---
name: my-skill
description: What this skill does in one sentence. Use when user says "trigger phrase", "another trigger", or "third trigger". Do NOT use for things handled by other-skill.
metadata:
  version: 1.0.0
  author: github.com/username
---

# My Skill

Brief description.

## Process

1. Step one
2. Step two
```

### Category Metadata

`_category.json`:

```json
{
  "(development)": {
    "name": "Development",
    "description": "Skills for software development",
    "priority": 1
  }
}
```

### Best Practices

- **Keep SKILL.md under 500 lines** — use `references/` for detailed docs
- **Write specific descriptions** — include trigger phrases
- **Assume the agent is smart** — only add what it doesn't already know
- **Prefer scripts over inline code** — reduces context window usage
- **Use the `skill-architect` skill** — for creating new skills or validating existing ones

### Description Quality Standards

Every skill description **must** follow this structure:

```
[What it does] + [Use when ...] + [Do NOT use for ...]
```

**Mandatory rules:**

| Rule                                                | Example                                                   |
| --------------------------------------------------- | --------------------------------------------------------- |
| Include `Use when` with user-facing trigger phrases | `Use when user says "deploy my app", "push this live"`    |
| Include `Do NOT use for` with negative triggers     | `Do NOT use for Netlify deployments (use netlify-deploy)` |
| Under 1024 characters                               | Keep it concise but complete                              |
| No XML angle brackets (`< >`) in YAML               | Use standard quotes instead                               |
| User perspective, not internal jargon               | "fix my build" not "remediate CI pipeline failures"       |

**Good example:**

```yaml
description: Deploy applications to Vercel. Use when the user requests "deploy my app",
  "push this live", or "create a preview deployment". Do NOT use for deploying to
  Netlify, Cloudflare, or Render (use their respective skills).
```

**Bad example:**

```yaml
# ❌ Missing triggers and negative scope
description: Helps with deployments.
```

## 🔒 Security Scan

Every skill is scanned with [Snyk Agent Scan](https://github.com/snyk/agent-scan) before publishing. The scan is **incremental** — only skills whose content changed since the last run are re-scanned.

```bash
npm run scan              # Incremental (default); requires SNYK_TOKEN
npm run scan -- --force   # Force full re-scan
```

### How it works

Each skill has a SHA-256 content hash (computed from all its files). Results are cached in `.security-scan-cache.json` (gitignored). On the next run, skills whose hash hasn't changed skip re-scanning and load results from cache.

```
Content hash unchanged → load from cache (fast)
Content hash changed   → re-scan with snyk-agent-scan
```

### When CI fails on Security Scan

1. **Open the run** → In the "CI Checks" job you’ll see a step **"Print scan failure summary"** (and/or **"Security Scan"**) with Critical/High counts and affected skills + codes (e.g. `frontend-design: W011`).
2. **Same-repo PRs** → A bot comment on the PR lists the same findings and links to the run.
3. **Fix it:**
   - **Real issue** → Adjust the skill (remove or restrict the flagged behavior).
   - **False positive** → Add an entry to `packages/skills-catalog/security-scan-allowlist.yaml` (see below). Match by `skill` + `code`; add a short `reason` and `allowedBy`/`allowedAt`.
4. **Run locally** (optional): `SNYK_TOKEN=<your-token> npm run scan` to confirm before pushing. PRs from forks don’t run the scan in CI (no secrets); use Merge Queue or run the scan locally.

### Handling false positives

If the scanner flags a finding that is intentional (e.g. a first-party MCP server integration), add it to the allowlist:

**`packages/skills-catalog/security-scan-allowlist.yaml`**

```yaml
version: '1.0.0'

entries:
  - skill: my-skill
    code: W011
    reason: >
      Fetches from trusted first-party API — expected behavior.
    allowedBy: github.com/username
    allowedAt: '2026-01-01'
    expiresAt: '2027-01-01' # Optional but recommended
```

- Match is by `skill + code` — no re-scan needed after adding an entry
- `expiresAt` is optional but recommended — forces periodic review
- Expired entries re-activate the finding automatically
- Use YAML for better readability, comments, and cleaner diffs

The allowlist is committed to the repo and reviewable in PRs.

## 🔄 Release Process

This project uses **Conventional Commits** for automated versioning:

| Commit Prefix | Version Bump  | Example                      |
| ------------- | ------------- | ---------------------------- |
| `feat:`       | Minor (0.X.0) | `feat: add new skill`        |
| `fix:`        | Patch (0.0.X) | `fix: correct symlink path`  |
| `feat!:`      | Major (X.0.0) | `feat!: breaking API change` |
| `docs:`       | No bump       | `docs: update README`        |
| `chore:`      | No bump       | `chore: update deps`         |

Releases are automated via GitHub Actions when merging to `main`.

## 🛍️ Contributing to the Marketplace

The Agent Skills Marketplace is a Next.js static site located in `packages/marketplace`. It serves as the frontend for browsing and discovering agent skills.

To work on the marketplace locally:

```bash
# Parse SKILL.md files and generate the JSON data used by the UI
nx run marketplace:generate-data

# Start the development server (runs with production config matching static export)
nx run marketplace:dev
```

Open `http://localhost:3000` in your browser. For more details on the marketplace architecture, SEO optimization, and Next.js setup, see the [Marketplace README](packages/marketplace/README.md).

## 🤝 Submitting Contributions

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feat/amazing-skill`)
3. **Commit** with conventional commits (`git commit -m "feat: add amazing skill"`)
4. **Push** to your fork (`git push origin feat/amazing-skill`)
5. **Open** a Pull Request
