#!/usr/bin/env node
// OKB from a terminal, for a person working without their agent. One command runs any of OKB's
// database functions, and the okb plugin's file, drawing and printing tools, with the same code the
// plugin's MCP server runs, as the person signed in with sign-in.
//
//   node okb.mjs setup --folder <folder> --email <email> [--url <project URL> --key <publishable key>] [--agent <plugin>:<agent>] [--new-password]
//   node okb.mjs sign-in [--new-password] [--url <project URL> --key <publishable key>] [--folder <folder> --email <email>]
//   node okb.mjs sign-in --owner --url <project URL> --key <publishable key> --folder <setup folder>
//   node okb.mjs sync [--project <ref> --email <email>] [--into <local folder>]
//   node okb.mjs uninstall [--yes] [--remove-work]
//   node okb.mjs [--project <ref> --email <email>] <name> [<argument>=<value> ...]
//
// A folder works in one client's project as one person. sign-in run in a folder with an actor file,
// .okb-actor.json, signs in again as the file's person, with the project's address and key saved at
// the first sign-in. sync installs the newest release of the firm's plugins from OKB's Plugins
// scope, as sync.mjs describes. uninstall takes Real Agent's install off the computer and keeps the person's
// folders, as uninstall.mjs describes. --folder signs in as --email and writes that folder's actor file, so a session
// opened on it works as that person. The first sign-in asks for the project's address and
// publishable key, unless --url and --key give them.
// SUPABASE_PROJECT_REF and SUPABASE_AUTH_EMAIL, set together, stand in for --project and --email.
// Without --project, a folder holding an actor file works as the file's person.
// A name starting okb_ is an OKB function. An object, a list, a quoted string, true, false and null
// are sent as JSON, and anything else, numbers too, as text; <argument>=@<file> sends the JSON in the
// file, and <argument>.<field>=<value> sets one field of an object. A list of files may be given one
// file at a time. A file argument is a path in the current folder, which is both the folder files are
// read from and the folder results are written to.
import process from "node:process";
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { accountEmail, PROJECT_REF } from "../mcp/lib/session.mjs";
import { createTools as databaseTools, TOOLS as DATABASE_TOOLS } from "../mcp/lib/tools.mjs";
import { createTools as pageTools, TOOLS as PAGE_TOOLS } from "../mcp/lib/pages.mjs";
import { readActor } from "../mcp/lib/actor-file.mjs";
import { setup, SETUP_USAGE } from "./setup.mjs";
import { runSync, SYNC_USAGE } from "./sync.mjs";
import { uninstall, UNINSTALL_USAGE } from "./uninstall.mjs";

export const USAGE = `Usage: node okb.mjs setup [--folder <folder>] --email <email> [--url <project URL> --key <publishable key>] [--agent <plugin>:<agent>] [--new-password]
       node okb.mjs setup --owner [--folder <folder>]
       node okb.mjs sign-in [--new-password] [--url <project URL> --key <publishable key>] [--folder <folder> --email <email>]
       node okb.mjs sign-in --owner --url <project URL> --key <publishable key> --folder <setup folder>
       node okb.mjs sync [--project <ref> --email <email>] [--into <local folder>]
       node okb.mjs uninstall [--yes] [--remove-work]
       node okb.mjs [--project <ref> --email <email>] <name> [<argument>=<value> ...]

setup sets up a folder for one person in their firm's OKB: the folder, ~/real-agent unless --folder
names another, where the person puts files for their agent and the agent keeps its work, the agent
the folder works with, its plugin, and the person's sign-in. With --owner, before the firm has a project, it sets up the owner's folder for the
business analyst, with no sign-in. node okb.mjs setup --help says more.

sign-in signs you in to your firm's OKB and asks for your password. In a folder you signed in with
before, it signs you in again as that folder's person. --folder signs you in as --email, and saves the
folder's actor file: a session opened on that folder works as that email. The first sign-in asks for the project's address and publishable key, unless --url
and --key give them. --owner is the firm's owner's first sign-in, at the end of setup: it asks your name, your
email and the password you choose, and makes your sign-in with the code setup left in the folder.

sync installs the newest release of your firm's plugins from the Plugins scope of your firm's OKB,
signed in as you, and updates each plugin installed from it. node okb.mjs sync --help says more.

uninstall takes Real Agent's install off this computer, signs you out and keeps your folders. It lists
each item first, and asks you to type yes. node okb.mjs uninstall --help says more.

<name> is one of OKB's functions, such as okb_show_record or okb_set_state, or one of these tools:
  ${[...DATABASE_TOOLS, ...PAGE_TOOLS].map(t => t.name).filter(n => n !== "read_file").join(", ")}

An object, a list, a quoted string, true, false and null are sent as JSON, and anything else,
numbers too, as text. <argument>=@<file> sends the JSON in the file. <argument>.<field>=<value> sets one field of an object, and a list of files
may be given one file at a time. Files are read from and written to the current folder.
SUPABASE_PROJECT_REF and SUPABASE_AUTH_EMAIL, set together, stand in for --project and --email.
Without --project, a folder holding an actor file works as the person the file names.`;

const HERE = dirname(fileURLToPath(import.meta.url));
const SIGN_IN = resolve(HERE, "../mcp/sign-in.mjs");
// The path is quoted for the person's shell, as the database tools quote their sign-in command.
const quote = value => process.platform === "win32" ? `"${value}"` : `'${String(value).replaceAll("'", `'\\''`)}'`;
const OKB_SIGN_IN = `node ${quote(resolve(HERE, "okb.mjs"))} sign-in`;
/** The plugin's id in Claude Code's settings: the okb plugin from the real-agent marketplace. */
export const PLUGIN_ID = "okb@real-agent";
/** Every OKB function is in the okb schema. */
export const SCHEMA = "okb";

/** The email the person gave the okb plugin's settings at install, from Claude Code's settings, or null. */
export function settingsEmail(home = homedir(), configDir = process.env.CLAUDE_CONFIG_DIR) {
  try {
    const settings = JSON.parse(readFileSync(join(configDir || join(home, ".claude"), "settings.json"), "utf-8"));
    return accountEmail(settings?.pluginConfigs?.[PLUGIN_ID]?.options?.auth_email) || null;
  } catch { return null; }
}

/**
 * The sign-in's arguments. In a folder with an actor file and no other person named, it signs in
 * again as the file's person, in the file's project and folder. Otherwise it signs in as
 * the email given, or the settings' email, with the person's own options.
 */
export function signInArgs(argv, email, cwd = process.cwd()) {
  const named = argv.includes("--email") || argv.includes("--project") || argv.includes("--folder");
  if (!named) {
    const actor = readActor(cwd);
    if (actor && !actor.ok) throw new Error(actor.problem);
    if (actor) {
      // --url and --key are only for a first sign-in, which this is not.
      const rest = argv.filter((word, i) => !["--url", "--key"].includes(word) && !["--url", "--key"].includes(argv[i - 1]));
      return [SIGN_IN, "--project", actor.value.project_ref, "--email", actor.value.auth_email, "--folder", actor.folder, ...rest];
    }
  }
  email ??= settingsEmail();
  return [SIGN_IN, ...(email && !named ? ["--email", email] : []), ...argv];
}

// A tool argument that names a local file: a top-level `file`, or a name ending in _file or _files.
const isFileArgument = name => name === "file" || /_files?$/.test(name);

/** The command line's options, name and arguments. */
export function parse(argv, cwd = process.cwd()) {
  const out = { project: undefined, email: undefined, name: undefined, args: {} };
  for (let i = 0; i < argv.length; i++) {
    const word = argv[i];
    if (word === "--project" || word === "--email") {
      if (argv[i + 1] === undefined) throw new Error(`${word} needs a value.`);
      out[word.slice(2)] = argv[++i];
    } else if (word === "--help" || word === "-h") {
      out.name = undefined;
      return out;
    } else if (out.name === undefined) {
      out.name = word;
    } else {
      const eq = word.indexOf("=");
      if (eq < 1) throw new Error(`${word} is not <argument>=<value>.`);
      const key = word.slice(0, eq), text = word.slice(eq + 1);
      const dot = key.indexOf(".");
      if (dot > 0) {
        // <argument>.<field>=<value> sets one field of an object argument, with no JSON to type.
        const [name, field] = [key.slice(0, dot), key.slice(dot + 1)];
        const held = out.args[name] ?? {};
        if (held === null || typeof held !== "object" || Array.isArray(held)) throw new Error(`${name} is given as a value and as fields.`);
        if (field in held) throw new Error(`${key} is given twice.`);
        out.args[name] = { ...held, [field]: value(field, text, cwd, false) };
      } else if (key in out.args) {
        // A file list may be given one file at a time.
        if (!/_files$/.test(key)) throw new Error(`${key} is given twice.`);
        out.args[key] = [].concat(out.args[key], value(key, text, cwd));
      } else {
        out.args[key] = value(key, text, cwd);
      }
    }
  }
  if ((out.project === undefined) !== (out.email === undefined)) throw new Error("--project and --email go together.");
  if (out.project !== undefined && !PROJECT_REF.test(out.project)) throw new Error(`${out.project} is not a project reference.`);
  if (out.email !== undefined && !accountEmail(out.email)) throw new Error(`${out.email} is not an email address.`);
  return out;
}

/** One argument's value: a file's JSON, JSON, or text. A top-level file argument's paths are made full; a field of an object, such as a bucket path, stays as typed. */
function value(key, text, cwd, topLevel = true) {
  let v;
  if (text.startsWith("@")) {
    const file = resolve(cwd, text.slice(1));
    try { v = JSON.parse(readFileSync(file, "utf-8")); }
    catch (err) { throw new Error(`${key}: ${file} is not a JSON file: ${err instanceof Error ? err.message : err}`); }
  } else {
    // Only an object, a list, a quoted string, true, false or null is JSON. A number stays text,
    // so an index such as 1.2 keeps its form; OKB reads text as a number where it takes one.
    const json = /^\s*[[{"]/.test(text) || ["true", "false", "null"].includes(text.trim());
    if (json) { try { v = JSON.parse(text); } catch { v = text; } } else v = text;
  }
  if (topLevel && isFileArgument(key)) {
    if (typeof v === "string") return resolve(cwd, v);
    if (Array.isArray(v)) return v.map(one => resolve(cwd, String(one)));
    // A single file name for a list, such as progress_files=progress.json.
  }
  return v;
}

/** The saved session to use: the one named, the one the folder's actor file names, or the only one saved on this computer. */
export function account(project, email, home = homedir(), cwd = process.cwd()) {
  const root = join(home, ".config", "supabase-auth");
  if (!project) {
    const actor = readActor(cwd);
    if (actor && !actor.ok) throw new Error(actor.problem);
    if (actor) { project = actor.value.project_ref; email = actor.value.auth_email; }
  }
  if (project) {
    const who = { ref: project, email: accountEmail(email) };
    if (!existsSync(join(root, project, `${who.email}.json`))) throw new Error(`No sign-in is saved on this computer for ${who.email} on project ${project}. Sign in with: ${OKB_SIGN_IN}`);
    return who;
  }
  let saved = [];
  try {
    for (const ref of readdirSync(root)) {
      if (!PROJECT_REF.test(ref)) continue;
      for (const file of readdirSync(join(root, ref))) if (file.endsWith(".json")) saved.push({ ref, email: file.slice(0, -5) });
    }
  } catch { saved = []; }
  if (saved.length === 1) return saved[0];
  if (saved.length === 0) throw new Error(`No sign-in is saved on this computer. Sign in with: ${OKB_SIGN_IN}`);
  throw new Error(`More than one sign-in is saved on this computer. Name one with --project and --email: ${saved.map(s => `--project ${s.ref} --email ${s.email}`).join("; ")}`);
}

/** Runs one name with its arguments. Returns { ok, result } or { ok: false, problem }. */
export async function run({ project, email, name, args }, cwd = process.cwd(), home = homedir()) {
  const pages = pageTools({ agentFolder: cwd });
  const asked = name ?? "";
  let content;
  if (PAGE_TOOLS.some(t => t.name === asked)) {
    if (["draw_board", "draw_graph"].includes(asked)) {
      if (typeof args.progress_files === "string") args = { ...args, progress_files: [args.progress_files] };
    }
    content = await pages.callTool(asked, args);
  } else {
    const databaseTool = DATABASE_TOOLS.some(t => t.name === asked) && asked !== "read_file";
    if (!asked.startsWith("okb_") && !databaseTool) return { ok: false, problem: `${asked} is not an OKB function or a tool. ${USAGE}` };
    const who = account(project, email, home, cwd);
    const database = databaseTools({ ref: who.ref, email: who.email, agentFolder: cwd, defaultSchema: SCHEMA });
    if (asked.startsWith("okb_")) {
      const { result_file, ...callArgs } = args;
      content = await database.callTool("rpc", { function: asked, schema: SCHEMA, args: callArgs, ...(result_file === undefined ? {} : { result_file }) });
    } else {
      content = await database.callTool(asked, args);
    }
  }
  return JSON.parse(content.content[0].text);
}

const real = file => { try { return realpathSync(file); } catch { return file; } };
if (process.argv[1] && real(fileURLToPath(import.meta.url)) === real(resolve(process.argv[1]))) {
  if (process.argv[2] === "setup") {
    const words = process.argv.slice(3);
    if (words.includes("--help") || words.includes("-h")) { process.stdout.write(`${SETUP_USAGE}\n`); process.exit(0); }
    // OKB_SETUP_SIGN_IN and OKB_SETUP_SYNC name a stand-in sign-in and sync, for setup.test.mjs.
    process.exit(setup(words, { signInArgs, signInPath: process.env.OKB_SETUP_SIGN_IN || SIGN_IN,
      ...(process.env.OKB_SETUP_SYNC ? { syncArgs: [process.env.OKB_SETUP_SYNC] } : {}) }));
  }
  if (process.argv[2] === "uninstall") {
    const words = process.argv.slice(3);
    if (words.includes("--help") || words.includes("-h")) { process.stdout.write(`${UNINSTALL_USAGE}\n`); process.exit(0); }
    process.exitCode = await uninstall(words);
  } else if (process.argv[2] === "sync") {
    const words = process.argv.slice(3);
    if (words.includes("--help") || words.includes("-h")) { process.stdout.write(`${SYNC_USAGE}\n`); process.exit(0); }
    process.exitCode = await runSync(words);
  } else if (process.argv[2] === "sign-in") {
    let args;
    try { args = signInArgs(process.argv.slice(3)); }
    catch (err) { process.stderr.write(`${err instanceof Error ? err.message : err}\n`); process.exit(1); }
    const ran = spawnSync(process.execPath, args, { stdio: "inherit" });
    process.exit(ran.status ?? 1);
  } else {
    let options;
    try { options = parse(process.argv.slice(2)); }
    catch (err) { process.stderr.write(`${err instanceof Error ? err.message : err}\n${USAGE}\n`); process.exit(2); }
    if (options.name === undefined) { process.stdout.write(`${USAGE}\n`); process.exit(0); }
    // The plugin's own settings name the sign-in once for a terminal.
    if (options.project === undefined && !readActor(process.cwd()) && process.env.SUPABASE_PROJECT_REF && process.env.SUPABASE_AUTH_EMAIL) {
      options.project = process.env.SUPABASE_PROJECT_REF;
      options.email = process.env.SUPABASE_AUTH_EMAIL;
    }
    let out;
    try { out = await run(options); }
    catch (err) { out = { ok: false, problem: err instanceof Error ? err.message : String(err) }; }
    // The exit code is set, and Node ends once its connections close. Calling exit() with a connection
    // still open crashes Node on Windows, as sign-in.mjs found.
    if (out.ok === false) {
      process.stderr.write(`${String(out.problem).replace(" Never ask for the password in chat.", "")}\n`);
      process.exitCode = 1;
    } else {
      const { ok: _ok, ...rest } = out;
      process.stdout.write(JSON.stringify(Object.keys(rest).length === 1 && "result" in rest ? rest.result : rest, null, 2) + "\n");
    }
  }
}
