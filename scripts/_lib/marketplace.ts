import { existsSync, mkdirSync, readdirSync, readFileSync, readlinkSync, symlinkSync, writeFileSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

import {
  CATEGORY_FOLDER_PATTERN,
  getFilesInDirectory,
  SKILL_NAME_SLUG_PATTERN,
} from '../../packages/skills-catalog/src/utils'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

export const REPO_ROOT = join(__dirname, '..', '..')
export const SKILLS_DIR = join(REPO_ROOT, 'packages', 'skills-catalog', 'skills')
export const PLUGINS_DIR = join(REPO_ROOT, 'plugins')
export const MARKETPLACE_PATH = join(REPO_ROOT, '.claude-plugin', 'marketplace.json')

export interface MarketplaceOwner {
  name: string
  email?: string
}

export interface MarketplacePluginEntry {
  name: string
  source: string
  description: string
}

export interface MarketplaceManifest {
  name: string
  owner: MarketplaceOwner
  metadata: {
    description: string
    version: string
    pluginRoot: string
  }
  plugins: MarketplacePluginEntry[]
}

export interface PluginManifest {
  name: string
  description: string
  author?: MarketplaceOwner
}

export interface SkillLocation {
  category: string
  skillName: string
  absPath: string
}

export class MarketplaceError extends Error {}

function isValidSkillName(name: string): boolean {
  return SKILL_NAME_SLUG_PATTERN.test(name)
}

export function categoryFolderName(category: string): string {
  return `(${category})`
}

export function pluginNameForCategory(category: string): string {
  return category
}

export function pluginDirFor(pluginName: string): string {
  return join(PLUGINS_DIR, pluginName)
}

export function skillsDirForPlugin(pluginName: string): string {
  return join(pluginDirFor(pluginName), 'skills')
}

export function symlinkTargetFor(category: string, skillName: string): string {
  return `../../../packages/skills-catalog/skills/${categoryFolderName(category)}/${skillName}`
}

export function listCategories(): string[] {
  if (!existsSync(SKILLS_DIR)) return []
  return readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && CATEGORY_FOLDER_PATTERN.test(entry.name))
    .map((entry) => {
      const match = entry.name.match(CATEGORY_FOLDER_PATTERN)
      return match ? match[1] : ''
    })
    .filter(Boolean)
}

export function listSkillsInCategory(category: string): string[] {
  const catDir = join(SKILLS_DIR, categoryFolderName(category))
  if (!existsSync(catDir)) return []
  return readdirSync(catDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith('.'))
    .map((entry) => entry.name)
}

export function findSkill(skillName: string, categoryHint?: string): SkillLocation[] {
  if (!isValidSkillName(skillName)) {
    throw new MarketplaceError(
      `Invalid skill name '${skillName}'. Must match ${SKILL_NAME_SLUG_PATTERN} (lowercase kebab-case).`,
    )
  }

  const matches: SkillLocation[] = []
  const categories = categoryHint ? [categoryHint] : listCategories()
  for (const category of categories) {
    const absPath = join(SKILLS_DIR, categoryFolderName(category), skillName)
    if (existsSync(absPath)) {
      matches.push({ category, skillName, absPath })
    }
  }
  return matches
}

export function readMarketplace(): MarketplaceManifest {
  if (!existsSync(MARKETPLACE_PATH)) {
    throw new MarketplaceError(`marketplace.json not found at ${MARKETPLACE_PATH}`)
  }
  const raw = readFileSync(MARKETPLACE_PATH, 'utf-8')
  return JSON.parse(raw) as MarketplaceManifest
}

export function writeMarketplace(manifest: MarketplaceManifest): void {
  writeFileSync(MARKETPLACE_PATH, JSON.stringify(manifest, null, 2) + '\n', 'utf-8')
}

export function ensureMarketplaceEntry(
  manifest: MarketplaceManifest,
  pluginName: string,
  description: string,
): { added: boolean; manifest: MarketplaceManifest } {
  const existing = manifest.plugins.find((p) => p.name === pluginName)
  if (existing) {
    return { added: false, manifest }
  }
  manifest.plugins.push({
    name: pluginName,
    source: `./plugins/${pluginName}`,
    description,
  })
  return { added: true, manifest }
}

export function ensurePluginManifest(pluginName: string, description: string, ownerName: string): { created: boolean } {
  const pluginDir = pluginDirFor(pluginName)
  const manifestDir = join(pluginDir, '.claude-plugin')
  const manifestPath = join(manifestDir, 'plugin.json')

  if (existsSync(manifestPath)) {
    return { created: false }
  }

  mkdirSync(manifestDir, { recursive: true })
  const manifest: PluginManifest = {
    name: pluginName,
    description,
    author: { name: ownerName },
  }
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n', 'utf-8')
  return { created: true }
}

export type SymlinkResult =
  | { status: 'created' }
  | { status: 'already-correct' }
  | { status: 'wrong-target'; currentTarget: string; expectedTarget: string }

export function ensureSkillSymlink(pluginName: string, location: SkillLocation): SymlinkResult {
  const skillsDir = skillsDirForPlugin(pluginName)
  mkdirSync(skillsDir, { recursive: true })

  const linkPath = join(skillsDir, location.skillName)
  const expectedTarget = symlinkTargetFor(location.category, location.skillName)

  if (existsSync(linkPath)) {
    let currentTarget: string
    try {
      currentTarget = readlinkSync(linkPath)
    } catch {
      throw new MarketplaceError(
        `${relative(REPO_ROOT, linkPath)} exists but is not a symlink. Refusing to clobber.`,
      )
    }
    if (currentTarget === expectedTarget) {
      return { status: 'already-correct' }
    }
    return { status: 'wrong-target', currentTarget, expectedTarget }
  }

  symlinkSync(expectedTarget, linkPath)
  return { status: 'created' }
}

export function defaultDescriptionForPlugin(category: string, skillCount: number): string {
  const noun = skillCount === 1 ? 'skill' : 'skills'
  return `${category} ${noun} from the CKL agent-skills catalog.`
}

export const STANDALONE_VENDOR_PREFIXES = [
  'tlc',
  'ckl',
  'aws',
  'cloudflare',
  'vercel',
  'netlify',
  'render',
  'shopify',
] as const

export const STANDALONE_THRESHOLDS = {
  payloadFiles: 10,
  skillMdLines: 500,
} as const

export type StandaloneSignalType = 'heavy-payload' | 'heavy-skill-md' | 'vendor-prefix'

export interface StandaloneSignal {
  type: StandaloneSignalType
  detail: string
}

export interface StandaloneCandidacy {
  isCandidate: boolean
  signals: StandaloneSignal[]
  suggestedPluginName: string
}

function countPayloadFiles(skillDir: string): number {
  if (!existsSync(skillDir)) return 0
  return getFilesInDirectory(skillDir).filter((f) => f !== 'SKILL.md').length
}

function countSkillMdLines(skillDir: string): number {
  const skillMdPath = join(skillDir, 'SKILL.md')
  if (!existsSync(skillMdPath)) return 0
  return readFileSync(skillMdPath, 'utf-8').split('\n').length
}

function matchedVendorPrefix(skillName: string): string | null {
  for (const prefix of STANDALONE_VENDOR_PREFIXES) {
    if (skillName.startsWith(`${prefix}-`)) return prefix
  }
  return null
}

export function evaluateStandaloneCandidacy(location: SkillLocation): StandaloneCandidacy {
  const signals: StandaloneSignal[] = []

  const payloadFiles = countPayloadFiles(location.absPath)
  if (payloadFiles >= STANDALONE_THRESHOLDS.payloadFiles) {
    signals.push({
      type: 'heavy-payload',
      detail: `${payloadFiles} non-SKILL.md files (threshold: ${STANDALONE_THRESHOLDS.payloadFiles})`,
    })
  }

  const skillMdLines = countSkillMdLines(location.absPath)
  if (skillMdLines >= STANDALONE_THRESHOLDS.skillMdLines) {
    signals.push({
      type: 'heavy-skill-md',
      detail: `SKILL.md is ${skillMdLines} lines (threshold: ${STANDALONE_THRESHOLDS.skillMdLines})`,
    })
  }

  const prefix = matchedVendorPrefix(location.skillName)
  if (prefix) {
    signals.push({
      type: 'vendor-prefix',
      detail: `name starts with '${prefix}-' (vendor/methodology prefix)`,
    })
  }

  return {
    isCandidate: signals.length > 0,
    signals,
    suggestedPluginName: location.skillName,
  }
}
