// Updates the person's Real Agent plugins in the background, in a session on a folder with an actor file or on the agent
// folder the okb plugin's settings name.
//
// At SessionStart it writes the session's entry in okb-marketplace/<ref>.sync-check.json, beside the copy, and calls
// updateLines: when the Plugins scope holds a newer signed release, it starts okb sync in the background and says so,
// with the release's notes; after a background run that stopped, it names the run's last line and the command to run
// by hand. At UserPromptSubmit it does the same once an hour; between those checks it reads only the files beside the
// copy. At the first prompt after a background run that ended since the session started, it tells the person once:
// the release and its notes, or the run's last line and the command. The lines go to the person as systemMessage, and
// to the agent as additionalContext, with every note line. A session on any other folder, or with nothing to say, gets
// nothing, and any failure adds nothing: the session goes on as it would without the hook.
import { readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { stdin, stdout } from "node:process";
import { fileURLToPath } from "node:url";

export const HOUR = 60 * 60_000;
const DAY = 24 * HOUR;

/** Each session's entry, by session id, or {} when the file cannot be read. */
export function readChecks(file) {
  try {
    const held = JSON.parse(readFileSync(file, "utf8"));
    return held && typeof held.sessions === "object" && held.sessions ? held.sessions : {};
  } catch { return {}; }
}

/**
 * Writes one session's entry. The file is read again just before the write, so another session's entry written
 * meanwhile is kept. Each entry whose last check is older than one day is removed.
 */
export function writeCheck(file, session, entry, now = Date.now()) {
  const sessions = { ...readChecks(file), [session]: entry };
  const kept = Object.fromEntries(Object.entries(sessions).filter(([, e]) => now - Date.parse(e?.checked ?? 0) < DAY));
  const part = `${file}.${process.pid}`;
  writeFileSync(part, `${JSON.stringify({ sessions: kept }, null, 2)}\n`);
  renameSync(part, file);
}

/** The text for the person and the text for the agent, from the lines and the note lines. */
function texts(lines, notes) {
  const text = ["Your Real Agent plugins:", ...lines.map(line => `- ${line}`)].join("\n");
  const context = notes.length ? `${text}\n\nThe release notes in full:\n${notes.map(line => `- ${line}`).join("\n")}` : text;
  return { text, context };
}

/** The hook's output for one input from Claude Code, or null. options stand in for the home folder, the clock and updateLines. */
export async function output(input, { env = process.env, home, now = Date.now(), update } = {}) {
  const event = input?.hook_event_name;
  const session = input?.session_id;
  if (!session || (event !== "SessionStart" && event !== "UserPromptSubmit")) return null;
  const { sessionFolder } = await import("./session-history.mjs");
  const updates = await import("../cli/plugin-updates.mjs");
  const who = updates.whoIs(sessionFolder(input?.cwd, env), env);
  if (!who) return null;
  const copy = updates.copyFolder(who.ref, home);
  const file = updates.syncFiles(copy).checks;
  const entry = readChecks(file)[session];
  const at = new Date(now).toISOString();
  const started = entry?.started ?? at;
  const lines = [], notes = [];
  // A run that ended since the session started, and that this session was not told of, is told at the next prompt.
  const run = updates.lastRun(copy);
  let told = entry?.told ?? null;
  if (event === "UserPromptSubmit" && run?.ended && Date.parse(run.ended) >= Date.parse(started) && told !== run.ended) {
    lines.push(...updates.endedLines(run));
    if (run.code !== 1) notes.push(...(run.notes ?? []).flatMap(n => n.lines ?? []));
    told = run.ended;
  }
  // OKB is read at the start of a session, and then at most once an hour.
  const due = event === "SessionStart" || !entry || now - Date.parse(entry.checked) >= HOUR;
  if (!due && !lines.length) return null;
  const found = due ? await (update ?? updates.updateLines)({ copy, ref: who.ref, email: who.email, ...(home ? { home } : {}), failure: event === "SessionStart" }) : { lines: [], notes: [] };
  // The commands to run by hand are given once, though a stopped run and a finding both give them.
  for (const line of found.lines) if (!lines.includes(line)) lines.push(line);
  notes.push(...found.notes);
  try { writeCheck(file, session, { started, checked: due ? at : entry.checked, ...(told ? { told } : {}) }, now); } catch {}
  if (!lines.length) return null;
  const { text, context } = texts(lines, notes);
  return { systemMessage: text, hookSpecificOutput: { hookEventName: event, additionalContext: context } };
}

const real = file => { try { return realpathSync(file); } catch { return file; } };
if (process.argv[1] && real(fileURLToPath(import.meta.url)) === real(process.argv[1])) {
  try {
    let text = "";
    for await (const chunk of stdin) text += chunk;
    let input = {};
    try { input = JSON.parse(text); } catch {}
    const out = await output(input);
    if (out) stdout.write(JSON.stringify(out));
  } catch {}
  process.exit(0);
}
