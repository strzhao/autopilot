import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { CodexAppServerClient } from "./app-server-client.mjs";

const TOOL_VERSION = "0.1.0";
const DEFAULT_PLUGIN_NAME = "autopilot-codex";

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(MODULE_DIR, "..", "..");
const DEFAULT_MARKETPLACE_PATH = path.join(REPO_ROOT, ".agents", "plugins", "marketplace.json");
const DEFAULT_PLUGIN_ROOT = path.join(REPO_ROOT, "codex", "plugins", DEFAULT_PLUGIN_NAME);
const DEFAULT_MANIFEST_PATH = path.join(DEFAULT_PLUGIN_ROOT, ".codex-plugin", "plugin.json");
const HOME_DIR = os.homedir();
const HOME_AGENTS_DIR = path.join(HOME_DIR, ".agents");
const HOME_PLUGINS_DIR = path.join(HOME_AGENTS_DIR, "plugins");
const HOME_MARKETPLACE_PATH = path.join(HOME_PLUGINS_DIR, "marketplace.json");

function printUsage() {
  console.log(`string-codex-plugin ${TOOL_VERSION}

Usage:
  string-codex-plugin install [plugin-name] [--force-remote-sync] [--json]
  string-codex-plugin uninstall [plugin-name] [--force-remote-sync] [--json]
  string-codex-plugin list [--json]
  string-codex-plugin doctor [--json]
  string-codex-plugin sync-home-marketplace [plugin-name] [--json]
  string-codex-plugin help

Defaults:
  plugin-name: ${DEFAULT_PLUGIN_NAME}
  repo root:   ${REPO_ROOT}
  marketplace: ${DEFAULT_MARKETPLACE_PATH}`);
}

function parseArgs(argv) {
  const options = {
    command: "help",
    pluginName: DEFAULT_PLUGIN_NAME,
    forceRemoteSync: false,
    json: false,
    repoRoot: REPO_ROOT,
    marketplacePath: DEFAULT_MARKETPLACE_PATH,
    pluginRoot: DEFAULT_PLUGIN_ROOT,
    manifestPath: DEFAULT_MANIFEST_PATH,
  };

  const [command = "help", ...rest] = argv;
  options.command = command;

  const positionals = [];
  for (let index = 0; index < rest.length; index += 1) {
    const value = rest[index];

    if (value === "--force-remote-sync") {
      options.forceRemoteSync = true;
      continue;
    }

    if (value === "--json") {
      options.json = true;
      continue;
    }

    if (value === "--repo-root") {
      options.repoRoot = path.resolve(rest[index + 1]);
      index += 1;
      continue;
    }

    if (value === "--marketplace") {
      options.marketplacePath = path.resolve(rest[index + 1]);
      index += 1;
      continue;
    }

    if (value === "--plugin-root") {
      options.pluginRoot = path.resolve(rest[index + 1]);
      index += 1;
      continue;
    }

    if (value === "--manifest") {
      options.manifestPath = path.resolve(rest[index + 1]);
      index += 1;
      continue;
    }

    positionals.push(value);
  }

  if (positionals[0]) {
    options.pluginName = positionals[0];
  }

  return options;
}

async function pathExists(targetPath) {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function loadJson(targetPath) {
  const raw = await fs.readFile(targetPath, "utf8");
  return JSON.parse(raw);
}

function resolveRepoMarketplaceIdentity(localChecks) {
  const marketplace =
    localChecks.marketplace && typeof localChecks.marketplace === "object"
      ? localChecks.marketplace
      : {};

  return {
    name:
      typeof marketplace.name === "string" && marketplace.name
        ? marketplace.name
        : "string-codex-plugins",
    interface:
      marketplace.interface && typeof marketplace.interface === "object"
        ? marketplace.interface
        : {},
  };
}

function homePluginLinkPath(localChecks, pluginName) {
  const identity = resolveRepoMarketplaceIdentity(localChecks);
  return path.join(HOME_PLUGINS_DIR, identity.name, pluginName);
}

function homePluginSourcePath(localChecks, pluginName) {
  const identity = resolveRepoMarketplaceIdentity(localChecks);
  return `./.agents/plugins/${identity.name}/${pluginName}`;
}

async function collectHomeChecks(options, localChecks) {
  const linkPath = homePluginLinkPath(localChecks, options.pluginName);
  const homeMarketplaceExists = await pathExists(HOME_MARKETPLACE_PATH);
  const homePluginLinkExists = await pathExists(linkPath);

  let homeMarketplace = null;
  let homeMarketplaceError = null;
  if (homeMarketplaceExists) {
    try {
      homeMarketplace = await loadJson(HOME_MARKETPLACE_PATH);
    } catch (error) {
      homeMarketplaceError = error instanceof Error ? error.message : String(error);
    }
  }

  let homePluginLinkRealpath = null;
  let homePluginLinkError = null;
  if (homePluginLinkExists) {
    try {
      homePluginLinkRealpath = await fs.realpath(linkPath);
    } catch (error) {
      homePluginLinkError = error instanceof Error ? error.message : String(error);
    }
  }

  const homePluginEntryPath = Array.isArray(homeMarketplace?.plugins)
    ? homeMarketplace.plugins.find((plugin) => plugin?.name === options.pluginName)?.source?.path || ""
    : "";

  return {
    homeMarketplacePath: HOME_MARKETPLACE_PATH,
    homeMarketplaceExists,
    homeMarketplace,
    homeMarketplaceError,
    homePluginLinkPath: linkPath,
    homePluginLinkExists,
    homePluginLinkRealpath,
    homePluginLinkError,
    expectedHomePluginSourcePath: homePluginSourcePath(localChecks, options.pluginName),
    homePluginEntryPath,
  };
}

async function ensureHomeMarketplace(options, localChecks) {
  const repoIdentity = resolveRepoMarketplaceIdentity(localChecks);
  const linkPath = homePluginLinkPath(localChecks, options.pluginName);
  const sourcePath = homePluginSourcePath(localChecks, options.pluginName);

  await fs.mkdir(path.dirname(linkPath), { recursive: true });

  let shouldRewriteLink = true;
  try {
    const existingRealpath = await fs.realpath(linkPath);
    shouldRewriteLink = path.resolve(existingRealpath) !== path.resolve(options.pluginRoot);
  } catch {
    shouldRewriteLink = true;
  }

  if (shouldRewriteLink) {
    await fs.rm(linkPath, { recursive: true, force: true });
    await fs.symlink(
      options.pluginRoot,
      linkPath,
      process.platform === "win32" ? "junction" : "dir"
    );
  }

  let homeMarketplace = {};
  if (await pathExists(HOME_MARKETPLACE_PATH)) {
    homeMarketplace = await loadJson(HOME_MARKETPLACE_PATH);
    if (!homeMarketplace || typeof homeMarketplace !== "object" || Array.isArray(homeMarketplace)) {
      throw new Error(`Home marketplace must be a JSON object: ${HOME_MARKETPLACE_PATH}`);
    }
  }

  const nextMarketplace = {
    ...homeMarketplace,
    name:
      typeof homeMarketplace.name === "string" && homeMarketplace.name
        ? homeMarketplace.name
        : repoIdentity.name,
    interface: {
      ...repoIdentity.interface,
      ...(homeMarketplace.interface && typeof homeMarketplace.interface === "object"
        ? homeMarketplace.interface
        : {}),
    },
  };

  const plugins = Array.isArray(homeMarketplace.plugins) ? [...homeMarketplace.plugins] : [];
  const pluginEntry = {
    name: options.pluginName,
    source: {
      source: "local",
      path: sourcePath,
    },
  };

  const existingIndex = plugins.findIndex((plugin) => plugin?.name === options.pluginName);
  if (existingIndex >= 0) {
    plugins[existingIndex] = pluginEntry;
  } else {
    plugins.push(pluginEntry);
  }

  nextMarketplace.plugins = plugins;

  await fs.mkdir(HOME_PLUGINS_DIR, { recursive: true });
  await fs.writeFile(`${HOME_MARKETPLACE_PATH}`, `${JSON.stringify(nextMarketplace, null, 2)}\n`, "utf8");

  return {
    homeMarketplacePath: HOME_MARKETPLACE_PATH,
    homePluginLinkPath: linkPath,
    homePluginSourcePath: sourcePath,
    effectiveMarketplaceName: nextMarketplace.name,
    repoMarketplaceName: repoIdentity.name,
    reusedExistingMarketplaceName: nextMarketplace.name !== repoIdentity.name,
  };
}

async function collectLocalChecks(options) {
  const marketplaceExists = await pathExists(options.marketplacePath);
  const pluginRootExists = await pathExists(options.pluginRoot);
  const manifestExists = await pathExists(options.manifestPath);

  let marketplace = null;
  let marketplaceError = null;
  if (marketplaceExists) {
    try {
      marketplace = await loadJson(options.marketplacePath);
    } catch (error) {
      marketplaceError = error instanceof Error ? error.message : String(error);
    }
  }

  let manifest = null;
  let manifestError = null;
  if (manifestExists) {
    try {
      manifest = await loadJson(options.manifestPath);
    } catch (error) {
      manifestError = error instanceof Error ? error.message : String(error);
    }
  }

  return {
    repoRoot: options.repoRoot,
    marketplacePath: options.marketplacePath,
    pluginRoot: options.pluginRoot,
    manifestPath: options.manifestPath,
    marketplaceExists,
    pluginRootExists,
    manifestExists,
    marketplace,
    marketplaceError,
    manifest,
    manifestError,
  };
}

function findPluginInList(response, marketplacePath, pluginName) {
  const normalizedMarketplacePath = path.resolve(marketplacePath);

  for (const marketplace of response.marketplaces || []) {
    const marketplaceMatches = path.resolve(marketplace.path) === normalizedMarketplacePath;

    for (const plugin of marketplace.plugins || []) {
      if (!marketplaceMatches && plugin.name !== pluginName && plugin.id !== pluginName) {
        continue;
      }

      if (plugin.name === pluginName || plugin.id === pluginName || marketplaceMatches) {
        return {
          marketplace,
          plugin,
        };
      }
    }
  }

  return null;
}

function formatMarketplaceSummary(response, marketplacePath, pluginName) {
  const details = findPluginInList(response, marketplacePath, pluginName);
  if (!details) {
    return null;
  }

  return {
    marketplaceName: details.marketplace.name,
    marketplacePath: details.marketplace.path,
    pluginId: details.plugin.id,
    pluginName: details.plugin.name,
    installed: details.plugin.installed,
    enabled: details.plugin.enabled,
    installPolicy: details.plugin.installPolicy,
    authPolicy: details.plugin.authPolicy,
    source: details.plugin.source,
    interface: details.plugin.interface,
  };
}

async function withClient(options, task) {
  const client = new CodexAppServerClient({ cwd: options.repoRoot });
  try {
    const initialize = await client.start();
    return await task(client, initialize);
  } finally {
    await client.close();
  }
}

function printTextResult(result) {
  if (result.command === "list") {
    if (!result.plugin) {
      console.log(`Plugin ${result.pluginName} was not discovered from ${result.marketplacePath}.`);
      return;
    }

    console.log(`Marketplace: ${result.plugin.marketplaceName}`);
    console.log(`Plugin: ${result.plugin.pluginName}`);
    console.log(`Plugin ID: ${result.plugin.pluginId}`);
    console.log(`Installed: ${result.plugin.installed ? "yes" : "no"}`);
    console.log(`Enabled: ${result.plugin.enabled ? "yes" : "no"}`);
    console.log(`Marketplace path: ${result.plugin.marketplacePath}`);
    return;
  }

  if (result.command === "install") {
    console.log(`Installed ${result.pluginName}.`);
    console.log(`Plugin ID: ${result.plugin.pluginId}`);
    console.log(`Installed: ${result.plugin.installed ? "yes" : "no"}`);
    console.log(`Home marketplace: ${result.homeMarketplace.homeMarketplacePath}`);
    if (result.appsNeedingAuth.length > 0) {
      console.log(`Apps needing auth: ${result.appsNeedingAuth.join(", ")}`);
    }
    return;
  }

  if (result.command === "uninstall") {
    console.log(`Uninstalled ${result.pluginName}.`);
    return;
  }

  if (result.command === "doctor") {
    console.log(`Codex home: ${result.initialize.codexHome}`);
    for (const check of result.checks) {
      const label = check.ok ? "OK" : "FAIL";
      console.log(`${label}: ${check.name}${check.details ? ` - ${check.details}` : ""}`);
    }
    if (result.plugin) {
      console.log(`Plugin installed: ${result.plugin.installed ? "yes" : "no"}`);
      console.log(`Plugin enabled: ${result.plugin.enabled ? "yes" : "no"}`);
    }
    if (result.marketplaceLoadErrors.length > 0) {
      console.log("Marketplace load errors:");
      for (const entry of result.marketplaceLoadErrors) {
        console.log(`- ${entry.path}: ${entry.error}`);
      }
    }
    return;
  }

  if (result.command === "sync-home-marketplace") {
    console.log(`Synced home marketplace: ${result.homeMarketplace.homeMarketplacePath}`);
    console.log(`Plugin link: ${result.homeMarketplace.homePluginLinkPath}`);
    if (result.homeMarketplace.reusedExistingMarketplaceName) {
      console.log(
        `Marketplace name preserved: ${result.homeMarketplace.effectiveMarketplaceName}`
      );
    }
    return;
  }

  console.log(JSON.stringify(result, null, 2));
}

async function runList(options) {
  return withClient(options, async (client) => {
    const response = await client.request("plugin/list", {
      cwds: [options.repoRoot],
    });

    return {
      command: "list",
      pluginName: options.pluginName,
      marketplacePath: options.marketplacePath,
      plugin: formatMarketplaceSummary(response, options.marketplacePath, options.pluginName),
      marketplaces: response.marketplaces,
      marketplaceLoadErrors: response.marketplaceLoadErrors,
      featuredPluginIds: response.featuredPluginIds,
    };
  });
}

async function runInstall(options) {
  const localChecks = await collectLocalChecks(options);

  return withClient(options, async (client) => {
    await client.request("plugin/read", {
      marketplacePath: options.marketplacePath,
      pluginName: options.pluginName,
    });

    const installResponse = await client.request("plugin/install", {
      marketplacePath: options.marketplacePath,
      pluginName: options.pluginName,
      forceRemoteSync: options.forceRemoteSync,
    });

    const homeMarketplace = await ensureHomeMarketplace(options, localChecks);

    const listResponse = await client.request("plugin/list", {
      cwds: [options.repoRoot],
    });

    return {
      command: "install",
      pluginName: options.pluginName,
      plugin: formatMarketplaceSummary(listResponse, options.marketplacePath, options.pluginName),
      homeMarketplace,
      appsNeedingAuth: (installResponse.appsNeedingAuth || []).map((app) => app.name),
      authPolicy: installResponse.authPolicy,
      marketplaceLoadErrors: listResponse.marketplaceLoadErrors,
    };
  });
}

async function runUninstall(options) {
  return withClient(options, async (client) => {
    const listResponse = await client.request("plugin/list", {
      cwds: [options.repoRoot],
    });

    const details = findPluginInList(listResponse, options.marketplacePath, options.pluginName);
    if (!details || !details.plugin.installed) {
      return {
        command: "uninstall",
        pluginName: options.pluginName,
        skipped: true,
      };
    }

    await client.request("plugin/uninstall", {
      pluginId: details.plugin.id,
      forceRemoteSync: options.forceRemoteSync,
    });

    return {
      command: "uninstall",
      pluginName: options.pluginName,
      skipped: false,
      pluginId: details.plugin.id,
    };
  });
}

async function runDoctor(options) {
  const localChecks = await collectLocalChecks(options);
  const homeChecks = await collectHomeChecks(options, localChecks);

  return withClient(options, async (client, initialize) => {
    const listResponse = await client.request("plugin/list", {
      cwds: [options.repoRoot],
    });

    let pluginReadError = null;
    try {
      await client.request("plugin/read", {
        marketplacePath: options.marketplacePath,
        pluginName: options.pluginName,
      });
    } catch (error) {
      pluginReadError = error instanceof Error ? error.message : String(error);
    }

    const plugin = formatMarketplaceSummary(listResponse, options.marketplacePath, options.pluginName);
    const checks = [
      {
        name: "repo root exists",
        ok: await pathExists(options.repoRoot),
        details: options.repoRoot,
      },
      {
        name: "marketplace.json exists",
        ok: localChecks.marketplaceExists,
        details: options.marketplacePath,
      },
      {
        name: "marketplace.json parses",
        ok: localChecks.marketplaceExists && !localChecks.marketplaceError,
        details: localChecks.marketplaceError || "",
      },
      {
        name: "plugin root exists",
        ok: localChecks.pluginRootExists,
        details: options.pluginRoot,
      },
      {
        name: "plugin manifest exists",
        ok: localChecks.manifestExists,
        details: options.manifestPath,
      },
      {
        name: "plugin manifest parses",
        ok: localChecks.manifestExists && !localChecks.manifestError,
        details: localChecks.manifestError || "",
      },
      {
        name: "plugin readable through app-server",
        ok: !pluginReadError,
        details: pluginReadError || "",
      },
      {
        name: "repo marketplace discovered by app-server",
        ok: Boolean(plugin),
        details: plugin ? plugin.marketplaceName : "",
      },
      {
        name: "home marketplace.json exists",
        ok: homeChecks.homeMarketplaceExists,
        details: homeChecks.homeMarketplacePath,
      },
      {
        name: "home marketplace.json parses",
        ok: homeChecks.homeMarketplaceExists && !homeChecks.homeMarketplaceError,
        details: homeChecks.homeMarketplaceError || "",
      },
      {
        name: "home marketplace includes plugin entry",
        ok:
          homeChecks.homeMarketplaceExists &&
          !homeChecks.homeMarketplaceError &&
          homeChecks.homePluginEntryPath === homeChecks.expectedHomePluginSourcePath,
        details: homeChecks.homePluginEntryPath || "",
      },
      {
        name: "home plugin link exists",
        ok: homeChecks.homePluginLinkExists,
        details: homeChecks.homePluginLinkPath,
      },
      {
        name: "home plugin link resolves to repo plugin root",
        ok:
          homeChecks.homePluginLinkExists &&
          !homeChecks.homePluginLinkError &&
          path.resolve(homeChecks.homePluginLinkRealpath || "") === path.resolve(options.pluginRoot),
        details: homeChecks.homePluginLinkError || homeChecks.homePluginLinkRealpath || "",
      },
    ];

    return {
      command: "doctor",
      initialize,
      checks,
      pluginName: options.pluginName,
      plugin,
      marketplaceLoadErrors: listResponse.marketplaceLoadErrors,
    };
  });
}

async function runSyncHomeMarketplace(options) {
  const localChecks = await collectLocalChecks(options);
  const homeMarketplace = await ensureHomeMarketplace(options, localChecks);

  return {
    command: "sync-home-marketplace",
    pluginName: options.pluginName,
    homeMarketplace,
  };
}

export async function runCli(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);

  if (options.command === "help" || options.command === "--help" || options.command === "-h") {
    printUsage();
    return 0;
  }

  let result;
  switch (options.command) {
    case "list":
      result = await runList(options);
      break;
    case "install":
      result = await runInstall(options);
      break;
    case "uninstall":
      result = await runUninstall(options);
      break;
    case "doctor":
      result = await runDoctor(options);
      break;
    case "sync-home-marketplace":
      result = await runSyncHomeMarketplace(options);
      break;
    default:
      printUsage();
      return 1;
  }

  if (options.json) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    printTextResult(result);
  }

  if (result.command === "doctor") {
    return result.checks.every((check) => check.ok) ? 0 : 1;
  }

  return 0;
}
