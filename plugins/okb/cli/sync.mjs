// okb.mjs sync: keeps a person's plugins up to date from their client's own OKB.
//
//   node okb.mjs sync [--project <ref> --email <email>] [--into <local folder>]
//
// Real Agent publishes each release of the client's plugins to the Plugins scope's bucket. sync lists
// and downloads them signed in as the person: the sign-in --project and --email name, else the one the
// current folder's actor file names, else the only one saved. It downloads the newest release newer than
// the local copy's RELEASE, checks every file against the release's MANIFEST, and swaps the copy in only
// when every file matches. A folder with no MANIFEST is a publish under way and is passed over; a release
// that fails its check is reported and passed over, and the next older one is taken. It then reads every
// workflow plugin scope, plugins_<workflow>, the person's grants reach, as okb_get_scopes lists them, and puts
// the newest release of each into the copy at plugins/<name>, listed in the copy's marketplace.json. A workflow
// plugin whose scope the person no longer reaches is taken out of the copy. The copy, by default
// okb-marketplace/<project reference> in the home folder, is a Git repository, and each release is
// committed to it. sync then registers the copy as the real-agent marketplace in Claude Code's settings,
// as a git source with a file:// URL, in place of Real Agent's public copy. It runs
// `claude plugin marketplace update real-agent`, and `claude plugin update` for each plugin installed
// from it, and prints each one's old and new version, and each plugin of the release not installed.
// It then prints, once, each old upload folder holding files, with the folder to move them into. A folder whose agent
// setting names the database admin, which the business analyst replaced, is moved to the business analyst, whose
// plugin is installed when it is not.
// It exits 0 when every step worked, or when the Plugins scope shows the person no release yet, and 1
// when a step failed.
import process from "node:process";
import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";
import { check, downloadRelease, isPluginScope, listReleases, MARKETPLACE_NAME, OWN_PLUGIN_NAMES, pluginScope, RELEASE_NAME, workflowPlugin } from "./releases.mjs";
import { callRpc } from "../mcp/lib/session.mjs";
import { openAccess } from "./okb-session.mjs";
import { ACTOR_FILE } from "../mcp/lib/actor-file.mjs";
import { madeBySetup } from "../mcp/lib/session-folder.mjs";

export { check, MARKETPLACE_NAME, RELEASE_NAME };

export const SYNC_USAGE = `Usage: node okb.mjs sync [--project <ref> --email <email>] [--into <local folder>]

sync installs the newest release of your firm's plugins from the Plugins scope of your firm's OKB,
signed in as you: in your folder, as the folder's person, or as --project and --email. It checks
every file against the release's MANIFEST, keeps the release as a Git copy in --into, by default
okb-marketplace/<project reference> in your home folder, registers that copy in Claude Code as the
${MARKETPLACE_NAME} marketplace, and updates each plugin installed from it.`;

/** The command line's options. Throws with SYNC_USAGE when they are unreadable. */
export function parseSync(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const word = argv[i];
    if (["--project", "--email", "--into"].includes(word) && argv[i + 1] !== undefined && !argv[i + 1].startsWith("--")) out[word.slice(2)] = argv[++i];
    else throw new Error(`${word} is not an option of sync.\n${SYNC_USAGE}`);
  }
  if ((out.project === undefined) !== (out.email === undefined)) throw new Error(`--project and --email go together.\n${SYNC_USAGE}`);
  return out;
}

/** The local copy for a project: --into, or okb-marketplace/<ref> in the home folder. */
export const localCopy = (ref, into, home = homedir()) => resolve(into ?? join(home, "okb-marketplace", ref));

/** The release folders in the Plugins scope, newest first. Throws with Storage's words when they cannot be listed. */
export async function releases(access) {
  const listed = await listReleases(access);
  if (!listed.ok) throw new Error(`The releases in OKB could not be listed: ${listed.problem}`);
  return listed.names;
}

/** A folder this command cannot remove, with the command that removes it. */
export class StuckFolder extends Error {
  constructor(folder, err) {
    const command = process.platform === "win32" ? `Remove-Item -Recurse -Force "${folder}"` : `rm -rf "${folder}"`;
    super(`The folder ${folder} could not be removed (${err.code ?? err.message}). Close any program with a file open in it, then remove it with:\n  ${command}`);
    this.folder = folder;
  }
}

/** Gives the owner write on a folder and all it holds, so a read-only copy can be replaced. */
export function makeWritable(folder) {
  let stat;
  try { stat = lstatSync(folder); } catch { return; }
  if (stat.isSymbolicLink()) return;
  if (stat.isDirectory()) {
    if ((stat.mode & 0o700) !== 0o700) chmodSync(folder, stat.mode | 0o700);
    for (const name of readdirSync(folder)) makeWritable(join(folder, name));
  } else if ((stat.mode & 0o600) !== 0o600) chmodSync(folder, stat.mode | 0o600);
}

/** Removes a folder and all it holds, with Node's own retries. Throws StuckFolder when the folder stays. */
export function removeFolder(folder, remove = rmSync) {
  try { makeWritable(folder); remove(folder, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }); }
  catch (err) { throw new StuckFolder(folder, err); }
}

/** Another sync, still going, holds the lock beside the copy. */
export class SyncRunning extends Error {}

/** Takes the lock beside the copy, `<local>.lock`, holding this run's process id, and frees it when the
 * run ends. A lock whose process has ended is taken over. Throws SyncRunning while another run holds it. */
export function takeLock(local) {
  const lock = `${local}.lock`;
  mkdirSync(dirname(lock), { recursive: true });
  for (let tries = 0; tries < 2; tries++) {
    try {
      writeFileSync(lock, `${process.pid}\n`, { flag: "wx" });
      process.on("exit", () => { try { rmSync(lock, { force: true }); } catch {} });
      return lock;
    } catch (err) {
      if (err.code !== "EEXIST") throw err;
      const pid = Number(readFileSync(lock, "utf8").trim());
      let running = false;
      try { process.kill(pid, 0); running = Number.isInteger(pid) && pid > 0; } catch (e) { running = e.code === "EPERM"; }
      if (running) throw new SyncRunning(`Another okb sync is still copying, as process ${pid}. Wait for it to finish, then run okb sync again if you need to.`);
      rmSync(lock, { force: true });
    }
  }
  throw new SyncRunning(`The lock ${lock} could not be taken. Run okb sync again.`);
}

/** Where this process runs inside local, as a path relative to it, or null when it runs elsewhere. */
function placeIn(local) {
  let here;
  try { here = realpathSync(process.cwd()); } catch { return null; }
  let base;
  try { base = realpathSync(local); } catch { return null; }
  const place = relative(base, here);
  return place === "" || (!place.startsWith("..") && !isAbsolute(place)) ? place : null;
}

/** For a run inside the copy at local, moves this process out to the folder holding the copy before the swap, and
 * returns the step that moves it back to the same place in the new copy, or to the copy itself where the new copy has
 * no such folder. Returns null for a run elsewhere. A run left in the folder the swap deletes fails each command it
 * starts. */
export function stepOutOf(local) {
  const place = placeIn(local);
  if (place === null) return null;
  try { process.chdir(dirname(local)); } catch { return null; }
  return () => { try { process.chdir(existsSync(join(local, place)) ? join(local, place) : local); } catch { /* it stays beside the copy */ } };
}

/** The line that ends a run started inside the copy: the terminal that started it is still in the replaced copy. */
export const backInto = local => `This terminal was in the copy that was replaced. Run: cd "${local}"`;

/** Thrown on Windows by a run inside the copy, before anything is downloaded: the terminal that started it holds the
 * folder, and Windows renames no folder a terminal is in. */
export class InsideCopy extends Error {
  constructor() { super("This terminal is in your copy, which the update replaces. Run cd ~, then run okb sync again."); }
}

/** Throws InsideCopy on Windows for a run inside the copy at local. */
export function refuseInside(local, platform = process.platform) {
  if (platform === "win32" && placeIn(local) !== null) throw new InsideCopy();
}

/** Downloads the newest release that checks into local. Returns { from, to, failed, warning, steppedOut } with failed
 * as [name, problems] for each release with a MANIFEST that was passed over, and steppedOut true when the run started
 * inside the copy and was moved into the new one. On Windows, a run inside the copy throws InsideCopy first. */
export async function sync(access, local, { remove = folder => removeFolder(folder), platform = process.platform } = {}) {
  refuseInside(local, platform);
  const from = existsSync(join(local, "RELEASE")) ? readFileSync(join(local, "RELEASE"), "utf8").trim() : "";
  const failed = [];
  const incoming = `${local}.incoming`;
  for (const name of (await releases(access)).filter(name => name > from)) {
    remove(incoming);
    let problems;
    try { problems = await downloadRelease(access, name, incoming); }
    catch (err) { problems = [`downloading failed: ${err instanceof Error ? err.message : err}`]; }
    if (problems.length) {
      remove(incoming);
      // A folder with no MANIFEST is a publish under way, or one that stopped, and is not a release.
      if (!(problems.length === 1 && problems[0] === "MANIFEST missing")) failed.push([name, problems]);
      continue;
    }
    writeFileSync(join(incoming, "RELEASE"), `${name}\n`);
    if (existsSync(join(local, ".git"))) renameSync(join(local, ".git"), join(incoming, ".git"));
    // The workflow plugins the copy held, so the next step puts each back, or says it is gone.
    if (existsSync(join(local, WORKFLOWS_FILE))) cpSync(join(local, WORKFLOWS_FILE), join(incoming, WORKFLOWS_FILE));
    const old = `${local}.old`;
    remove(old);
    const back = stepOutOf(local);
    if (existsSync(local)) renameSync(local, old);
    renameSync(incoming, local);
    back?.();
    let warning = null;
    try { remove(old); } catch (err) { warning = err.message; }
    return { from, to: name, failed, warning, steppedOut: Boolean(back) };
  }
  return { from, to: null, failed };
}

/** The file in the copy naming each workflow plugin it holds, with its scope and release. */
export const WORKFLOWS_FILE = "WORKFLOWS.json";

/** The code of each workflow plugin scope, plugins_<workflow>, that okb_get_scopes shows the person, every page of them. */
export async function pluginScopes(access) {
  const codes = [];
  for (let cursor = null, page = 0; page < 100; page++) {
    const got = await callRpc(access.url, access.key, access.token, "okb_get_scopes", "okb", { p_limit: 100, ...(cursor ? { p_cursor: cursor } : {}) });
    if (!got.ok) throw new Error(`Your scopes in OKB could not be listed: ${got.problem}`);
    for (const s of got.body?.items ?? []) if (isPluginScope(s.code) && s.enabled !== false) codes.push(s.code);
    cursor = got.body?.next_cursor ?? null;
    if (!cursor) break;
  }
  return codes.sort();
}

const readHeld = local => { try { const held = JSON.parse(readFileSync(join(local, WORKFLOWS_FILE), "utf8")); return held && typeof held === "object" && !Array.isArray(held) ? held : {}; } catch { return {}; } };

/** Sets the copy's marketplace.json entry for a workflow plugin, or takes it out when entry is null. */
function listWorkflow(local, name, entry) {
  const file = join(local, ".claude-plugin", "marketplace.json");
  if (!existsSync(file)) return;
  const market = JSON.parse(readFileSync(file, "utf8"));
  market.plugins = [...(market.plugins ?? []).filter(p => p.name !== name), ...(entry ? [entry] : [])];
  writeFileSync(file, `${JSON.stringify(market, null, 2)}\n`);
}

/**
 * Puts the newest release of each workflow plugin whose scope, plugins_<workflow>, the person's grants reach into the
 * copy at local: its folder at plugins/<name>, its entry in the copy's marketplace.json, and its scope and release in
 * WORKFLOWS.json. A release the copy holds already is not downloaded again. A release with no MANIFEST, or one whose
 * files do not match it, is passed over for the next older one. Each workflow plugin the copy holds whose scope the
 * person no longer reaches is taken out of it. Returns { added, removed, failed }: added as [name, release, scope],
 * removed as [name, scope], and failed as [scope, release, problems].
 */
export async function syncWorkflows(access, local, { remove = folder => removeFolder(folder), scopes = pluginScopes } = {}) {
  const reached = await scopes(access);
  const held = readHeld(local);
  // The plugins the Plugins scope's release lists, which no workflow plugin's scope may replace.
  const fromPlugins = new Set(listedPlugins(local).filter(name => !Object.hasOwn(held, name)));
  const added = [], removed = [], failed = [];
  const stage = `${local}.workflows`;
  remove(stage);
  try {
    for (const scope of reached) {
      const listed = await listReleases(access, scope);
      if (!listed.ok) { failed.push([scope, "", [`its releases could not be listed: ${listed.problem}`]]); continue; }
      for (const release of listed.names) {
        const kept = Object.entries(held).find(([, h]) => h?.scope === scope && h?.release === release);
        if (kept && existsSync(join(local, "plugins", kept[0], ".claude-plugin", "plugin.json"))) break;
        const into = join(stage, scope, release);
        const problems = await downloadRelease(access, release, into, scope);
        if (problems.length) {
          remove(into);
          if (!(problems.length === 1 && problems[0] === "MANIFEST missing")) failed.push([scope, release, problems]);
          continue;
        }
        const name = workflowPlugin(readFileSync(join(into, "MANIFEST"), "utf8"));
        // A workflow plugin's scope never replaces one of Real Agent's own plugins, nor one the Plugins scope lists.
        const refused = OWN_PLUGIN_NAMES.includes(name) ? `it holds ${name}, one of Real Agent's own plugins, which come only from the Plugins scope`
          : fromPlugins.has(name) ? `it holds ${name}, which the Plugins scope's release already gives`
          : pluginScope(name) !== scope ? `it holds ${name}, and the ${scope} scope keeps only the plugin it is named for` : null;
        if (refused) { remove(into); failed.push([scope, release, [refused]]); continue; }
        const target = join(local, "plugins", name);
        remove(target);
        mkdirSync(dirname(target), { recursive: true });
        cpSync(join(into, "plugins", name), target, { recursive: true });
        const { description } = JSON.parse(readFileSync(join(target, ".claude-plugin", "plugin.json"), "utf8"));
        listWorkflow(local, name, { name, source: `./plugins/${name}`, description });
        for (const [other, h] of Object.entries(held)) if (h?.scope === scope && other !== name) delete held[other];
        held[name] = { scope, release };
        added.push([name, release, scope]);
        break;
      }
    }
  } finally { remove(stage); }
  for (const [name, h] of Object.entries(held)) {
    if (reached.includes(h?.scope)) continue;
    remove(join(local, "plugins", name));
    listWorkflow(local, name, null);
    delete held[name];
    removed.push([name, h?.scope]);
  }
  if (added.length || removed.length) writeFileSync(join(local, WORKFLOWS_FILE), `${JSON.stringify(held, null, 2)}\n`);
  return { added, removed, failed };
}

const GIT = ["-c", "core.autocrlf=false", "-c", "user.name=okb-sync", "-c", "user.email=okb-sync@localhost"];
const git = (folder, ...args) => spawnSync("git", ["-C", folder, ...GIT, ...args], { encoding: "utf8" });
export const GIT_MISSING = "Git was not found. Install it, open a new terminal, and run this again:\n"
  + "  macOS: brew install git\n  Windows: winget install Git.Git\n  Debian and Ubuntu: sudo apt install git\n";

/** True when the git command runs. */
export const hasGit = () => spawnSync("git", ["--version"], { encoding: "utf8" }).status === 0;

/** Makes local a Git repository if it is not one, and commits any change as "release <RELEASE>".
 * Returns true when it made a commit. Throws with git's words when a git command fails. */
export function commit(local) {
  const must = (...args) => {
    const ran = git(local, ...args);
    if (ran.status !== 0) throw new Error(`git ${args[0]} failed in ${local}: ${`${ran.stdout}${ran.stderr}`.trim()}`);
    return ran.stdout;
  };
  if (!existsSync(join(local, ".git"))) must("init", "-q");
  if (!must("status", "--porcelain").trim()) return false;
  const release = readFileSync(join(local, "RELEASE"), "utf8").trim();
  must("add", "-A");
  must("commit", "-q", "-m", `release ${release}`);
  return true;
}

/** The folder Claude Code clones the marketplace into. */
export const cloneFolder = configDir => join(configDir, "plugins", "marketplaces", MARKETPLACE_NAME);

/** The git source URL of a local folder: file:// and its absolute path, with forward slashes. */
export function sourceUrl(local) {
  const path = resolve(local).split(sep).join("/");
  return `file://${path.startsWith("/") ? "" : "/"}${path}`;
}

/** Sets the real-agent marketplace's source to local's git source, in known_marketplaces.json and in
 * extraKnownMarketplaces in settings.json, in place of Real Agent's public copy. Keeps each entry's other
 * keys and every other entry. Returns true when it wrote a file. Throws when a file is there but is not
 * JSON, and leaves it as it is. */
export function registerSource(configDir, local) {
  const source = { source: "git", url: sourceUrl(local) };
  const same = entry => entry?.source?.source === "git" && entry.source.url === source.url;
  const read = file => {
    if (!existsSync(file)) return {};
    try { return JSON.parse(readFileSync(file, "utf8")); } catch { throw new Error(`${file} is not readable JSON. Fix it, and run this again.`); }
  };
  let wrote = false;
  const knownFile = join(configDir, "plugins", "known_marketplaces.json");
  const known = read(knownFile);
  if (!same(known[MARKETPLACE_NAME]) || known[MARKETPLACE_NAME].installLocation !== cloneFolder(configDir)) {
    // Claude Code refuses an entry without lastUpdated.
    known[MARKETPLACE_NAME] = { lastUpdated: new Date().toISOString(), ...known[MARKETPLACE_NAME], source, installLocation: cloneFolder(configDir) };
    mkdirSync(dirname(knownFile), { recursive: true });
    writeFileSync(knownFile, `${JSON.stringify(known, null, 2)}\n`);
    wrote = true;
  }
  const settingsFile = join(configDir, "settings.json");
  const settings = read(settingsFile);
  const extra = settings.extraKnownMarketplaces ?? {};
  if (!same(extra[MARKETPLACE_NAME])) {
    settings.extraKnownMarketplaces = { ...extra, [MARKETPLACE_NAME]: { ...extra[MARKETPLACE_NAME], source } };
    mkdirSync(configDir, { recursive: true });
    writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`);
    wrote = true;
  }
  return wrote;
}

// On Windows, claude may be a .cmd that only a shell runs, and a shell takes one command line.
export const claude = (args, cwd) => process.platform === "win32"
  ? spawnSync(`claude ${args.join(" ")}`, { encoding: "utf8", shell: true, cwd })
  : spawnSync("claude", args, { encoding: "utf8", cwd });

/** True when a claude run found no claude command. */
const noClaude = ran => ran.error?.code === "ENOENT"
  || /is not recognized as an internal or external command/i.test(`${ran.stdout ?? ""}${ran.stderr ?? ""}`);

/** The last line a claude run printed. */
const lastLine = ran => `${ran.stdout ?? ""}${ran.stderr ?? ""}`.trim().split("\n").pop() ?? "";

/** The plugins the copy's marketplace.json lists. */
export function listedPlugins(local) {
  try { return JSON.parse(readFileSync(join(local, ".claude-plugin", "marketplace.json"), "utf8")).plugins.map(p => p.name); }
  catch { return []; }
}

/** Runs `claude plugin update` for each plugin installed from the real-agent marketplace, and names each plugin
 * the copy lists that is not installed. Returns { lines, failed, missing }: one line per plugin, the number
 * that failed, and true when there is no claude command. Each plugin's old and new version come from
 * `claude plugin list --json`, before and after, which every Claude Code build gives; some builds have no --json on
 * the update itself. Without a terminal, the update gets -y, which accepts a marketplace's changed install command in
 * place of a prompt nobody answers; a build that does not know -y is asked again without it. */
export function updatePlugins(local, run = claude, interactive = Boolean(process.stdin.isTTY), gone = new Set()) {
  const listed = run(["plugin", "list", "--json"]);
  if (noClaude(listed)) return { lines: [], failed: 0, missing: true };
  let plugins;
  try { plugins = JSON.parse(listed.stdout); } catch {
    return { lines: [`The installed plugins could not be listed. Claude Code said: ${lastLine(listed)}`], failed: 1, missing: false };
  }
  const suffix = `@${MARKETPLACE_NAME}`;
  const key = p => `${p?.id} ${p?.scope} ${p?.projectPath ?? ""}`;
  const done = [];
  let failed = 0;
  const seen = new Set();
  const installed = new Set();
  for (const plugin of Array.isArray(plugins) ? plugins : []) {
    const { id, scope, projectPath } = plugin;
    if (typeof id !== "string" || !id.endsWith(suffix) || seen.has(key(plugin)) || gone.has(id.slice(0, -suffix.length))) continue;
    seen.add(key(plugin));
    installed.add(id.slice(0, -suffix.length));
    const name = id.slice(0, -suffix.length) + (typeof projectPath === "string" ? ` in ${projectPath}` : "");
    // Claude Code finds a project or local install in the folder the update runs in.
    const cwd = typeof projectPath === "string" && existsSync(projectPath) ? projectPath : undefined;
    const update = ["plugin", "update", id, ...(scope ? ["--scope", scope] : [])];
    let ran = run(interactive ? update : [...update, "-y"], cwd);
    if (!interactive && ran.status !== 0 && /unknown option '(-y|--yes)'/.test(`${ran.stdout ?? ""}${ran.stderr ?? ""}`)) ran = run(update, cwd);
    if (ran.error || ran.status !== 0) {
      failed += 1;
      done.push({ plugin, line: `${name}: the update failed. Claude Code said: ${lastLine(ran).replace(/^✘\s*/, "")}` });
    } else done.push({ plugin, name });
  }
  let after = [];
  if (done.some(d => !d.line)) {
    try { after = JSON.parse(run(["plugin", "list", "--json"]).stdout); } catch { after = []; }
  }
  const lines = done.map(({ plugin, name, line }) => {
    if (line) return line;
    const old = plugin.version, now = (Array.isArray(after) ? after : []).find(p => key(p) === key(plugin))?.version;
    if (!now) return `${name}: the update ran, and its version could not be read.`;
    if (old === now) return `${name}: already up to date, at ${now}.`;
    return `${name}: updated from ${old ?? "an unknown version"} to ${now}.`;
  });
  for (const plugin of listedPlugins(local).filter(p => !installed.has(p)))
    lines.push(`${plugin}: in the release, and not installed. Install it with: claude plugin install ${plugin}${suffix}`);
  return { lines, failed, missing: false };
}

/** The copy's line about this computer's Node.js, when it is not the version the plugins need, or null. */
export async function nodeLine(local) {
  const file = join(local, "plugins", "okb", "cli", "node-version.mjs");
  if (!existsSync(file)) return null;
  try { return (await import(pathToFileURL(file).href)).nodeMismatch() || null; }
  catch { return null; }
}

// The one-time notice for a computer set up when each person's agent also had an upload folder. The okb
// plugin's old upload_folder setting may still name one, and so may the actor file of each folder an
// earlier `okb setup` made, in the home folder or a folder in it. That setup also made an `uploads`
// folder inside each folder it made. The agent no longer reads any of them. For each such folder holding a
// file, sync prints once which folder to move the files into. Each folder told about is recorded in the
// okb plugin's data folder, and is never named again. The folder and its files stay.
export const NOTICE_FILE = "upload-folder-notice.json";

/** The okb plugin's data folder, where Claude Code keeps the plugin's own files. */
export const dataFolder = configDir => join(configDir, "plugins", "data", `okb-${MARKETPLACE_NAME}`);

/** Whether the folder holds a file that is not hidden, directly inside it. */
function holdsFiles(folder) {
  try { return readdirSync(folder, { withFileTypes: true }).some(entry => entry.isFile() && !entry.name.startsWith(".")); }
  catch { return false; }
}

/** Each folder in the home folder, and in a folder in it. */
function homeFolders(home) {
  const folders = under => { try { return readdirSync(under, { withFileTypes: true }).filter(e => e.isDirectory() && !e.name.startsWith(".")).map(e => join(under, e.name)); } catch { return []; } };
  return folders(home).flatMap(one => [one, ...folders(one)]);
}

/** The notice's lines, one for each old upload folder holding files that no run has named yet. Records each one named. */
export function uploadFolderNotices(configDir, home = homedir()) {
  const read = file => { try { return JSON.parse(readFileSync(file, "utf8")); } catch { return null; } };
  const options = read(join(configDir, "settings.json"))?.pluginConfigs?.[`okb@${MARKETPLACE_NAME}`]?.options ?? {};
  // Each old upload folder, with the agent folder its files go into: the setting's first, then each actor file's,
  // then the uploads folder in the agent folder, in each folder holding an actor file, and in each other folder setup made.
  const agentSetting = String(options.agent_folder ?? "").trim();
  const pairs = [[options.upload_folder, agentSetting || "your folder"]];
  const made = homeFolders(home).filter(folder => existsSync(join(folder, ACTOR_FILE)) || madeBySetup(folder, home));
  for (const folder of made) pairs.push([read(join(folder, ACTOR_FILE))?.upload_folder, folder]);
  for (const folder of [...(agentSetting ? [agentSetting] : []), ...made]) pairs.push([join(folder, "uploads"), folder]);
  const record = join(dataFolder(configDir), NOTICE_FILE);
  const told = read(record)?.told;
  const named = Array.isArray(told) ? told : [];
  const lines = [];
  for (const [upload, agentFolder] of pairs) {
    const folder = typeof upload === "string" && upload.trim() ? resolve(upload.trim()) : "";
    if (!folder || named.includes(folder) || !holdsFiles(folder)) continue;
    lines.push(`Your agent no longer reads ${folder}. Move any file you want uploaded into ${agentFolder}.`);
    named.push(folder);
  }
  if (lines.length) {
    mkdirSync(dataFolder(configDir), { recursive: true });
    writeFileSync(record, `${JSON.stringify({ told: named }, null, 1)}\n`);
  }
  return lines;
}

// The agent the business analyst replaced, as an administrator's folder may still name it, and its replacement.
export const OLD_ADMIN_AGENT = "real-agent:database-admin";
export const ADMIN_AGENT = "business-analyst:business-analyst";

/**
 * Moves each folder in the home folder, or in a folder in it, whose .claude/settings.json names the database admin, to
 * the business analyst, keeping every other setting, and installs the business-analyst plugin when it is not installed.
 * Returns one line for each folder moved, and one for an install that failed.
 */
export function moveAdminFolders(home = homedir(), run = claude) {
  const lines = [];
  for (const folder of [home, ...homeFolders(home)]) {
    const file = join(folder, ".claude", "settings.json");
    let settings;
    try { settings = JSON.parse(readFileSync(file, "utf8")); } catch { continue; }
    if (!settings || typeof settings !== "object" || Array.isArray(settings) || settings.agent !== OLD_ADMIN_AGENT) continue;
    writeFileSync(file, `${JSON.stringify({ ...settings, agent: ADMIN_AGENT }, null, 2)}\n`);
    lines.push(`${folder} now works with your business analyst, ${ADMIN_AGENT}, which does all the database admin did.`);
  }
  if (!lines.length) return lines;
  let installed = [];
  try { installed = JSON.parse(run(["plugin", "list", "--json"]).stdout); } catch { installed = []; }
  const id = `${ADMIN_AGENT.split(":")[0]}@${MARKETPLACE_NAME}`;
  if (!(Array.isArray(installed) ? installed : []).some(p => p?.id === id)) {
    const ran = run(["plugin", "install", id]);
    if (ran.error || ran.status !== 0) lines.push(`${id} could not be installed. Claude Code said: ${lastLine(ran)}. Install it with: claude plugin install ${id}`);
  }
  return lines;
}

/**
 * The whole of okb sync. `say` prints a line. `run` runs a claude command, `open` opens the sign-in.
 * Returns the exit code: 0 when every step worked or no release is there yet, 1 when a step failed.
 */
export async function runSync(argv, { cwd = process.cwd(), home = homedir(), say = line => process.stdout.write(`${line}\n`), run = claude, open = openAccess,
  configDir = process.env.CLAUDE_CONFIG_DIR || join(home, ".claude") } = {}) {
  let options;
  try { options = parseSync(argv); } catch (err) { say(err.message); return 1; }
  if (!hasGit()) { say(GIT_MISSING.trimEnd()); return 1; }
  const session = await open({ project: options.project, email: options.email, cwd, home });
  if (!session.ok) { say(`${session.problem}\nThen run okb sync again.`); return 1; }
  const local = localCopy(session.ref, options.into, home);
  let synced;
  try { takeLock(local); synced = await sync(session.access, local); }
  catch (err) {
    if (!(err instanceof StuckFolder || err instanceof SyncRunning || err instanceof InsideCopy) && !/^The releases in OKB could not be listed/.test(err?.message)) throw err;
    say(`${err.message}${err instanceof SyncRunning || err instanceof InsideCopy ? "" : "\nThen run okb sync again."}`);
    return 1;
  }
  const { from, to, failed, warning } = synced;
  // A folder still set to the database admin moves to the business analyst on every run, release or none.
  for (const line of moveAdminFolders(home, run)) say(line);
  if (warning) say(`The copy is updated, but its earlier version stays behind. ${warning}`);
  for (const [name, problems] of failed) say(`Release ${name} is incomplete in OKB, and was passed over:\n${problems.map(p => `  ${p}`).join("\n")}`);
  if (!to && !from && failed.length) {
    say("No release in OKB's Plugins scope has all its files in place. Ask Real Agent to publish again, with the support skill.");
    return 1;
  }
  if (!to && !from) {
    say(`OKB's Plugins scope shows ${session.email} no release yet, so your plugins stay as installed from Real Agent's public marketplace. If Real Agent has published your firm's plugins, ask your administrator for read in the Plugins scope.`);
    return 0;
  }
  say(to ? `Your copy in ${local} is now release ${to}${from ? `, from ${from}` : ""}.` : `Your copy in ${local} is up to date, at release ${from}.`);
  // Each workflow plugin whose own scope the person's grants reach.
  let workflows = { added: [], removed: [], failed: [] };
  try { workflows = await syncWorkflows(session.access, local); }
  catch (err) { say(`${err instanceof Error ? err.message : err}\nYour workflow plugins stay as they are.`); }
  for (const [scope, release, problems] of workflows.failed)
    say(`Release ${release ? `${release} ` : ""}in the ${scope} scope is incomplete, and was passed over:\n${problems.map(p => `  ${p}`).join("\n")}`);
  for (const [name, release, scope] of workflows.added) say(`Your copy holds ${name} from release ${release}, in the ${scope} scope.`);
  for (const [name, scope] of workflows.removed)
    say(`${name}: your grants no longer reach the ${scope} scope, so it is gone from your copy. Remove it with: claude plugin uninstall ${name}@${MARKETPLACE_NAME}`);
  try {
    commit(local);
    registerSource(configDir, local);
  } catch (err) { say(err instanceof Error ? err.message : String(err)); return 1; }
  say(`Claude Code's ${MARKETPLACE_NAME} marketplace is your copy, at ${sourceUrl(local)}.`);
  // The marketplace update runs on every run that reaches a copy, so a run after a failed one still refreshes it.
  const update = run(["plugin", "marketplace", "update", MARKETPLACE_NAME]);
  if (noClaude(update)) { say("The claude command was not found. Open a new terminal, and run okb sync again."); return 1; }
  say(lastLine(update));
  if (update.status !== 0) return 1;
  const plugins = updatePlugins(local, run, undefined, new Set(workflows.removed.map(([name]) => name)));
  if (plugins.missing) { say("The claude command was not found. Open a new terminal, and run okb sync again."); return 1; }
  for (const line of plugins.lines) say(line);
  if (plugins.lines.length) say("Start a new Code session to use the new versions.");
  for (const line of uploadFolderNotices(configDir, home)) say(line);
  const mismatch = await nodeLine(local);
  if (mismatch) say(mismatch);
  if (synced.steppedOut) say(backInto(local));
  return plugins.failed ? 1 : 0;
}
