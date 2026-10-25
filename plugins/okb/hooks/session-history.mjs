// Copies the person's sessions with their agent into <agent folder>/sessions/, as Markdown, and starts
// session-upload.mjs to put each new copy in their sessions scope in OKB. Runs for a session opened on
// a folder with an actor file, or on the agent folder the okb plugin's settings name, and does nothing
// elsewhere. On Stop it copies the session that has just replied. On SessionStart it copies each session
// in the same Claude Code project folder whose copy is missing or older than its JSONL file.
import { spawn } from "node:child_process";
import { mkdirSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { env, execPath, stdin } from "node:process";
import { fileURLToPath } from "node:url";
import { copySession, uploaded } from "./session-copy.mjs";
import { actorFolder } from "../mcp/lib/actor-file.mjs";

const setting = value => { const t = value?.trim(); return t && !/^\$\{.*\}$/.test(t) ? t : undefined; };
const samePath = (one, other) => process.platform === "win32" ? one.toLowerCase() === other.toLowerCase() : one === other;
const real = path => { try { return realpathSync.native(path); } catch { return null; } };

/** The agent folder the session is opened on, and which connection it is (`actor` for a folder with an
 * actor file, `settings` for the agent folder the okb plugin's settings name), or null for any other folder. */
export function sessionFolder(cwd, options = env) {
  const session = real(cwd ?? "");
  if (!session) return null;
  const actor = actorFolder(session);
  if (actor) return { folder: actor, connection: "actor" };
  const folder = setting(options.CLAUDE_PLUGIN_OPTION_AGENT_FOLDER);
  const root = folder && real(folder);
  if (root && samePath(session, root)) return { folder: root, connection: "settings" };
  return null;
}

const modified = path => { try { return statSync(path).mtimeMs; } catch { return 0; } };

/** Writes the copy of each JSONL file given whose copy is missing or older. A copy whose session's title
 * has changed since is replaced. Returns the copies written, and the names of the copies replaced. */
export function copySessions(jsonlFiles, sessionsFolder) {
  mkdirSync(sessionsFolder, { recursive: true });
  const known = new Map();
  for (const name of readdirSync(sessionsFolder)) if (name.endsWith(".md")) known.set(name.slice(-11, -3), join(sessionsFolder, name));
  const written = [], replaced = [];
  for (const jsonl of jsonlFiles) {
    // A copy is named for its session's id, whose first 8 characters end the name.
    const before = known.get(jsonl.split(/[\\/]/).at(-1).slice(0, 8));
    if (before && modified(before) >= modified(jsonl)) continue;
    const copy = copySession(jsonl);
    if (!copy) continue;
    const file = join(sessionsFolder, copy.name);
    writeFileSync(file, copy.text);
    written.push(file);
    if (before && basename(before) !== copy.name) {
      rmSync(before, { force: true });
      replaced.push(basename(before));
    }
  }
  return { written, replaced };
}

/** Runs the hook for one input from Claude Code. Returns the copies written and replaced. */
export function run(input, options = env, upload = startUpload) {
  const at = sessionFolder(input?.cwd, options);
  const transcript = input?.transcript_path;
  if (!at || !transcript) return { written: [], replaced: [] };
  const sessionsFolder = join(at.folder, "sessions");
  let files = [transcript];
  if (input.hook_event_name === "SessionStart") {
    const project = dirname(transcript);
    files = readdirSync(project).filter(name => name.endsWith(".jsonl")).map(name => join(project, name));
  }
  const copied = copySessions(files, sessionsFolder);
  // At the start, each copy not yet uploaded as it now stands goes too, such as one whose upload failed.
  if (input.hook_event_name === "SessionStart") {
    const done = uploaded(sessionsFolder);
    for (const name of readdirSync(sessionsFolder)) {
      const file = join(sessionsFolder, name);
      if (name.endsWith(".md") && done[name] !== modified(file) && !copied.written.includes(file)) copied.written.push(file);
    }
  }
  if (copied.written.length || copied.replaced.length) upload(sessionsFolder, at.connection, copied);
  return copied;
}

/** Starts the upload in a process of its own, which runs on after the hook has returned. */
function startUpload(sessionsFolder, which, { written, replaced }) {
  const script = fileURLToPath(new URL("./session-upload.mjs", import.meta.url));
  const names = [...written.map(file => basename(file)), ...replaced.map(name => `-${name}`)];
  const child = spawn(execPath, [script, sessionsFolder, which, ...names], { detached: true, stdio: "ignore", windowsHide: true });
  child.unref();
}

if (process.argv[1] && real(fileURLToPath(import.meta.url)) === real(process.argv[1])) {
  let text = "";
  for await (const chunk of stdin) text += chunk;
  try { run(JSON.parse(text)); } catch { /* a session that cannot be copied is left for the next start */ }
}
