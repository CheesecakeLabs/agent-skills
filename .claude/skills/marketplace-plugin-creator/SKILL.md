---
name: marketplace-plugin-creator
description: Adds an existing skill (or whole category) from packages/skills-catalog/skills/ to the ckl-agent-skills Claude marketplace by running the repo's marketplace scripts. Use when working in this repo and the user says "add this skill to the marketplace", "expose tlc-spec-driven via Claude marketplace", "wrap this skill as a plugin", "add the architecture category to our marketplace", "ship the docs-writer skill via the marketplace", or asks how to make a catalog skill installable through `/plugin install`. Do NOT use for authoring new skill content (use skill-architect), modifying existing SKILL.md files, removing plugins from the marketplace, or marketplace work outside this repo.
license: CC-BY-4.0
metadata:
  author: Cheesecake Labs
  version: '1.0.0'
---

# Marketplace Plugin Creator

This skill wraps the two `npm` scripts that turn a canonical skill at `packages/skills-catalog/skills/(<category>)/<skill-name>/` into an entry the team can install via `/plugin install <plugin>@ckl-agent-skills`. The scripts handle every mechanical step — plugin manifest, symlinks, marketplace.json updates — so you never have to author `../../../` paths by hand.

## When to use

Use this skill when the user is in the `agent-skills` repo (working tree contains `.claude-plugin/marketplace.json`) and wants to make one or more existing skills installable through the CKL Claude marketplace.

If you're not sure whether the user is in this repo, check for `.claude-plugin/marketplace.json` at the repo root. If it's absent, this skill is not the right fit — surface that.

## Two flows

### A. Add one specific skill

Default. Use when the user names a single skill — e.g. "add `docs-writer` to our marketplace".

```
npm run marketplace:add -- <skill-name>
```

Optional flags:

- `--category=<cat>` — required only when the skill name exists in more than one category (the script will tell you).
- `--plugin=<name>` — override the default plugin name (`agent-skills-<category>`).
- `--description="..."` — override the auto-generated plugin description (only meaningful when the plugin is being created for the first time).

### B. Add every skill in a category at once

Use when the user wants bulk exposure — e.g. "expose all the architecture skills" or "add the performance category to the marketplace".

```
npm run marketplace:add-category -- <category>
```

The category arg is the inner name without parens — `architecture`, not `(architecture)`. The script lists available categories if you pass an unknown one.

## What the scripts do (so you can explain it if asked)

1. Locate the canonical skill source at `packages/skills-catalog/skills/(<category>)/<skill-name>/`.
2. Create `plugins/agent-skills-<category>/.claude-plugin/plugin.json` if it doesn't exist yet (idempotent).
3. Create a symlink at `plugins/agent-skills-<category>/skills/<skill-name>` pointing at the canonical source. Claude Code dereferences in-marketplace symlinks at install time, so no file duplication.
4. Add a plugin entry to `.claude-plugin/marketplace.json` if not already present.

Re-running with the same arguments is a no-op and reports "Nothing to do — already wired up." Safe to chain.

## After running the command

Tell the user:

1. **Review the diff.** `git status` should show changes only under `.claude-plugin/marketplace.json`, `plugins/agent-skills-<category>/`, and the new symlink.
2. **Commit and push.** Repo enforces signed commits; signing is already configured locally if a previous PR worked.
3. **Install locally to validate:**
   ```
   /plugin marketplace update
   /plugin install agent-skills-<category>@ckl-agent-skills
   ```
4. **Confirm in a session.** Ask Claude something that should trigger one of the newly-exposed skills; verify it loads via the Skill tool.

## Failure modes

- **"Skill 'X' not found in any category"** — the skill doesn't exist at `packages/skills-catalog/skills/(*)/X/`. Either typo the name, or the skill needs to be authored first (use `skill-architect`).
- **"Skill 'X' found in multiple categories"** — re-run with `--category=<cat>` to disambiguate.
- **"plugins/.../skills/X exists but points at '...'"** — the symlink target diverged from what the script expected. Investigate before clobbering; usually means a previous run with different flags.

## Do not use this skill for

- Authoring a new skill's content (use `skill-architect` instead, then come back here to expose it via the marketplace).
- Removing a plugin or skill from the marketplace — no `marketplace:remove` script yet; do it manually with `git rm` + edit `marketplace.json`.
- Editing skill SKILL.md content — the canonical file lives under `packages/skills-catalog/skills/`; edit it directly there.
- Anything outside this repo. This skill is project-scoped on purpose; it doesn't load for marketplace consumers.
