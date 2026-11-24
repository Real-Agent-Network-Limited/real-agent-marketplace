// Background updates of a person's Real Agent plugins, for the okb plugin's plugin-updates.mjs hook.
//
// - whoIs: the project and email a session's folder works as: its actor file's, or the okb plugin's settings for the
//   agent folder they name.
// - newerRelease: the newest release in the Plugins scope newer than the copy's RELEASE, whose MANIFEST carries Real
//   Agent's signature and whose plugin.json files match it, with the notes of each such release.
// - startSync: starts okb sync in the background, unless a run holds the lock beside the copy.
// - lastRun and endedLines: how the last background run ended, from the result okb sync writes beside the copy.
// - updateLines: what the hook tells the person, starting the update when a newer release is there.
//
// The hook reads OKB only with a saved access token that has more than five minutes left, so it never renews the
// sign-in: okb sync, the okb server and the hook would otherwise race for the one refresh token.
import { spawn as nodeSpawn } from "node:child_process";
import { closeSync, existsSync, openSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { listReleases, downloadFile, manifestEntries, releaseFiles, releaseKeysFor, sha256, verifyManifest, RELEASES_BUCKET, SIGNATURE } from "./releases.mjs";
import { readActor } from "../mcp/lib/actor-file.mjs";
import { accountEmail, PROJECT_REF, readSession } from "../mcp/lib/session.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
/** The okb command the background run starts: this plugin's own. */
export const OKB_COMMAND = resolve(HERE, "okb.mjs");
const json = file => { try { return JSON.parse(readFileSync(file, "utf8")); } catch { return null; } };
const setting = value => { const t = value?.trim(); return t && !/^\$\{.*\}$/.test(t) ? t : undefined; };

/** The commands a person runs by hand in their folder: macOS and Linux, then Windows, as the plugins skill gives them. */
export const SYNC_COMMANDS = ["node ~/.claude/plugins/marketplaces/real-agent/plugins/okb/cli/okb.mjs sync",
  'node "$env:USERPROFILE\\.claude\\plugins\\marketplaces\\real-agent\\plugins\\okb\\cli\\okb.mjs" sync'];
const runLines = () => [`In your folder, run this in Terminal, then start a new Code session: ${SYNC_COMMANDS[0]}`, `On Windows, run this in PowerShell: ${SYNC_COMMANDS[1]}`];

/** This computer's copy of the firm's plugins, as okb sync keeps it: okb-marketplace/<project reference> in the home folder. */
export const copyFolder = (ref, home = homedir()) => join(home, "okb-marketplace", ref);

/**
 * The project and email a session on the folder works as, { ref, email }, from the session folder sessionFolder gave:
 * an actor file's, or, for the agent folder the settings name, the okb plugin's project_ref and auth_email settings.
 * Null when neither names both.
 */
export function whoIs(at, env = process.env) {
  if (!at) return null;
  if (at.connection === "actor") {
    const actor = readActor(at.folder);
    return actor?.ok ? { ref: actor.value.project_ref, email: actor.value.auth_email } : null;
  }
  const ref = setting(env.CLAUDE_PLUGIN_OPTION_PROJECT_REF), email = accountEmail(setting(env.CLAUDE_PLUGIN_OPTION_AUTH_EMAIL));
  return ref && PROJECT_REF.test(ref) && email ? { ref, email } : null;
}

/** A saved access token is used only while more than this is left of it. */
export const FRESH_FOR = 5 * 60_000;

/** The access the saved sign-in gives, { url, key, token }, while its access token has more than five minutes left, or null. */
export function freshAccess(ref, email, now = Date.now()) {
  let saved;
  try { saved = readSession(ref, email); } catch { return null; }
  if (!(typeof saved?.accessToken === "string" && saved.accessToken && Number(saved.expiresAt) - FRESH_FOR > now)) return null;
  return { url: saved.url, key: saved.publishableKey, token: saved.accessToken };
}

/** The lines of a release's NOTES.md, each without its leading "- ", blank lines left out. */
export const noteLines = text => String(text).split(/\r?\n/).map(line => line.replace(/^\s*[-*]\s+/, "").trim()).filter(Boolean);

/**
 * The newest release in the Plugins scope that is newer than the copy's RELEASE, whose MANIFEST carries Real Agent's
 * signature, and whose plugin.json files match it, as { name, notes }, or null. A release with no signature, or one
 * that does not verify, is passed over, and its notes are never read. notes holds { release, lines } for each release
 * newer than the copy, up to that one, newest first, whose NOTES.md is listed in its MANIFEST and matches it. The reads
 * from OKB stop after waitMs. Null when the copy, OKB or a read fails, or after waitMs.
 */
export async function newerRelease(copy, access, waitMs = 3000) {
  let held;
  try { held = readFileSync(join(copy, "RELEASE"), "utf8").trim(); } catch { return null; }
  const look = (async () => {
    const listed = await listReleases(access);
    if (!listed.ok) return null;
    const read = async name => {
      const [manifest, signature] = await Promise.all([`${name}/MANIFEST`, `${name}/${SIGNATURE}`].map(path => downloadFile(access, RELEASES_BUCKET, path)));
      if (!manifest.ok) return manifest.missing ? { name } : null;
      if (!signature.ok) return signature.missing ? { name } : null;
      if (!verifyManifest(manifest.body, signature.body, RELEASES_BUCKET, name, releaseKeysFor(access.url))) return { name };
      let entries;
      try { entries = manifestEntries(manifest.body.toString("utf8")); } catch { return { name }; }
      const own = entries.filter(e => /^plugins\/[^/]+\/\.claude-plugin\/plugin\.json$/.test(e.path));
      const notes = entries.find(e => e.path === "NOTES.md");
      const got = await releaseFiles(access, RELEASES_BUCKET, name, [...own, ...(notes ? [notes] : [])].map(e => e.path));
      const matches = (g, e) => g?.ok && sha256(g.body) === e.hash;
      const lines = notes && matches(got.at(-1), notes) ? noteLines(got.at(-1).body.toString("utf8")) : [];
      return { name, ok: own.every((e, i) => matches(got[i], e)), lines };
    };
    const found = await Promise.all(listed.names.filter(n => n > held).map(read));
    // A release that could not be read stops the look, as the newest one cannot then be told.
    if (found.some(f => f === null)) return null;
    const newest = found.find(f => f.ok);
    if (!newest) return null;
    return { name: newest.name, notes: found.filter(f => f.name <= newest.name && f.lines?.length).map(f => ({ release: f.name, lines: f.lines })) };
  })().catch(() => null);
  let timer;
  const late = new Promise(done => { timer = setTimeout(() => done(null), waitMs); });
  try { return await Promise.race([look, late]); } finally { clearTimeout(timer); }
}

/** The background run's files beside the copy: the lock okb sync takes, its log, its result and the hook's checks. */
export const syncFiles = copy => ({ lock: `${copy}.lock`, log: `${copy}.sync.log`, result: `${copy}.sync.json`, checks: `${copy}.sync-check.json` });

/** True while the process the id names runs. */
function alive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; } catch (err) { return err.code === "EPERM"; }
}

// A lock taken by a hook that has not yet written its run's process id, younger than this, is a start under way.
const CLAIMING_FOR = 10_000;

/**
 * Starts okb sync for the project and email in the background, with this Node, from the home folder, its output in the
 * log beside the copy. Returns "running", and starts nothing, while the lock beside the copy names a process that runs.
 * Otherwise it takes the lock for the run, writes the run's process id into it, and returns "started"; okb sync keeps
 * the lock that names it. Null when the run could not be started.
 */
export function startSync({ copy, ref, email, spawn = nodeSpawn, home = homedir(), command = OKB_COMMAND }) {
  const { lock, log } = syncFiles(copy);
  for (let tries = 0; tries < 2; tries++) {
    try {
      writeFileSync(lock, "", { flag: "wx" });
      break;
    } catch (err) {
      if (err.code !== "EEXIST") return null;
      let text = "", age = Infinity;
      try { text = readFileSync(lock, "utf8").trim(); age = Date.now() - statSync(lock).mtimeMs; } catch {}
      if (alive(Number(text)) || (!text && age < CLAIMING_FOR)) return "running";
      if (tries) return "running";
      try { rmSync(lock, { force: true }); } catch {}
    }
  }
  if (!existsSync(command)) { try { rmSync(lock, { force: true }); } catch {} return null; }
  let out;
  try {
    out = openSync(log, "w");
    const child = spawn(process.execPath, [command, "sync", "--project", ref, "--email", email], { detached: true, windowsHide: true, cwd: home, stdio: ["ignore", out, out] });
    child.on?.("error", () => {});
    // A spawn that fails reports it later, and gives no process id.
    if (!Number.isInteger(child.pid)) { try { rmSync(lock, { force: true }); } catch {} return null; }
    writeFileSync(lock, `${child.pid}\n`);
    child.unref?.();
    return "started";
  } catch {
    try { rmSync(lock, { force: true }); } catch {}
    return null;
  } finally { if (out !== undefined) closeSync(out); }
}

/** The result of the last okb sync run, from the file beside the copy, or null. */
export const lastRun = copy => json(syncFiles(copy).result);

/** At most ten note lines, then "and <n> more". */
export function shownNotes(notes) {
  const lines = notes.flatMap(n => n.lines);
  return lines.length > 10 ? [...lines.slice(0, 10), `and ${lines.length - 10} more`] : lines;
}

/** The lines that tell the person a run has ended: its release and notes after exit code 0, or that the update ended
 * when the release did not change, or its last line and the commands after exit code 1. */
export function endedLines(run) {
  if (run?.code === 1) return [`The update of your Real Agent plugins stopped: ${run.last || "it gave no reason"}`, ...runLines()];
  if (run?.from && run.from === run.release) return ["The update of your Real Agent plugins has ended.", "Start a new Code session to use them."];
  const shown = shownNotes(Array.isArray(run?.notes) ? run.notes : []);
  return [`Your Real Agent plugins are updated to release ${run?.release}.${shown.length ? " It brings:" : ""}`, ...shown, "Start a new Code session to use them."];
}

/**
 * What the hooks tell the person about their plugins, as { lines, notes, sync }. When the Plugins scope holds a release
 * newer than the copy, it starts okb sync in the background, and says the update is installing, with the notes of each
 * newer release. It reads OKB only while the saved sign-in has more than five minutes left. After a run that stopped
 * with exit code 1, it names its last line and the commands, unless failure is false, and starts no run until OKB holds
 * a release newer than that run's. notes holds each note line, for the agent. sync is "started", "running" or null.
 */
export async function updateLines({ copy, ref, email, waitMs = 3000, release = newerRelease, access = freshAccess, spawn = nodeSpawn, home = homedir(), failure = true } = {}) {
  const last = lastRun(copy);
  const failed = last?.code === 1 ? last : null;
  const stopped = failed && failure ? [`The last update of your Real Agent plugins stopped: ${failed.last || "it gave no reason"}`] : [];
  const signedIn = existsSync(join(copy, "RELEASE")) ? access(ref, email) : null;
  const newer = signedIn ? await release(copy, signedIn, waitMs) : null;
  if (!newer) return { lines: stopped.length ? [...stopped, ...runLines()] : [], notes: [], sync: null };
  const notes = newer.notes ?? [];
  const found = `A newer release of your Real Agent plugins is in OKB, ${newer.name}.`;
  // A failed run is tried again only for a release newer than its own.
  const retry = !failed || newer.name > String(failed.release ?? "");
  const sync = retry ? startSync({ copy, ref, email, spawn, home }) : null;
  if (!sync) return { lines: [found, ...stopped, ...runLines()], notes: notes.flatMap(n => n.lines), sync };
  const shown = shownNotes(notes);
  const installing = shown.length ? ["A new release of your Real Agent plugins is installing in the background. It brings:", ...shown]
    : ["A new release of your Real Agent plugins is installing in the background."];
  return { lines: [found, ...installing, "Start a new Code session once it ends, in about two minutes, to use it."], notes: notes.flatMap(n => n.lines), sync };
}
