// The actor file, `.okb-actor.json`, in a person's folder: the client's project and the email a session
// opened on that folder signs in with. The folder itself is the agent folder, the one folder the person
// puts files in and the agent uploads from. An actor file written before the agent folder was the only
// folder also names an upload folder, which is ignored. One folder works in one project, as one person.
// It holds no password or token. The sign-in's --folder writes it; choose.mjs, the hooks and the okb
// command read it.
import { closeSync, fsyncSync, lstatSync, openSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { join } from "node:path";
import { accountEmail, PROJECT_REF } from "./session.mjs";

export const ACTOR_FILE = ".okb-actor.json";
const FIELDS = ["auth_email", "project_ref"];
const OLD_FIELDS = ["auth_email", "project_ref", "upload_folder"];

/**
 * The actor file in `folder`: `null` when there is none, `{ ok: true, value }` for a valid one, and
 * `{ ok: false, problem }` for one that cannot be used. A broken file is a refusal, never a reason to
 * fall back to the plugin's settings, which name another actor.
 */
export function readActorFile(folder) {
  if (!folder) return null;
  const path = join(folder, ACTOR_FILE);
  let stat;
  try { stat = lstatSync(path); } catch (err) { if (err?.code === "ENOENT" || err?.code === "ENOTDIR") return null; return { ok: false, problem: `${path} could not be read: ${err?.message ?? err}` }; }
  if (stat.isSymbolicLink() || !stat.isFile()) return { ok: false, problem: `${path} is not a file. Delete it and sign in again with --folder.` };
  let value;
  try { value = JSON.parse(readFileSync(path, "utf-8")); }
  catch { return { ok: false, problem: `${path} is not JSON. Delete it and sign in again with --folder.` }; }
  const bad = `${path} is not a valid actor file. Delete it and sign in again with --folder.`;
  const fields = value && typeof value === "object" && !Array.isArray(value) ? Object.keys(value).sort().join(",") : null;
  if (fields !== FIELDS.join(",") && fields !== OLD_FIELDS.join(",")) return { ok: false, problem: bad };
  if (!PROJECT_REF.test(String(value.project_ref)) || accountEmail(value.auth_email) !== value.auth_email) return { ok: false, problem: bad };
  return { ok: true, value: { project_ref: value.project_ref, auth_email: value.auth_email } };
}

/**
 * The session folder's actor file, with the folder resolved: null when there is none,
 * `{ ok: true, folder, value }` for a valid one, and `{ ok: false, problem }` for one that cannot be used.
 */
export function readActor(session) {
  if (!session) return null;
  let root;
  try { root = realpathSync.native(session); } catch { return null; }
  const found = readActorFile(root);
  return found?.ok ? { ...found, folder: root } : found;
}

/** The session folder's resolved path when it holds a valid actor file, or null. */
export function actorFolder(session) {
  const actor = readActor(session);
  return actor?.ok ? actor.folder : null;
}

/** Writes the actor file into `folder`, replacing one there, through a temporary file renamed into place. */
export function writeActorFile(folder, { projectRef, email }) {
  const root = realpathSync.native(folder);
  const target = join(root, ACTOR_FILE);
  try { if (lstatSync(target).isSymbolicLink()) throw new Error(`${target} is a link. Delete it and sign in again.`); }
  catch (err) { if (err?.code !== "ENOENT") throw err; }
  const temporary = join(root, `.${process.pid}.${randomUUID()}.tmp`);
  const fd = openSync(temporary, "wx", 0o644);
  try {
    writeFileSync(fd, JSON.stringify({ project_ref: projectRef, auth_email: email }, null, 2) + "\n");
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  try { renameSync(temporary, target); }
  catch (err) { rmSync(temporary, { force: true }); throw err; }
  return target;
}
