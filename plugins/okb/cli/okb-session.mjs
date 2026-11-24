// A person's saved sign-in to their client's project, opened for okb sync and publish-plugin.mjs: the
// sign-in --project and --email name, else the one the folder's actor file names, else the only one
// saved on this computer. The access it gives, { url, key, token }, lists, downloads and publishes
// releases as the person, under OKB's grants.
import { readdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readActor } from "../mcp/lib/actor-file.mjs";
import { accountEmail, PROJECT_REF, sessionAccess } from "../mcp/lib/session.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const quote = value => process.platform === "win32" ? `"${value}"` : `'${String(value).replaceAll("'", `'\\''`)}'`;
/** The command that signs the person in, from the okb plugin beside this file. */
export const SIGN_IN = `node ${quote(resolve(HERE, "okb.mjs"))} sign-in`;

/** The sign-in to use, as { ref, email }. Throws, naming the sign-in command, when there is none to use. */
export function whichSignIn({ project, email, cwd = process.cwd(), home = homedir() } = {}) {
  if ((project === undefined) !== (email === undefined)) throw new Error("--project and --email go together.");
  if (project !== undefined) {
    if (!PROJECT_REF.test(project)) throw new Error(`${project} is not a project reference.`);
    if (!accountEmail(email)) throw new Error(`${email} is not an email address.`);
    return { ref: project, email: accountEmail(email) };
  }
  const actor = readActor(cwd);
  if (actor && !actor.ok) throw new Error(actor.problem);
  if (actor) return { ref: actor.value.project_ref, email: actor.value.auth_email };
  const root = join(home, ".config", "supabase-auth");
  const saved = [];
  try {
    for (const ref of readdirSync(root)) {
      if (!PROJECT_REF.test(ref)) continue;
      for (const file of readdirSync(join(root, ref))) if (file.endsWith(".json") && !file.startsWith(".")) saved.push({ ref, email: file.slice(0, -5) });
    }
  } catch { /* none saved */ }
  if (saved.length === 1) return saved[0];
  if (!saved.length) throw new Error(`No sign-in is saved on this computer. In your folder, sign in with: ${SIGN_IN}`);
  throw new Error(`More than one sign-in is saved on this computer. Run this in your folder, or name one with --project and --email: ${saved.map(s => `--project ${s.ref} --email ${s.email}`).join("; ")}`);
}

/**
 * Opens the saved sign-in: { ok: true, ref, email, access: { url, key, token } } or { ok: false, problem }.
 * sessionAccess renews it at most about once an hour, one process at a time.
 */
export async function openAccess(options = {}) {
  let who;
  try { who = whichSignIn(options); } catch (err) { return { ok: false, problem: err.message }; }
  const { ref, email } = who;
  const signIn = `Sign in again in your folder with: ${SIGN_IN}`;
  let opened;
  try { opened = await sessionAccess(ref, email); }
  catch (err) {
    if (err?.cause || err instanceof TypeError) return { ok: false, problem: `Project ${ref} could not be reached: ${err?.cause?.code ?? err?.message ?? err}` };
    return { ok: false, problem: `${err.message} ${signIn}` };
  }
  if (opened.missing) return { ok: false, problem: `${email} is not signed in to project ${ref} on this computer. ${signIn}` };
  if (opened.wrongUser) return { ok: false, problem: `The saved sign-in is for ${opened.wrongUser}, not ${email}. ${signIn}` };
  if (!opened.ok && opened.status) return { ok: false, problem: `Project ${ref} ended ${email}'s sign-in: ${opened.problem}. ${signIn}` };
  if (!opened.ok) return { ok: false, problem: opened.problem };
  return { ok: true, ref, email, access: { url: opened.url, key: opened.key, token: opened.token } };
}
