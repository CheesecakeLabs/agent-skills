#!/usr/bin/env tsx

import {
  defaultDescriptionForPlugin,
  ensureMarketplaceEntry,
  ensurePluginManifest,
  ensureSkillSymlink,
  evaluateStandaloneCandidacy,
  findSkill,
  listCategories,
  listSkillsInCategory,
  MarketplaceError,
  pluginNameForCategory,
  readMarketplace,
  writeMarketplace,
} from './_lib/marketplace'

const BOOLEAN_FLAGS = new Set(['bundle'])

interface ParsedArgs {
  skillName: string
  category?: string
  pluginName?: string
  description?: string
  bundle: boolean
}

function parseArgs(argv: string[]): ParsedArgs {
  const positional: string[] = []
  const flags: Record<string, string> = {}

  for (const arg of argv) {
    if (arg.startsWith('--')) {
      const eq = arg.indexOf('=')
      if (eq === -1) {
        const key = arg.slice(2)
        if (BOOLEAN_FLAGS.has(key)) {
          flags[key] = 'true'
          continue
        }
        throw new MarketplaceError(`Flag '${arg}' must be in --key=value form.`)
      }
      const key = arg.slice(2, eq)
      const value = arg.slice(eq + 1)
      flags[key] = value
    } else {
      positional.push(arg)
    }
  }

  if (positional.length === 0) {
    throw new MarketplaceError(
      'Usage: tsx scripts/marketplace-add-skill.ts <skill-name> [--category=<cat>] [--plugin=<plugin-name>] [--description="..."] [--bundle]',
    )
  }
  if (positional.length > 1) {
    throw new MarketplaceError(`Unexpected positional args: ${positional.slice(1).join(', ')}`)
  }

  return {
    skillName: positional[0],
    category: flags.category,
    pluginName: flags.plugin,
    description: flags.description,
    bundle: flags.bundle === 'true',
  }
}

function main(): void {
  const args = parseArgs(process.argv.slice(2))
  const matches = findSkill(args.skillName, args.category)

  if (matches.length === 0) {
    if (args.category) {
      throw new MarketplaceError(
        `Skill '${args.skillName}' not found in category '(${args.category})'. ` +
          `Try one of these categories: ${listCategories().join(', ')}`,
      )
    }
    throw new MarketplaceError(
      `Skill '${args.skillName}' not found in any category. ` +
        `Available categories: ${listCategories().join(', ')}`,
    )
  }

  if (matches.length > 1) {
    const cats = matches.map((m) => `(${m.category})`).join(', ')
    throw new MarketplaceError(
      `Skill '${args.skillName}' found in multiple categories: ${cats}. ` + `Re-run with --category=<cat>.`,
    )
  }

  const location = matches[0]

  const usingDefaultPlugin = !args.pluginName
  if (usingDefaultPlugin && !args.bundle) {
    const candidacy = evaluateStandaloneCandidacy(location)
    if (candidacy.isCandidate) {
      console.log(`→ Skill: ${args.skillName} (in (${location.category}))`)
      console.log('')
      console.log(`⚠️  Standalone candidate detected.`)
      for (const signal of candidacy.signals) {
        console.log(`   - ${signal.detail}`)
      }
      console.log('')
      console.log(`Choose one and re-run:`)
      console.log(`  Standalone plugin (recommended for flagships):`)
      console.log(`    npm run marketplace:add -- ${args.skillName} --plugin=${candidacy.suggestedPluginName}`)
      console.log(`  Bundle into category plugin '${pluginNameForCategory(location.category)}':`)
      console.log(`    npm run marketplace:add -- ${args.skillName} --bundle`)
      console.log('')
      console.log(`(No action taken — re-run with one of the above.)`)
      process.exit(2)
    }
  }

  const pluginName = args.pluginName ?? pluginNameForCategory(location.category)

  const pluginDescription =
    args.description ?? defaultDescriptionForPlugin(location.category, listSkillsInCategory(location.category).length)

  const ownerName = 'Cheesecake Labs'

  console.log(`→ Skill:       ${args.skillName} (in (${location.category}))`)
  console.log(`→ Plugin:      ${pluginName}`)

  const pluginResult = ensurePluginManifest(pluginName, pluginDescription, ownerName)
  console.log(`  plugin.json: ${pluginResult.created ? 'created' : 'exists'}`)

  const symlinkResult = ensureSkillSymlink(pluginName, location)
  if (symlinkResult.status === 'wrong-target') {
    throw new MarketplaceError(
      `plugins/${pluginName}/skills/${args.skillName} exists but points at '${symlinkResult.currentTarget}', ` +
        `expected '${symlinkResult.expectedTarget}'. Refusing to clobber.`,
    )
  }
  console.log(`  symlink:     ${symlinkResult.status}`)

  const manifest = readMarketplace()
  const entryResult = ensureMarketplaceEntry(manifest, pluginName, pluginDescription)
  if (entryResult.added) {
    writeMarketplace(entryResult.manifest)
    console.log(`  marketplace: added entry`)
  } else {
    console.log(`  marketplace: entry already present`)
  }

  if (pluginResult.created || symlinkResult.status === 'created' || entryResult.added) {
    console.log('')
    console.log(`Done. Try:`)
    console.log(`  /plugin marketplace update`)
    console.log(`  /plugin install ${pluginName}@${manifest.name}`)
  } else {
    console.log('')
    console.log(`Nothing to do — already wired up.`)
  }
}

try {
  main()
} catch (error) {
  if (error instanceof MarketplaceError) {
    console.error(`error: ${error.message}`)
    process.exit(1)
  }
  throw error
}
