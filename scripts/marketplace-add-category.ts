#!/usr/bin/env tsx

import {
  defaultDescriptionForPlugin,
  ensureMarketplaceEntry,
  ensurePluginManifest,
  ensureSkillSymlink,
  listCategories,
  listSkillsInCategory,
  MarketplaceError,
  pluginNameForCategory,
  readMarketplace,
  writeMarketplace,
  type SkillLocation,
} from './_lib/marketplace'

interface ParsedArgs {
  category: string
  pluginName?: string
  description?: string
}

function parseArgs(argv: string[]): ParsedArgs {
  const positional: string[] = []
  const flags: Record<string, string> = {}

  for (const arg of argv) {
    if (arg.startsWith('--')) {
      const eq = arg.indexOf('=')
      if (eq === -1) {
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
      'Usage: tsx scripts/marketplace-add-category.ts <category> [--plugin=<plugin-name>] [--description="..."]',
    )
  }
  if (positional.length > 1) {
    throw new MarketplaceError(`Unexpected positional args: ${positional.slice(1).join(', ')}`)
  }

  return {
    category: positional[0],
    pluginName: flags.plugin,
    description: flags.description,
  }
}

function main(): void {
  const args = parseArgs(process.argv.slice(2))

  const available = listCategories()
  if (!available.includes(args.category)) {
    throw new MarketplaceError(
      `Category '${args.category}' not found. Available: ${available.join(', ')}`,
    )
  }

  const skillNames = listSkillsInCategory(args.category)
  if (skillNames.length === 0) {
    throw new MarketplaceError(`Category '(${args.category})' has no skills — nothing to add.`)
  }

  const pluginName = args.pluginName ?? pluginNameForCategory(args.category)
  const pluginDescription = args.description ?? defaultDescriptionForPlugin(args.category, skillNames.length)
  const ownerName = 'Cheesecake Labs'

  console.log(`→ Category:    (${args.category})`)
  console.log(`→ Plugin:      ${pluginName}`)
  console.log(`→ Skills:      ${skillNames.length}`)

  const pluginResult = ensurePluginManifest(pluginName, pluginDescription, ownerName)
  console.log(`  plugin.json: ${pluginResult.created ? 'created' : 'exists'}`)

  let createdCount = 0
  let alreadyCount = 0
  for (const skillName of skillNames) {
    const location: SkillLocation = {
      category: args.category,
      skillName,
      absPath: '',
    }
    const result = ensureSkillSymlink(pluginName, location)
    if (result.status === 'wrong-target') {
      throw new MarketplaceError(
        `plugins/${pluginName}/skills/${skillName} exists but points at '${result.currentTarget}', ` +
          `expected '${result.expectedTarget}'. Refusing to clobber.`,
      )
    }
    if (result.status === 'created') {
      createdCount++
      console.log(`  symlink:     created ${skillName}`)
    } else {
      alreadyCount++
    }
  }
  if (alreadyCount > 0) {
    console.log(`  symlinks:    ${alreadyCount} already-correct`)
  }

  const manifest = readMarketplace()
  const entryResult = ensureMarketplaceEntry(manifest, pluginName, pluginDescription)
  if (entryResult.added) {
    writeMarketplace(entryResult.manifest)
    console.log(`  marketplace: added entry`)
  } else {
    console.log(`  marketplace: entry already present`)
  }

  if (pluginResult.created || createdCount > 0 || entryResult.added) {
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
