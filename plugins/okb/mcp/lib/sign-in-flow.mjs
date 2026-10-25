// The sign-in's steps, apart from the terminal, so a test can answer its questions.
import { statSync } from "node:fs";
import { resolve } from "node:path";
import { writeActorFile } from "./actor-file.mjs";
import { accountEmail, passwordSignIn, projectUrl, readSession, refFromUrl, setPassword, writeSession, PROJECT_REF } from "./session.mjs";

export const USAGE = "Usage: node sign-in.mjs [--project <ref> --email <email>] [--url <project URL> --key <publishable key>] [--new-password] [--folder <session folder>]";

export function options(args) {
  const out = { project: undefined, email: undefined, url: undefined, key: undefined, newPassword: false, folder: undefined };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--new-password") out.newPassword = true;
    else if (args[i] === "--project" && args[i + 1]) out.project = args[++i];
    else if (args[i] === "--email" && args[i + 1]) out.email = args[++i];
    else if (args[i] === "--url" && args[i + 1]) out.url = args[++i];
    else if (args[i] === "--key" && args[i + 1]) out.key = args[++i];
    else if (args[i] === "--folder" && args[i + 1]) out.folder = args[++i];
    else throw new Error(`unknown option ${args[i]}. ${USAGE}`);
  }
  if (out.project !== undefined && !PROJECT_REF.test(out.project)) throw new Error(`${out.project} is not a project reference.`);
  // --email alone answers the email question; with --project it names a saved sign-in.
  if (out.project !== undefined && out.email === undefined) throw new Error(`--project and --email go together. ${USAGE}`);
  if (out.email !== undefined && !accountEmail(out.email)) throw new Error(`${out.email} is not an email address.`);
  if ((out.url === undefined) !== (out.key === undefined)) throw new Error(`--url and --key go together. ${USAGE}`);
  if (out.url !== undefined && !projectUrl(out.url)) throw new Error(`${out.url} is not a project URL.`);
  // Checked before the password is asked for, so a mistyped folder costs nothing.
  if (out.folder !== undefined) {
    let folder = false;
    try { folder = statSync(out.folder).isDirectory(); } catch { folder = false; }
    if (!folder) throw new Error(`${out.folder}, given as --folder, is not a folder. Make it first.`);
    out.folder = resolve(out.folder);
  }
  return out;
}

/**
 * `ask(prompt, hidden)` answers each question; `say` prints a line. Returns the saved file's path.
 * With `folder`, it also writes that folder's actor file, so a session opened on the folder works as
 * this user, with the folder as its agent folder.
 */
export async function signIn({ project, email: given, url: knownUrl, key: knownKey, newPassword, folder }, ask, say) {
  const saved = project ? readSession(project, accountEmail(given)) : null;
  if (project && !saved) throw new Error(`nothing is saved for ${given} on ${project}. Run without --project to enter the details.`);

  const url = saved?.url ?? projectUrl(knownUrl ?? await ask("Project URL: "));
  if (!url) throw new Error("the project URL starts https:// and comes from the dashboard's Connect button.");
  // A custom domain hides the reference, so it is asked for.
  const ref = project ?? refFromUrl(url) ?? await ask("Project reference: ");
  if (!PROJECT_REF.test(ref)) throw new Error(`${ref} is not a project reference. It is under Project Settings → General.`);
  const key = saved?.publishableKey ?? knownKey ?? await ask("Publishable key: ");
  const email = accountEmail(saved?.email ?? given ?? await ask("Email: "));
  if (!email) throw new Error("that is not an email address.");
  if (saved || given) say(`Signing in to ${ref} as ${email}.`);

  const typed = await ask("Password: ", true);
  let session = await passwordSignIn(url, key, email, typed);
  if (!session.ok) throw new Error(`Supabase refused the sign-in: ${session.problem}`);

  const first = newPassword ? await ask("New password: ", true) : null;
  if (newPassword && first !== await ask("New password again: ", true)) throw new Error("the new passwords differ. Nothing was changed.");
  // Supabase refuses a new password that is the one the person has, so the one they have stays.
  if (newPassword && first === typed) say("The new password is the one you have, and stays.");
  else if (newPassword) {
    const changed = await setPassword(url, key, session.body.access_token, first);
    if (!changed.ok) throw new Error(`Supabase refused the new password: ${changed.problem}`);
    // A fresh session under the new password, rather than trusting the old one survived the change.
    session = await passwordSignIn(url, key, email, first);
    if (!session.ok) throw new Error(`the password changed, but signing in with it failed: ${session.problem}`);
    say("Password changed.");
  }

  const signedIn = accountEmail(session.body.user?.email);
  if (signedIn !== email) throw new Error(`Supabase signed in ${session.body.user?.email}, not ${email}. Nothing was saved.`);
  const path = writeSession(ref, email, { projectRef: ref, url, publishableKey: key, email, refreshToken: session.body.refresh_token });
  say(`Signed in as ${email}. Session saved to ${path}.`);
  if (folder !== undefined) {
    const actor = writeActorFile(folder, { projectRef: ref, email });
    say(`Actor file saved to ${actor}. A session opened on ${folder} works as ${email}.`);
  } else {
    say(`Set auth_email to ${email} in the okb plugin's settings, or sign in again with --folder to work as ${email} in one folder.`);
  }
  return path;
}
