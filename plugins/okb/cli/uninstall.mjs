// okb.mjs uninstall: takes Real Agent's install back off a computer, and keeps the person's work.
//
//   node okb.mjs uninstall [--yes] [--remove-work]
//
// It lists what it removes, what it keeps and what it leaves, and asks the person to type yes. --yes answers it.
// It removes each plugin from the real-agent marketplace and the marketplace itself, with Claude Code's own commands,
// then what Claude Code leaves of them in its settings and plugin folders. It removes each copy of the firm's
// marketplace okb sync made, okb-marketplace in the home folder and the copy Claude Code's settings name, with the
// files beside it, the whisper folder the install script fills and the install script's files in the temporary
// folder. It signs out each saved sign-in to a project one of the person's folders, the okb plugin's settings or a
// copy names, and deletes its file; a sign-in whose sign-out fails stays. Without a working claude command, the
// plugins, the marketplace and their settings stay. It keeps each folder the okb plugin's settings name, and each
// folder in the home folder or a folder in it that okb setup made: one holding an actor file, with any upload folder
// an older setup named, or one whose .claude/settings.json names an agent of Real Agent's plugins or of a plugin from
// the real-agent marketplace, signed in or not; it deletes the actor file and the agent setting in each. --remove-work also deletes those folders, once the person
// types delete, which --yes does not answer. It leaves the programs the install added, and every other marketplace,
// and names the uninstall guide, which gives their commands. It prints one line per item, and exits 1 when an item
// could not be removed.
import process from "node:process";
import { spawnSync } from "node:child_process";
import { existsSync, lstatSync, readdirSync, readFileSync, rmdirSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { ACTOR_FILE } from "../mcp/lib/actor-file.mjs";
import { PROJECT_REF, refreshSession } from "../mcp/lib/session.mjs";
import { removeFolder } from "./sync.mjs";
import { MARKETPLACE_NAME } from "./releases.mjs";

export const UNINSTALL_USAGE = `Usage: node okb.mjs uninstall [--yes] [--remove-work]

uninstall takes Real Agent's install off this computer: the plugins from the ${MARKETPLACE_NAME} marketplace and the
marketplace itself, your copy of your firm's plugins, the whisper folder the install script fills, and your sign-ins
to your firm's OKB. It keeps your folders. It lists each first, and asks you to type yes. --yes answers yes.
--remove-work also deletes your folders, once you type delete.`;

// On Windows, claude may be a .cmd that only a shell runs, and a shell takes one command line.
const shellWord = word => /[\s"&|<>^]/.test(word) ? `"${word.replaceAll('"', '\\"')}"` : word;
const claudeCommand = (args, cwd) => process.platform === "win32"
  ? spawnSync(`claude ${args.map(shellWord).join(" ")}`, { encoding: "utf8", shell: true, cwd, stdio: ["ignore", "pipe", "pipe"] })
  : spawnSync("claude", args, { encoding: "utf8", cwd, stdio: ["ignore", "pipe", "pipe"] });

/** What Claude Code said, or why it could not be run. */
const said = ran => `${ran.stdout ?? ""}${ran.stderr ?? ""}`.trim() || ran.error?.message || `exit code ${ran.status}`;

/** The list a claude list command prints, or null with Claude Code's words when it cannot be run or prints none. */
function claudeList(claude, args) {
  const ran = claude([...args, "--json"]);
  if (ran.error || ran.status !== 0) return { list: null, why: said(ran) };
  try { const list = JSON.parse(ran.stdout); if (Array.isArray(list)) return { list }; } catch {}
  return { list: null, why: said(ran) };
}

const readJson = file => { try { return JSON.parse(readFileSync(file, "utf-8")); } catch { return null; } };
const there = path => { try { lstatSync(path); return true; } catch { return false; } };

/** One line from the person. Without a terminal, the next line of the input, or "" once it ends. */
export function terminalAsk() {
  let piped = null;
  return prompt => {
    process.stdout.write(prompt);
    if (!process.stdin.isTTY) {
      try { piped ??= readFileSync(0, "utf8").split(/\r?\n/); } catch { piped = []; }
      process.stdout.write("\n");
      return Promise.resolve((piped.shift() ?? "").trim());
    }
    const line = createInterface({ input: process.stdin });
    return new Promise(done => line.once("line", answer => { line.close(); done(answer.trim()); }));
  };
}

/** Signs out one saved sign-in: refreshes it, then calls Supabase Auth's logout with the access token. Returns null, or the problem. */
async function signOut(file) {
  const saved = readJson(file);
  if (!saved?.url || !saved?.publishableKey || !saved?.refreshToken) return "the file holds no sign-in";
  try {
    const renewed = await refreshSession(saved.url, saved.publishableKey, saved.refreshToken);
    if (!renewed.ok) return `the project refused the sign-in: ${renewed.problem}`;
    const response = await fetch(`${saved.url}/auth/v1/logout?scope=local`, {
      method: "POST",
      headers: { apikey: saved.publishableKey, Authorization: `Bearer ${renewed.body.access_token}` },
    });
    return response.ok ? null : `the project answered HTTP ${response.status}`;
  } catch (err) {
    return `the project could not be reached: ${err?.cause?.code ?? err?.message ?? err}`;
  }
}

/** Real Agent's own plugins, whose agents a folder okb setup made names. A firm's workflow plugins are the others
 * installed from the real-agent marketplace. */
export const REAL_AGENT_PLUGINS = ["business-analyst", "real-agent", "real-agent-internal", "okb"];

/** The local folder a file:// git source names, or null. */
function sourceFolder(url) {
  if (typeof url !== "string" || !url.startsWith("file://")) return null;
  try { return fileURLToPath(url); } catch { return null; }
}

/** Everything the uninstall acts on, read before anything is removed. */
export function survey({ home, configDir, temp, platform, claude, localAppData = process.env.LOCALAPPDATA }) {
  const settings = readJson(join(configDir, "settings.json")) ?? {};
  const pluginList = claudeList(claude, ["plugin", "list"]);
  const marketplaceList = pluginList.list ? claudeList(claude, ["plugin", "marketplace", "list"]) : pluginList;
  const installed = pluginList.list ?? [];
  const seen = new Set();
  const plugins = installed.filter(p => {
    const key = `${p?.id} ${p?.scope} ${p?.projectPath ?? ""}`;
    if (typeof p?.id !== "string" || !p.id.endsWith(`@${MARKETPLACE_NAME}`) || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  const marketplaces = (marketplaceList.list ?? []).map(m => m?.name);
  const options = settings.pluginConfigs?.[`okb@${MARKETPLACE_NAME}`]?.options ?? {};

  // The person's work: the folders the okb plugin's settings name, and each folder holding an actor file in the home
  // folder or a folder in it, with the upload folder an older actor file names.
  const work = [];
  const refs = new Set();
  const keep = (folder, kind) => {
    if (typeof folder !== "string" || !folder.trim()) return;
    const full = resolve(folder);
    if (full === resolve(home) || work.some(w => w.folder === full) || !existsSync(full)) return;
    work.push({ folder: full, kind });
  };
  keep(options.agent_folder, "agent");
  keep(options.upload_folder, "upload");
  if (PROJECT_REF.test(String(options.project_ref ?? ""))) refs.add(options.project_ref);
  const folders = under => { try { return readdirSync(under, { withFileTypes: true }).filter(e => e.isDirectory() && !e.name.startsWith(".")).map(e => join(under, e.name)); } catch { return []; } };
  // A folder okb setup made names one of Real Agent's agents in its .claude/settings.json, signed in or not, such as
  // the owner's setup folder before its first sign-in.
  const ours = new Set([...REAL_AGENT_PLUGINS, ...plugins.map(p => p.id.slice(0, -`@${MARKETPLACE_NAME}`.length))]);
  const namesOurAgent = folder => {
    const agent = readJson(join(folder, ".claude", "settings.json"))?.agent;
    return typeof agent === "string" && ours.has(agent.split(":")[0]) && agent.includes(":");
  };
  for (const folder of folders(home).flatMap(one => [one, ...folders(one)])) {
    if (!existsSync(join(folder, ACTOR_FILE))) {
      if (namesOurAgent(folder)) keep(folder, "agent");
      continue;
    }
    keep(folder, "agent");
    const actor = readJson(join(folder, ACTOR_FILE));
    keep(actor?.upload_folder, "upload");
    if (PROJECT_REF.test(String(actor?.project_ref ?? ""))) refs.add(actor.project_ref);
  }

  // The copies of the firm's marketplace: okb-marketplace in the home folder, a copy for each project, and the copy
  // Claude Code's settings name as the real-agent marketplace's source, with the files okb sync keeps beside it.
  const copies = join(home, "okb-marketplace");
  for (const ref of (() => { try { return readdirSync(copies); } catch { return []; } })()) {
    const ref0 = ref.replace(/\.(incoming|old|lock|workflows)$/, "");
    if (PROJECT_REF.test(ref0)) refs.add(ref0);
  }
  const known = readJson(join(configDir, "plugins", "known_marketplaces.json"))?.[MARKETPLACE_NAME];
  const registered = sourceFolder(known?.source?.url) ?? sourceFolder(settings.extraKnownMarketplaces?.[MARKETPLACE_NAME]?.source?.url);
  const outside = registered && !resolve(registered).startsWith(`${resolve(copies)}${process.platform === "win32" ? "\\" : "/"}`) && resolve(registered) !== resolve(home)
    ? ["", ".incoming", ".old", ".lock", ".workflows"].map(end => `${resolve(registered)}${end}`) : [];

  const signIns = [];
  for (const ref of [...refs].sort()) {
    let files = [];
    try { files = readdirSync(join(home, ".config", "supabase-auth", ref)).filter(f => f.endsWith(".json") && !f.startsWith(".")); } catch {}
    for (const file of files) signIns.push({ ref, email: file.slice(0, -5), file: join(home, ".config", "supabase-auth", ref, file) });
  }

  const whisper = platform === "win32" ? join(localAppData || join(home, "AppData", "Local"), "okb") : join(home, ".local", "share", "okb");
  let tempNames = [];
  try { tempNames = readdirSync(temp); } catch {}
  const tempFiles = tempNames
    .filter(n => n === "okb-install.log" || /^okb-install-admin-.*\.log$/.test(n) || /^okb-install-(log|stage)\.[A-Za-z0-9]+$/.test(n)
      || n === "whisper-bin-x64.zip" || /^node-v26\.[\d.]+-(x64|arm64)\.msi$/.test(n))
    .map(n => join(temp, n));
  const files = [copies, ...outside, whisper, ...tempFiles].filter(there);

  return { claudeProblem: pluginList.list && marketplaceList.list ? null : (pluginList.why ?? marketplaceList.why), plugins, marketplace: marketplaces.includes(MARKETPLACE_NAME), work, signIns, files };
}

/** Deletes each key in a JSON file's objects that `drop` picks. Returns one line per key deleted. */
function dropKeys(file, objects, drop) {
  const value = readJson(file);
  if (!value || typeof value !== "object") return [];
  const gone = [];
  for (const name of objects) {
    const object = name ? value[name] : value;
    if (!object || typeof object !== "object") continue;
    for (const key of Object.keys(object)) if (drop(key)) { delete object[key]; gone.push(`Removed ${name ? `${name}.` : ""}${key} from ${file}.`); }
  }
  if (gone.length) writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
  return gone;
}

/**
 * Deletes what Claude Code left of the real-agent marketplace and its plugins: their keys in settings.json, in
 * known_marketplaces.json and in installed_plugins.json, the marketplace's clone and plugin cache, and the okb plugin's
 * data folder. Returns one line per item deleted.
 */
export function clearClaude(configDir) {
  const ours = key => key.endsWith(`@${MARKETPLACE_NAME}`);
  const plugins = join(configDir, "plugins");
  const gone = [
    ...dropKeys(join(configDir, "settings.json"), ["pluginConfigs", "enabledPlugins"], ours),
    ...dropKeys(join(configDir, "settings.json"), ["extraKnownMarketplaces"], key => key === MARKETPLACE_NAME),
    ...dropKeys(join(plugins, "known_marketplaces.json"), [""], key => key === MARKETPLACE_NAME),
    ...dropKeys(join(plugins, "installed_plugins.json"), ["plugins"], ours),
  ];
  // The okb plugin's data folder holds okb sync's record of each upload folder it named.
  for (const folder of [join(plugins, "marketplaces", MARKETPLACE_NAME), join(plugins, "cache", MARKETPLACE_NAME), join(plugins, "data", `okb-${MARKETPLACE_NAME}`)]) {
    if (!there(folder)) continue;
    removeFolder(folder);
    gone.push(`Removed ${folder}.`);
  }
  return gone;
}

/** Deletes a folder's actor file and the agent key in its .claude/settings.json. Returns what it deleted. */
function clearFolder(folder) {
  const gone = [];
  const actor = join(folder, ACTOR_FILE);
  if (there(actor)) { rmSync(actor, { force: true }); gone.push(actor); }
  const file = join(folder, ".claude", "settings.json");
  const settings = readJson(file);
  if (settings && typeof settings === "object" && !Array.isArray(settings) && "agent" in settings) {
    delete settings.agent;
    if (Object.keys(settings).length) writeFileSync(file, `${JSON.stringify(settings, null, 2)}\n`);
    else {
      rmSync(file, { force: true });
      try { rmdirSync(dirname(file)); } catch {}
    }
    gone.push(`the agent setting in ${file}`);
  }
  return gone;
}

/**
 * Runs the uninstall. Returns 0 when each item is removed, 1 when one could not be, and 2 for a wrong option.
 * `ask` takes a prompt and gives the person's answer.
 */
export async function uninstall(argv, {
  home = homedir(), configDir = process.env.CLAUDE_CONFIG_DIR || join(home, ".claude"), temp = tmpdir(), platform = process.platform,
  claude = claudeCommand, ask = terminalAsk(), say = line => process.stdout.write(`${line}\n`), fail = line => process.stderr.write(`${line}\n`),
} = {}) {
  const yes = argv.includes("--yes"), removeWork = argv.includes("--remove-work");
  const wrong = argv.find(w => w !== "--yes" && w !== "--remove-work");
  if (wrong) { fail(`${wrong} is not an option of uninstall.\n${UNINSTALL_USAGE}`); return 2; }
  const s = survey({ home, configDir, temp, platform, claude });

  say("This removes:");
  for (const p of s.plugins) say(`  the ${p.id} plugin`);
  if (s.marketplace) say(`  the ${MARKETPLACE_NAME} marketplace`);
  for (const one of s.signIns) say(`  the sign-in of ${one.email} to project ${one.ref}, ${one.file}`);
  for (const file of s.files) say(`  ${file}`);
  say(removeWork ? "This deletes your work, once you type delete:" : "This keeps your work:");
  for (const w of s.work) say(`  ${w.folder}`);
  if (!s.work.length) say("  no folder of yours is on this computer");
  if (!yes && await ask("Type yes to uninstall Real Agent from this computer: ") !== "yes") { say("Nothing was removed."); return 0; }
  let deleteWork = false;
  if (removeWork && s.work.length) {
    deleteWork = await ask(`Type delete to delete ${s.work.map(w => w.folder).join(", ")} and every file in them: `) === "delete";
    if (!deleteWork) say("Your work stays.");
  }

  let failed = 0;
  const problem = line => { failed += 1; say(line); };

  for (const one of s.signIns) {
    const why = await signOut(one.file);
    if (why) { problem(`The sign-out of ${one.email} failed: ${why}. The sign-in stays in ${one.file}. Run this again once the project can be reached.`); continue; }
    say(`Signed out ${one.email} from project ${one.ref}.`);
    rmSync(one.file, { force: true });
    say(`Removed ${one.file}.`);
    try { rmdirSync(dirname(one.file)); } catch {}
  }

  // Claude Code's own records of the plugins go only once Claude Code has removed the plugins and the marketplace.
  let removed = !s.claudeProblem;
  if (s.claudeProblem) problem(`Claude Code's claude command could not be run: ${s.claudeProblem}. The ${MARKETPLACE_NAME} plugins and marketplace stay, with their settings. Run this again once claude runs.`);
  for (const p of s.plugins) {
    const cwd = typeof p.projectPath === "string" && existsSync(p.projectPath) ? p.projectPath : undefined;
    const ran = claude(["plugin", "uninstall", p.id, ...(p.scope ? ["--scope", p.scope] : [])], cwd);
    if (ran.error || ran.status !== 0) { removed = false; problem(`The ${p.id} plugin could not be removed. Claude Code said: ${said(ran)}`); }
    else say(`Removed the ${p.id} plugin.`);
  }
  if (s.marketplace) {
    const ran = claude(["plugin", "marketplace", "remove", MARKETPLACE_NAME]);
    if (ran.error || ran.status !== 0) { removed = false; problem(`The ${MARKETPLACE_NAME} marketplace could not be removed. Claude Code said: ${said(ran)}`); }
    else say(`Removed the ${MARKETPLACE_NAME} marketplace.`);
  }
  if (removed) {
    try { for (const line of clearClaude(configDir)) say(line); }
    catch (err) { problem(err?.message ?? String(err)); }
  }

  for (const file of s.files) {
    try {
      if (lstatSync(file).isDirectory()) removeFolder(file);
      else rmSync(file, { force: true });
      say(`Removed ${file}.`);
    } catch (err) {
      problem(err?.message ?? `${file} could not be removed.`);
    }
  }

  for (const w of s.work) {
    for (const gone of clearFolder(w.folder)) say(`Removed ${gone}.`);
    if (deleteWork) {
      try { removeFolder(w.folder); say(`Deleted ${w.folder}.`); }
      catch (err) { problem(err?.message ?? `${w.folder} could not be deleted.`); }
    } else say(`Kept ${w.folder}.`);
  }

  say("Your other plugins and the programs the install added stay. The uninstall guide, uninstall.md in Real Agent's support guides, gives the command that removes each.");
  say("Your account and grants stay in your firm's OKB. Your administrator removes them.");
  if (failed) fail(`${failed} item${failed === 1 ? "" : "s"} could not be removed. Each is named above.`);
  return failed ? 1 : 0;
}
