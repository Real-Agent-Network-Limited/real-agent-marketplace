// okb.mjs setup: sets up one person's folder from the Terminal. One folder works in one client's
// project as one person. It makes the folder, where the person puts files for their agent and the agent
// keeps its work, writes the folder's agent setting,
// installs the agent's plugin from the real-agent marketplace, and runs the sign-in with --folder, which
// writes the folder's actor file. Its last step, the first after a first sign-in, is okb sync in the
// folder, which installs the firm's own release of its plugins from OKB in place of the public copy.
//
//   node okb.mjs setup [--folder <folder>] --email <email> [--url <project URL> --key <publishable key>] [--agent <plugin>:<agent>] [--new-password]
//   node okb.mjs setup [--folder <folder>] --email <email> --url <project URL> --key <publishable key> --join [--agent <plugin>:<agent>]
//   node okb.mjs setup --owner [--folder <folder>]
//
// --join is the first sign-in of a person their administrator added with a one-time invitation code: the sign-in asks
// the code and the password they choose, twice, in place of a password someone gave them. Every other step is the same.
//
// The folder is ~/real-agent unless --folder names another. A folder set up before under another name, such as
// ~/okb, keeps working: run setup again with --folder naming it.
//
// --owner is the firm's owner's first run, before the firm has a Supabase project: it makes the folder, names the
// business analyst as its agent and installs its plugin, and neither signs in nor runs okb sync, since there is no
// project yet. The owner then types "Set up Real Agent" in a session on the folder.
//
// Each step prints what it did, or that it was already done, so running it again is safe. A failed step
// stops the run with Claude Code's or the sign-in's message, and every step before it stays done.
import process from "node:process";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { endSetup, markSetup } from "../mcp/lib/setup-marker.mjs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { accountEmail } from "../mcp/lib/session.mjs";
import { readActor } from "../mcp/lib/actor-file.mjs";
import { nodeMismatch } from "./node-version.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
/** The marketplace this command runs from, such as Claude Code's copy of the real-agent marketplace. */
export const MARKETPLACE = resolve(HERE, "../../..");
/** The marketplace's name in Claude Code, which each plugin's id ends with. */
export const MARKETPLACE_NAME = "real-agent";
export const DEFAULT_AGENT = "real-agent:database-operator";
/** The agent of the owner's folder while OKB is set up. */
export const OWNER_AGENT = "business-analyst:business-analyst";
/** The folder's name in the home folder when --folder is left out. */
export const DEFAULT_FOLDER = "real-agent";
/** What the owner types in a session on their folder to start setup. */
export const OWNER_PHRASE = "Set up Real Agent";

export const SETUP_USAGE = `Usage: node okb.mjs setup [--folder <folder>] --email <email> [--url <project URL> --key <publishable key>] [--agent <plugin>:<agent>] [--new-password]
       node okb.mjs setup [--folder <folder>] --email <email> --url <project URL> --key <publishable key> --join [--agent <plugin>:<agent>]
       node okb.mjs setup --owner [--folder <folder>]

setup sets up a folder for one person in their firm's OKB: the folder, ~/${DEFAULT_FOLDER} unless --folder
names another, where you put files for your agent and your agent keeps its work, the agent the folder works with, ${DEFAULT_AGENT} unless --agent names another, that agent's plugin
from the ${MARKETPLACE_NAME} marketplace, and the person's sign-in as --email. A session opened on the
folder then works as that person. Last, it runs okb sync in the folder, which installs the firm's own
release of its plugins from OKB's Plugins scope in place of the public copy. --url and --key give the project's address and publishable key,
from the Supabase dashboard's Connect button; without them the sign-in asks. --new-password replaces
the first password.

--join is for a person their administrator added with a one-time invitation code. The sign-in asks for the code
and a password you choose, twice, and needs --url and --key.

--owner is for the firm's owner, before the firm has a Supabase project. It makes the folder, names the
business analyst, ${OWNER_AGENT}, as the folder's agent, and installs its plugin. It neither signs in
nor runs okb sync. The owner then types "${OWNER_PHRASE}" in a session opened on the folder.`;

const VALUED = ["--email", "--folder", "--agent", "--url", "--key"];

/** The command line's options. */
export function parseSetup(argv) {
  const out = { newPassword: false, owner: false, join: false };
  for (let i = 0; i < argv.length; i++) {
    const word = argv[i];
    if (word === "--new-password") out.newPassword = true;
    else if (word === "--owner") out.owner = true;
    else if (word === "--join") out.join = true;
    else if (VALUED.includes(word)) {
      if (argv[i + 1] === undefined || argv[i + 1].startsWith("--")) throw new Error(`${word} needs a value.`);
      out[word.slice(2)] = argv[++i];
    } else throw new Error(`${word} is not an option of setup.`);
  }
  if (out.owner) {
    const other = ["email", "url", "key", "agent"].filter(name => out[name] !== undefined).map(name => `--${name}`);
    if (out.newPassword) other.push("--new-password");
    if (out.join) other.push("--join");
    if (other.length) throw new Error(`--owner takes only --folder, since there is no project to sign in to yet: leave out ${other.join(", ")}.`);
    out.agent = OWNER_AGENT;
    return out;
  }
  if (!out.email) throw new Error("--email is needed.");
  if (!accountEmail(out.email)) throw new Error(`${out.email} is not an email address.`);
  out.email = accountEmail(out.email);
  if ((out.url === undefined) !== (out.key === undefined)) throw new Error("--url and --key go together.");
  if (out.join && out.url === undefined) throw new Error("--join needs --url and --key, the project's address and publishable key.");
  if (out.join && out.newPassword) throw new Error("--join and --new-password do not go together: with --join you choose your password.");
  out.agent ??= DEFAULT_AGENT;
  return out;
}

/** Each agent in a plugin of the marketplace, as <plugin>:<agent>, from the plugins' agents folders. */
export function marketplaceAgents(marketplace = MARKETPLACE) {
  const listed = JSON.parse(readFileSync(join(marketplace, ".claude-plugin", "marketplace.json"), "utf-8")).plugins ?? [];
  const agents = [];
  for (const plugin of listed) {
    if (typeof plugin.source !== "string") continue;
    const folder = join(marketplace, plugin.source, "agents");
    let files = [];
    try { files = readdirSync(folder).filter(f => f.endsWith(".md")).sort(); } catch { continue; }
    for (const file of files) {
      const text = readFileSync(join(folder, file), "utf-8");
      const name = /^---\r?\n[\s\S]*?^name:\s*(\S+)\s*$/m.exec(text)?.[1] ?? file.slice(0, -3);
      agents.push(`${plugin.name}:${name}`);
    }
  }
  return agents;
}

// On Windows, claude may be a .cmd that only a shell runs, and a shell takes one command line.
const shellWord = word => /[\s"&|<>^]/.test(word) ? `"${word.replaceAll('"', '\\"')}"` : word;
const claude = args => process.platform === "win32"
  ? spawnSync(`claude ${args.map(shellWord).join(" ")}`, { encoding: "utf8", shell: true, stdio: ["ignore", "pipe", "pipe"] })
  : spawnSync("claude", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

class StepFailed extends Error {}

/** Runs one claude command, prints its message, and stops the run when it fails. */
function runClaude(args, say) {
  const ran = claude(args);
  const text = `${ran.stdout ?? ""}${ran.stderr ?? ""}`.trim();
  if (ran.error || ran.status !== 0) {
    const why = ran.error?.code === "ENOENT" || process.platform === "win32" && /is not recognized/.test(text)
      ? "The claude command was not found. Install Claude Code's command-line tool, then run setup again."
      : text || `claude ${args.join(" ")} stopped with exit code ${ran.status}.`;
    throw new StepFailed(why);
  }
  // A folder signed in with --folder needs none of the plugin's own settings.
  const shown = text.replace(/^Installing plugin "[^"]+"\.\.\./, "").split(/\r?\n/).filter(line => !/userConfig options? not yet set/.test(line)).join("\n");
  if (shown) say(shown);
  return ran.stdout ?? "";
}

/** The JSON a claude list command prints, or [] when it prints none. */
function claudeList(args) {
  const ran = claude([...args, "--json"]);
  if (ran.error || ran.status !== 0) return [];
  try { return JSON.parse(ran.stdout); } catch { return []; }
}

function makeFolder(folder, say) {
  if (existsSync(folder)) { say(`${folder} is already there.`); return; }
  mkdirSync(folder, { recursive: true });
  say(`Made ${folder}.`);
}

/** Writes the folder's .claude/settings.json with the agent, keeping every other setting in it. */
function writeAgentSetting(folder, agent, say) {
  const file = join(folder, ".claude", "settings.json");
  let settings = {};
  if (existsSync(file)) {
    try { settings = JSON.parse(readFileSync(file, "utf-8")); }
    catch { throw new StepFailed(`${file} is not JSON. Correct it or delete it, and run setup again.`); }
    if (!settings || typeof settings !== "object" || Array.isArray(settings)) throw new StepFailed(`${file} is not a settings file. Correct it or delete it, and run setup again.`);
    if (settings.agent === agent) { say(`${file} already names the ${agent} agent.`); return; }
  }
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, `${JSON.stringify({ ...settings, agent }, null, 2)}\n`);
  say(`${file} names the ${agent} agent.`);
}

/** True when a saved sign-in for the email on the project is on this computer. */
const signedIn = (home, ref, email) => existsSync(join(home, ".config", "supabase-auth", ref, `${email}.json`));

function runSignIn(signInPath, args, say) {
  say("Signing in. Type each password into the sign-in's own prompt.");
  const ran = spawnSync(process.execPath, [signInPath, ...args], { stdio: "inherit" });
  if (ran.status !== 0) throw new StepFailed(`The sign-in stopped${ran.status === null ? "" : ` with exit code ${ran.status}`}. Run setup again to sign in.`);
}

function runSync(syncArgs, folder, say) {
  say("Installing your firm's own release of its plugins, with okb sync.");
  const ran = spawnSync(process.execPath, syncArgs, { stdio: "inherit", cwd: folder });
  if (ran.status !== 0) throw new StepFailed(`okb sync stopped${ran.status === null ? "" : ` with exit code ${ran.status}`}. In ${folder}, run okb sync again.`);
}

/**
 * Runs setup. `signInArgs` builds okb.mjs sign-in's arguments, and `signInPath` names the sign-in to run.
 * `syncArgs` is the node command line of okb sync, run in the folder once the folder is signed in.
 * Returns 0 when every step is done, 1 when a step failed, and 2 for a wrong command line.
 */
export function setup(argv, { home = homedir(), signInArgs, signInPath, syncArgs = [resolve(HERE, "okb.mjs"), "sync"], marketplace = MARKETPLACE, say = line => process.stdout.write(`${line}\n`), fail = line => process.stderr.write(`${line}\n`) } = {}) {
  let o;
  try { o = parseSetup(argv); }
  catch (err) { fail(`${err.message}\n${SETUP_USAGE}`); return 2; }
  const mismatch = nodeMismatch();
  if (mismatch) { fail(mismatch); return 1; }
  try {
    const agents = marketplaceAgents(marketplace);
    if (!agents.includes(o.agent)) throw new StepFailed(`${o.agent} is not an agent in the ${MARKETPLACE_NAME} marketplace. Its agents are: ${agents.join(", ")}.`);
    const folder = resolve(o.folder ?? join(home, DEFAULT_FOLDER));
    makeFolder(folder, say);
    writeAgentSetting(folder, o.agent, say);
    const plugin = o.agent.split(":")[0];
    if (claudeList(["plugin", "list"]).some(p => p.id === `${plugin}@${MARKETPLACE_NAME}`)) say(`The ${plugin} plugin is already installed.`);
    else {
      say(`Installing ${plugin}@${MARKETPLACE_NAME}.`);
      runClaude(["plugin", "install", `${plugin}@${MARKETPLACE_NAME}`], say);
    }
    if (o.owner) {
      // Setup is under way in the folder until a signed-in okb setup ends it.
      markSetup(folder);
      say(`Done. Start a new Code session on ${folder}, and type: ${OWNER_PHRASE}`);
      return 0;
    }
    const actor = readActor(folder);
    // --new-password always runs the sign-in, so a reset first password is replaced.
    if (!o.newPassword && actor?.ok && actor.value.auth_email === o.email && signedIn(home, actor.value.project_ref, o.email)) {
      say(`${folder} is already signed in as ${o.email}.`);
    } else {
      const where = o.url === undefined ? [] : ["--url", o.url, "--key", o.key];
      runSignIn(signInPath, signInArgs([...(o.newPassword ? ["--new-password"] : []), ...(o.join ? ["--join"] : []), ...where, "--folder", folder, "--email", o.email], o.email).slice(1), say);
    }
    runSync(syncArgs, folder, say);
    // A folder signed in and synced has finished setup: its agent keeps to the okb plugin's tools from now on.
    endSetup(folder);
    say(`Done. Start a new Code session on ${folder}, and type: who am I?`);
    return 0;
  } catch (err) {
    if (!(err instanceof StepFailed)) throw err;
    fail(err.message);
    return 1;
  }
}
