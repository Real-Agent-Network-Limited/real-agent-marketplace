// The sign-in's steps, apart from the terminal, so a test can answer its questions.
import { chmodSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { writeActorFile } from "./actor-file.mjs";
import { accountEmail, currentUser, enrolFactor, passwordSignIn, projectUrl, readSession, refFromUrl, removeFactor, setPassword, signInLevel, verifiedFactors, verifyFactor, writeSession, PROJECT_REF } from "./session.mjs";

export const USAGE = "Usage: node sign-in.mjs [--project <ref> --email <email>] [--url <project URL> --key <publishable key>] [--new-password] [--second-factor] [--folder <session folder>]";
export const OWNER_USAGE = "Usage: node sign-in.mjs --owner --url <project URL> --key <publishable key> --folder <setup folder>";
export const JOIN_USAGE = "Usage: node sign-in.mjs --join --url <project URL> --key <publishable key> [--email <email>] [--folder <session folder>]";
/** The file in the owner's setup folder that holds the sign-in code setup's build.mjs wrote. */
export const OWNER_CODE_FILE = ".okb-owner-code";
/** The file in the owner's setup folder where the sign-in saves Real Agent's invitation codes, for setup's summary. */
export const REAL_AGENT_CODE_FILE = ".okb-real-agent-code";

export function options(args) {
  const out = { project: undefined, email: undefined, url: undefined, key: undefined, newPassword: false, secondFactor: false, folder: undefined, owner: false, join: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--new-password") out.newPassword = true;
    else if (args[i] === "--second-factor") out.secondFactor = true;
    else if (args[i] === "--owner") out.owner = true;
    else if (args[i] === "--join") out.join = true;
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
  if (out.owner && (out.url === undefined || out.folder === undefined || out.project !== undefined || out.email !== undefined || out.newPassword || out.secondFactor))
    throw new Error(`--owner takes --url, --key and --folder, and no other option. ${OWNER_USAGE}`);
  if (out.join && (out.owner || out.url === undefined || out.project !== undefined || out.newPassword || out.secondFactor))
    throw new Error(`--join takes --url and --key, and may take --email and --folder. ${JOIN_USAGE}`);
  // Checked before the password is asked for, so a mistyped folder costs nothing.
  if (out.folder !== undefined) {
    let folder = false;
    try { folder = statSync(out.folder).isDirectory(); } catch { folder = false; }
    if (!folder) throw new Error(`${out.folder}, given as --folder, is not a folder. Make it first.`);
    out.folder = resolve(out.folder);
  }
  return out;
}

/** The name the account's authenticator app is kept under in Supabase Auth, and shows in the app. */
export const FACTOR_NAME = "Real Agent";

/**
 * The second factor's step, after the password. With an authenticator app on the account, it asks for the app's code
 * until Supabase takes one, and returns the session the code gives. With `enrol` and no app on the account, it adds one:
 * it prints the secret and the otpauth:// address, and asks for a code from the app to finish. An empty code stops the
 * sign-in. Without an app and without `enrol`, it returns the session as it is.
 */
export async function secondFactor(url, key, session, ask, say, enrol = false) {
  const token = session.body.access_token;
  const user = await currentUser(url, key, token);
  if (!user.ok) throw new Error(`Supabase did not give the account's sign-in methods: ${user.problem}`);
  let [factor] = verifiedFactors(user.body);
  let adding = false;
  if (!factor && !enrol) return session;
  if (factor && enrol) say("This account already has an authenticator app. Type its code to sign in.");
  if (!factor) {
    // An app started and never finished is removed, so its name is free.
    for (const left of (user.body.factors ?? []).filter(f => f.factor_type === "totp" && f.status !== "verified")) await removeFactor(url, key, token, left.id);
    const started = await enrolFactor(url, key, token, FACTOR_NAME);
    if (!started.ok) throw new Error(`Supabase refused the authenticator app: ${started.problem}`);
    factor = { id: started.body.id };
    adding = true;
    say("Add Real Agent to your authenticator app. Scan a QR code made from the address, or type the secret into the app.");
    say(`Secret: ${started.body.totp?.secret}`);
    say(`Address: ${started.body.totp?.uri}`);
  }
  for (;;) {
    const code = (await ask("Code: ")).replace(/\s+/g, "");
    if (!code) {
      if (adding) await removeFactor(url, key, token, factor.id);
      throw new Error(adding ? "no code was typed. The authenticator app was not added." : "no code was typed. Nothing was saved.");
    }
    const verified = await verifyFactor(url, key, token, factor.id, code);
    if (verified.ok) {
      if (adding) say("The authenticator app is added. Each sign-in asks for its code from now on. Sign in again in each of your other folders.");
      return verified;
    }
    say(`Supabase refused the code: ${verified.problem} Type the code your authenticator app shows now, or press Return with nothing typed to stop.`);
  }
}

const AGAIN = "Type the new password again, or press Return with nothing typed to stop.";

/**
 * A password the person chooses, asked twice until the two match. `take(password)` gives null when it is taken, or
 * the problem, and the password is asked for again. An empty one stops with nothing changed.
 */
async function choosePassword(ask, say, [prompt, again], take = async () => null) {
  for (;;) {
    const password = await ask(prompt, true);
    if (!password) throw new Error("no password was typed. Nothing was changed.");
    if (password !== await ask(again, true)) { say(`The two passwords differ. ${AGAIN}`); continue; }
    const problem = await take(password);
    if (!problem) return password;
    say(`${problem} ${AGAIN}`);
  }
}

/**
 * `ask(prompt, hidden)` answers each question; `say` prints a line. Returns the saved file's path.
 * With `folder`, it also writes that folder's actor file, so a session opened on the folder works as
 * this user, with the folder as its agent folder.
 */
export async function signIn({ project, email: given, url: knownUrl, key: knownKey, newPassword, secondFactor: enrol = false, folder }, ask, say) {
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

  // An account with an authenticator app gives its code before anything else is done as it.
  if (newPassword) session = await secondFactor(url, key, session, ask, say);
  if (newPassword) {
    // Asked until the two match and Supabase takes it. Supabase refuses a new password that is the one the person
    // has, so the one they have stays.
    const first = await choosePassword(ask, say, ["New password: ", "New password again: "], async password => {
      if (password === typed) return null;
      const changed = await setPassword(url, key, session.body.access_token, password);
      return changed.ok ? null : `Supabase refused the new password: ${changed.problem}`;
    });
    if (first === typed) say("The new password is the one you have, and stays.");
    else {
      // A fresh session under the new password, rather than trusting the old one survived the change.
      session = await passwordSignIn(url, key, email, first);
      if (!session.ok) throw new Error(`the password changed, but signing in with it failed: ${session.problem}`);
      say("Password changed.");
    }
  }

  // A session that already gave a code, as one that kept its password after --new-password has, is not asked again.
  const password = session;
  if (signInLevel(session.body.access_token) !== "aal2") session = await secondFactor(url, key, session, ask, say, enrol);
  // The code's answer names the same account as the password's.
  if (session !== password && session.body.user?.id !== password.body.user?.id) throw new Error("Supabase's answer to the code names another account. Nothing was saved.");

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

/**
 * The owner's first sign-in, at the end of setup's build. It reads the sign-in code build.mjs wrote to the setup
 * folder, asks the owner's name, email and the password they choose, twice, and sends them with the code to the
 * okb-setup hosted function, which makes their Auth user. Then it signs in with that password, saves the session
 * and the folder's actor file, and deletes the code file. The password goes only to the project. inSetup is true when
 * okb setup --owner runs it, and goes on with setup itself.
 */
export async function ownerSignIn({ url: knownUrl, key, folder, inSetup = false }, ask, say) {
  const url = projectUrl(knownUrl);
  const codeFile = join(folder, OWNER_CODE_FILE);
  let code;
  try { code = readFileSync(codeFile, "utf-8").trim(); } catch { code = ""; }
  if (!code) throw new Error(`${folder} holds no sign-in code. Ask your business analyst to carry on with setup.`);
  const ref = refFromUrl(url) ?? await ask("Project reference: ");
  if (!PROJECT_REF.test(ref)) throw new Error(`${ref} is not a project reference.`);
  say("Choose your own sign-in to your firm's Real Agent knowledge base. Your password goes only to your firm's Supabase project.");
  const name = (await ask("Your name: ")).trim();
  if (!name) throw new Error("your name is needed. Nothing was changed.");
  const email = accountEmail(await ask("Your email: "));
  if (!email) throw new Error("that is not an email address. Nothing was changed.");
  const password = await choosePassword(ask, say, ["Choose a password: ", "The password again: "]);

  let made;
  try {
    const response = await fetch(`${url}/functions/v1/okb-setup/owner`, {
      method: "POST", headers: { apikey: key, "Content-Type": "application/json" }, body: JSON.stringify({ code, name, email, password }),
    });
    made = await response.json().catch(() => ({ ok: false, problem: `the project answered HTTP ${response.status}` }));
  } catch (err) {
    throw new Error(`the project could not be reached: ${err?.cause?.code ?? err?.message ?? err}`);
  }
  if (!made?.ok) throw new Error(made?.problem ?? "the project refused the sign-in.");

  const session = await passwordSignIn(url, key, email, password);
  if (!session.ok) throw new Error(`your sign-in was made, but signing in with it failed: ${session.problem}`);
  if (accountEmail(session.body.user?.email) !== email) throw new Error(`Supabase signed in ${session.body.user?.email}, not ${email}. Nothing was saved.`);
  writeSession(ref, email, { projectRef: ref, url, publishableKey: key, email, refreshToken: session.body.refresh_token });
  writeActorFile(folder, { projectRef: ref, email });
  rmSync(codeFile, { force: true });
  // Real Agent's one-time codes that okb-setup could not send to Real Agent, for the business analyst's summary to give
  // the owner, readable by the owner alone. An empty list is saved too: every code reached Real Agent.
  if (Array.isArray(made.real_agent_codes)) {
    const file = join(folder, REAL_AGENT_CODE_FILE);
    writeFileSync(file, `${JSON.stringify(made.real_agent_codes)}\n`, { mode: 0o600 });
    try { chmodSync(file, 0o600); } catch {}
  }
  // Run by okb setup --owner, setup goes on in the same run, so the owner is not sent back yet.
  say(inSetup ? `Signed in as ${email}.` : `Signed in as ${email}. Go back to your business analyst and type: done`);
  return email;
}

/**
 * A person's first sign-in with the one-time invitation code their administrator gave them. It asks their email, unless
 * --email gives it, the code, and the password they choose, twice, and sends them to the okb-join hosted function, which
 * makes their Auth user. Then it signs in with that password and saves the session, and the folder's actor file with
 * `folder`, as the first sign-in does. The password goes only to the project.
 */
export async function joinSignIn({ url: knownUrl, key, email: given, folder }, ask, say) {
  const url = projectUrl(knownUrl);
  const ref = refFromUrl(url) ?? await ask("Project reference: ");
  if (!PROJECT_REF.test(ref)) throw new Error(`${ref} is not a project reference.`);
  say("Join your firm's Real Agent knowledge base with the invitation code your administrator gave you. Your password goes only to your firm's Supabase project.");
  const email = accountEmail(given ?? await ask("Your email: "));
  if (!email) throw new Error("that is not an email address. Nothing was changed.");
  if (given) say(`Joining as ${email}.`);
  const code = (await ask("Invitation code: ")).trim();
  if (!code) throw new Error("the invitation code is needed. Nothing was changed.");
  const password = await choosePassword(ask, say, ["Choose a password: ", "The password again: "]);

  let made;
  try {
    const response = await fetch(`${url}/functions/v1/okb-join`, {
      method: "POST", headers: { apikey: key, "Content-Type": "application/json" }, body: JSON.stringify({ email, code, password }),
    });
    made = await response.json().catch(() => ({ ok: false, problem: `the project answered HTTP ${response.status}` }));
    // Supabase's gateway, not okb-join, answers a wrong key or a missing function, with its own message and no problem.
    if (!made?.ok && !made?.problem && made?.message) made.problem = `the project answered HTTP ${response.status}: ${String(made.message).replace(/([^.])$/, "$1.")}${response.status === 401 ? ` Check that ${key} is this project's publishable key.` : ""} Your code was not used.`;
  } catch (err) {
    throw new Error(`the project could not be reached: ${err?.cause?.code ?? err?.message ?? err}`);
  }
  if (!made?.ok) throw new Error(made?.problem ?? "the project refused the invitation code.");

  const session = await passwordSignIn(url, key, email, password);
  if (!session.ok) throw new Error(`your sign-in was made, but signing in with it failed: ${session.problem}`);
  if (accountEmail(session.body.user?.email) !== email) throw new Error(`Supabase signed in ${session.body.user?.email}, not ${email}. Nothing was saved.`);
  const path = writeSession(ref, email, { projectRef: ref, url, publishableKey: key, email, refreshToken: session.body.refresh_token });
  say(`Signed in as ${email}. Session saved to ${path}.`);
  if (folder !== undefined) {
    const actor = writeActorFile(folder, { projectRef: ref, email });
    say(`Actor file saved to ${actor}. A session opened on ${folder} works as ${email}.`);
  }
  return path;
}
