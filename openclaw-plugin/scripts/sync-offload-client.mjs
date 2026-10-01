/**
 * Sync src/offload-client from the repo root into this plugin package.
 *
 * Why: openclaw-plugin is loaded from ~/.openclaw's plugin registry, which packs
 * it into a temp capture dir using package.json "files". Anything outside the
 * plugin directory is NOT shipped, so a relative import of "../src/..." breaks at
 * load time with ERR_MODULE_NOT_FOUND.
 *
 * The repo root src/offload-client is the single source of truth. This script
 * copies the .ts sources in before tsc runs. The copy under src/offload-client/
 * is generated and gitignored — edit the original, never this copy.
 */

import { cpSync, existsSync, mkdirSync, readdirSync, rmSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const pluginRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const sourceRoot = join(pluginRoot, "..", "src", "offload-client");
const targetRoot = join(pluginRoot, "src", "offload-client");

if (!existsSync(sourceRoot)) {
  console.error(`[sync-offload-client] source not found: ${sourceRoot}`);
  process.exit(1);
}

/** Remove target first so files deleted upstream do not linger as stale output. */
rmSync(targetRoot, { recursive: true, force: true });
mkdirSync(targetRoot, { recursive: true });

/** Copy .ts sources only — never the stale .js/.d.ts build artifacts upstream. */
const isSourceFile = (path) => path.endsWith(".ts") && !path.endsWith(".d.ts");

cpSync(sourceRoot, targetRoot, {
  recursive: true,
  filter: (src) => statSync(src).isDirectory() || isSourceFile(src),
});

const copied = readdirSync(targetRoot, { recursive: true })
  .filter((entry) => typeof entry === "string" && isSourceFile(entry))
  .map((entry) => relative(pluginRoot, join(targetRoot, entry)))
  .sort();

console.log(`[sync-offload-client] ${copied.length} file(s) -> ${relative(pluginRoot, targetRoot)}`);
for (const file of copied) console.log(`[sync-offload-client]   ${file}`);
