// okb setup --owner: sets Real Agent up for a firm in one run, on the owner's computer, through Supabase's
// Management API, with a personal access token the owner pastes at a hidden prompt. It does each step the firm
// analyst once did with the Supabase connector, in the order of the setup design's "How it works":
//
//   the token, checked with GET /v1/organizations; the organisation; the project, found or created in London, and
//   healthy; where the project stands, read with state.sql; okb-setup deployed, the setup files approved and run;
//   file search's functions and schedule; the Data API serving okb; the owner's own sign-in; the firm's short
//   name, its slug, kept with Real Agent's connector; the administrator, the health check, the scopes and file search
//   checked as the owner, the setup record and the open task saved, okb_setup dropped, setup ended in the folder;
//   then the five settings of Real Agent's connector, public sign-up off among them, and the summary.
//
// The token, the owner's password and the database password the command makes stay in this process's memory. None
// goes on a command line, into an environment variable, a file or a log, and none is printed.
//
// The setup folder keeps the firm's name, its slug and the project's reference in .okb-setup-business.json,
// readable by the owner alone, so a run after a stop carries on with the same project and slug, and never proposes
// a new one. state.sql says where the project stands. A project picked from the list is read with it before the file
// is written, and one that already holds a knowledge base is never written there.
//
// Exit codes: 0 everything done, 1 a step failed or was refused, 2 bad options, 3 run again later, for the signing
// key's second run.
//
// OKB_TEST_MANAGEMENT_API and OKB_TEST_REAL_AGENT_SITE name loopback stand-ins for Supabase and Real Agent's connector, for
// the stand-in's tests. Each is used only when it is a loopback http address, and the run says so before any prompt.
// With the Management API's stand-in, the project's own address is the stand-in's too, and OKB_TEST_HEALTH_WAIT_MS
// may shorten the wait for a healthy project.
import process, { stdin, stdout } from "node:process";
import { randomBytes } from "node:crypto";
import { chmodSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  API, apiBase, askHidden as terminalHidden, createProject, deployFunction, exposeOkb, functionsList, managementClient,
  organization, organizations, PROJECT_REF, projects, publishableKey, query, Refused, waitHealthy,
} from "./management.mjs";
import { AGAIN, makeSettings, TOKEN_OPTIONS, TOKEN_PAGE } from "./connector-settings.mjs";
import { ownerSignIn } from "../mcp/lib/sign-in-flow.mjs";
import { createTools } from "../mcp/lib/tools.mjs";
import { readActor } from "../mcp/lib/actor-file.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
/** The setup skill's files, beside the okb plugin in Real Agent's marketplace. */
export const SETUP_FOLDER = resolve(HERE, "../../business-analyst/skills/setup/okb");

/** The file in the setup folder that keeps the firm's name, slug and project between runs. */
export const BUSINESS_FILE = ".okb-setup-business.json";
/** Where a new project is made: London. */
export const REGION = "eu-west-2";
/** Real Agent's connector, which keeps each firm's slug at /api/slug and serves each client at /<slug>. */
export const CONNECTOR = "https://mcp.realagent.network";
export const SITE = CONNECTOR;
const LOOPBACK = /^http:\/\/(?:127\.0\.0\.1|localhost|\[::1\]):\d{1,5}$/;
/** A slug: lower-case words and numbers joined by hyphens, 2 to 40 characters. */
export const SLUG = /^(?=.{2,40}$)[a-z0-9]+(-[a-z0-9]+)*$/;
/** The first path segments the connector serves itself, which no business can take as its slug. */
export const RESERVED = ["api"];
/** The highest number a slug is tried with, after the slug itself: <slug>-2 up to <slug>-9. */
const LAST_TRY = 9;
const SCOPES = ["general", "routines", "reference", "plugins"];
const TASK_TITLE = "Connect Real Agent's connector";

/**
 * Real Agent's connector's address: the real one, or a loopback stand-in named by OKB_TEST_REAL_AGENT_SITE, which counts only
 * when the Management API is a stand-in too, so a real run never sends a firm's slug anywhere but Real Agent.
 */
export function siteBase(base = apiBase(), env = process.env) {
  if (base === API) return SITE;
  const given = env.OKB_TEST_REAL_AGENT_SITE;
  return given && LOOPBACK.test(given) ? given : SITE;
}

/** text cut to at most max characters, at a hyphen when there is one. */
function cutAt(text, max) {
  if (text.length <= max) return text;
  const at = text.slice(0, max + 1).lastIndexOf("-");
  return (at > 0 ? text.slice(0, at) : text.slice(0, max)).replace(/-+$/, "");
}

/**
 * The slug proposed for a firm's name: its Latin letters and digits, lower case, accents taken off, every run of
 * anything else one hyphen, cut at a hyphen to 40 characters at most. Empty when fewer than 2 characters are left.
 */
export function slugFor(name) {
  const words = String(name ?? "").normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  const slug = cutAt(words, 40);
  return SLUG.test(slug) ? slug : "";
}

/** The n-th slug tried: the slug itself, then <slug>-2 up to <slug>-9, each within 40 characters. */
export const slugTry = (slug, n) => n === 1 ? slug : `${cutAt(slug, 38)}-${n}`;

export const OWNER_SETUP_USAGE = `Usage: node okb.mjs setup --owner --folder <folder>

setup --owner sets Real Agent up for your firm in one run. It asks for a Supabase access token, which you make
at ${TOKEN_PAGE}. ${TOKEN_OPTIONS} You delete it on that page once setup is done. It then asks your firm's name, finds or creates your Supabase project in London, builds your
Real Agent knowledge base in it, asks your name, email and the password you choose, and makes the five settings of
Real Agent's connector. Run it again after a stop, and it carries on from where it stopped.`;

/** --folder, checked. */
function options(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] !== "--folder") throw new Error(`${argv[i]} is not an option of setup --owner.`);
    if (argv[i + 1] === undefined) throw new Error("--folder needs a value.");
    out.folder = argv[++i];
  }
  if (!out.folder) throw new Error("setup --owner needs --folder.");
  let folder = false;
  try { folder = statSync(out.folder).isDirectory(); } catch { folder = false; }
  if (!folder) throw new Error(`${out.folder}, given as --folder, is not a folder.`);
  return { folder: resolve(out.folder) };
}

// Typed past the end of a visible answer, kept for the next question. What is typed past a hidden answer is dropped,
// so nothing typed after a password is ever shown.
let ahead = "";
// A terminal that brackets a paste sends ESC[200~ before it and ESC[201~ after it. They are dropped.
const MARKS = ["\u001b[200~", "\u001b[201~"];
/**
 * One line from the terminal. A hidden one is never echoed. Text kept from before the prompt is taken without being
 * echoed. Ctrl-C stops the run.
 */
export function askLine(prompt, hidden = false) {
  if (!stdin.isTTY || typeof stdin.setRawMode !== "function") return Promise.reject(new Error("This command needs an interactive terminal."));
  stdin.setEncoding("utf-8");
  stdin.setRawMode(true);
  stdout.write(prompt);
  return new Promise((done, fail) => {
    let value = "";
    const finish = (error, answer) => {
      stdin.off("data", take);
      stdin.off("end", closed);
      stdin.setRawMode(false);
      stdin.pause();
      error ? fail(error) : done(answer);
    };
    const take = chunk => {
      const replayed = ahead.length;
      const text = ahead + chunk;
      ahead = "";
      for (let i = 0; i < text.length; i++) {
        const char = text[i];
        const echo = !hidden && i >= replayed;
        if (char === "\r" || char === "\n") {
          ahead = hidden ? "" : text.slice(text[i + 1] === "\n" && char === "\r" ? i + 2 : i + 1);
          stdout.write("\n");
          return finish(null, value.trim());
        }
        if (char === "\u0003") { stdout.write("\n"); return finish(new Error("cancelled.")); }
        if (char === "\u007f" || char === "\b") {
          if (value && echo) stdout.write("\b \b");
          value = value.slice(0, -1);
        } else {
          value += char;
          const mark = MARKS.find(m => value.endsWith(m));
          if (mark) value = value.slice(0, -mark.length);
          else if (echo && char !== "\u001b" && !/^\u001b\[?[0-9]*~?$/.test(value.slice(value.lastIndexOf("\u001b")))) stdout.write(char);
        }
      }
    };
    const closed = () => finish(new Error("input closed."));
    stdin.on("data", take);
    stdin.on("end", closed);
    stdin.resume();
    if (ahead) take("");
  });
}

/**
 * The firm file in the folder, or null. A file whose project reference is not 20 lower-case letters and digits,
 * or whose slug is not a slug, counts as no file, so an edited file never steers a call elsewhere.
 */
export function readBusiness(folder) {
  try {
    const kept = JSON.parse(readFileSync(join(folder, BUSINESS_FILE), "utf8"));
    if (!kept || typeof kept.name !== "string" || !kept.name.trim() || typeof kept.ref !== "string" || !PROJECT_REF.test(kept.ref)) return null;
    if (kept.slug !== undefined && kept.slug !== null && (typeof kept.slug !== "string" || !SLUG.test(kept.slug))) return null;
    if (kept.organization !== undefined && typeof kept.organization !== "string") return null;
    return { ...kept, project: typeof kept.project === "string" ? kept.project : kept.name, held: kept.held === true };
  } catch { return null; }
}

function writeBusiness(folder, business) {
  const file = join(folder, BUSINESS_FILE);
  writeFileSync(file, `${JSON.stringify(business, null, 2)}\n`, { mode: 0o600 });
  try { chmodSync(file, 0o600); } catch {}
}

/** text as an SQL string literal. */
const literal = text => `'${String(text).replaceAll("'", "''")}'`;

/** A step that stopped the run, with the line the owner reads. */
class Stop extends Error {}

/** Supabase's own message for a failed call, as one line. */
const said = err => (err instanceof Error ? err.message : String(err)).replace(/\s+/g, " ").trim().replace(/([^.!?…])$/, "$1.");

/** Real Agent's support address, from real-agent.ts, or null. */
function supportEmail(setup) {
  try { return /^export const SUPPORT_EMAIL: string \| null = "([^"]+)";$/m.exec(readFileSync(join(setup, "functions", "okb-setup", "real-agent.ts"), "utf8"))?.[1] ?? null; }
  catch { return null; }
}

/** Real Agent's connector keeps slug for the project. Returns "held", "taken", or throws Stop. */
async function claimSlug(site, { projectUrl, slug, key }) {
  if (RESERVED.includes(slug)) return "taken";
  let res;
  try {
    res = await fetch(`${site}/api/slug`, { method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ project_url: projectUrl, slug, publishable_key: key }) });
  } catch (err) {
    throw new Stop(`Keeping your short name with Real Agent: failed. Real Agent's connector could not be reached: ${err?.cause?.code ?? err?.message ?? err}. Run this command again later.`);
  }
  await res.arrayBuffer().catch(() => null);
  if (res.status === 204) return "held";
  if (res.status === 409) return "taken";
  throw new Stop(`Keeping your short name with Real Agent: failed. Real Agent's connector answered HTTP ${res.status}. Run this command again later.`);
}

/**
 * Sets Real Agent up for the firm in the folder. `ask(prompt, hidden)` answers each question, `askHidden(prompt)` the
 * token's, and `say` prints a line. `endFolder(folder)` ends setup in the folder once it has finished there. Returns
 * the exit code.
 */
export async function ownerSetup(argv, {
  ask = askLine, askHidden = terminalHidden, say = line => stdout.write(`${line}\n`), base = apiBase(), site,
  setup = SETUP_FOLDER, endFolder = () => {}, env = process.env,
} = {}) {
  site = base === API ? SITE : site ?? siteBase(base, env);
  let o;
  try { o = options(argv); }
  catch (err) { say(`${err.message}\n${OWNER_SETUP_USAGE}`); return 2; }
  const folder = o.folder;
  let build;
  try { build = await import(pathToFileURL(join(setup, "build.mjs")).href); }
  catch { say(`The setup files are not beside the okb plugin, at ${setup}. Run this command from Real Agent's marketplace.`); return 1; }
  const support = supportEmail(setup);
  const stand = base !== API;
  // Each stand-in is said before any prompt, so a token is never pasted for one unseen.
  if (stand) say(`This run talks to a test stand-in at ${base}, not to Supabase. Paste no real token.`);
  if (site !== SITE) say(`This run talks to a test stand-in at ${site}, not to Real Agent's connector.`);
  const projectUrl = ref => stand ? base : `https://${ref}.supabase.co`;
  const waitMs = stand && Number(env.OKB_TEST_HEALTH_WAIT_MS) > 0 ? Number(env.OKB_TEST_HEALTH_WAIT_MS) : 600000;

  say(`Make a Supabase access token at ${TOKEN_PAGE}. ${TOKEN_OPTIONS} Paste it here, and delete it on that page once setup is done.`);
  let token;
  try { token = await askHidden("Supabase access token: "); }
  catch (err) { say(`Stopped: ${said(err)}`); return 1; }
  if (!token) { say("No token was pasted. Run this again, and paste the token at the prompt."); return 1; }
  const c = managementClient(token, base);
  token = undefined;

  let doing = "Checking your token";
  // The projects waited for in this run, so a project picked from the list is not waited for twice.
  const ready = new Set();
  try {
    let orgs;
    try { orgs = await organizations(c); }
    catch (err) {
      if (err instanceof Refused && (err.status === 401 || err.status === 403))
        throw new Stop(`Supabase refused the token: ${said(err)} Make a new one at ${TOKEN_PAGE}, and run this again.`);
      throw err;
    }

    // The firm, its organisation and its project: from the firm file after a stop, or asked.
    let business = readBusiness(folder);
    if (business) say(`Carrying on with setup for ${business.name}, in your Supabase project ${business.project}.`);
    else {
      let name = "";
      while (!name) {
        name = (await ask("Your firm's name: ")).trim();
        if (name && !build.FIRM.test(name)) { say("That name is too long. Type it in 200 characters or fewer."); name = ""; }
      }
      let slug = slugFor(name);
      while (!slug) {
        say("Real Agent's address for your firm uses Latin letters and numbers, and your firm's name has none.");
        slug = slugFor(await ask("A short name for your firm, in Latin letters or numbers: "));
      }
      if (!orgs.length) throw new Stop("Your Supabase account has no organisation. Make one at https://supabase.com/dashboard, and run this again.");
      let org = orgs[0];
      if (orgs.length > 1) {
        say(orgs.map((x, i) => `${i + 1}. ${x.name}`).join("\n"));
        org = null;
        while (!org) org = orgs[Number(await ask(`Which of your Supabase organisations is for ${name}? Type its number: `)) - 1] ?? null;
      }
      doing = "Finding your project";
      const plan = (await organization(c, org.slug)).plan;
      const found = await projects(c, org.slug);
      let chosen = null;
      // A project picked from the list is read with state.sql before anything is saved. One that is set up, or holds
      // records or files, is another knowledge base: the owner is told so and asked again, so the firm file only
      // ever names a new project or an unfinished attempt with nothing in it.
      while (found.length && !chosen) {
        say([...found.map((p, i) => `${i + 1}. ${p.name}`), `${found.length + 1}. A new project`].join("\n"));
        let pick = 0;
        while (!(pick >= 1 && pick <= found.length + 1)) pick = Number(await ask("Which project is for Real Agent? Type its number: "));
        if (pick === found.length + 1) break;
        const picked = found[pick - 1];
        doing = "Waiting for your project to be ready";
        await waitReady(picked.ref);
        doing = "Reading where your project stands";
        const [was] = await query(c, picked.ref, readFileSync(join(setup, "state.sql"), "utf8"));
        if (was.setup_finished || was.records || was.files) say(`${picked.name} already holds a knowledge base. Choose another project, or a new one.`);
        else chosen = picked;
        doing = "Finding your project";
      }
      if (!chosen) {
        if (plan !== "free") {
          say(plan ? `${org.name} is on Supabase's ${plan} plan, so Supabase charges for a new project there.`
            : "This organisation's plan is not Free, so Supabase charges for a project.");
          const yes = (await ask(`Type yes to create the project ${name} in London: `)).trim().toLowerCase();
          if (yes !== "yes") throw new Stop("Nothing was created.");
        }
        doing = "Creating your project in London";
        // The database password is made here, sent once with the project, and kept nowhere.
        const made = await createProject(c, { orgSlug: org.slug, name, region: REGION, dbPass: randomBytes(24).toString("base64url") });
        if (!made.ref) throw new Stop(`Supabase made the project ${name}, but its answer did not say which project it is. Run this command again, and choose ${name} from the list.`);
        chosen = { ref: made.ref, name };
        say("Creating your project in London: done.");
      }
      business = { name, slug, held: false, ref: chosen.ref, project: chosen.name, organization: org.slug };
      writeBusiness(folder, business);
    }
    const { ref } = business;
    const url = projectUrl(ref);

    doing = "Waiting for your project to be ready";
    if (!ready.has(ref)) await waitReady(ref);
    // Declared here, in the run's order of stages, and called for a project picked from the list too.
    async function waitReady(project) {
      say("Waiting for your project to be ready. This can take a few minutes.");
      if (!await waitHealthy(c, project, { timeoutMs: waitMs, everyMs: Math.min(10000, Math.max(100, waitMs / 5)) })) {
        const minutes = Math.max(1, Math.round(waitMs / 60000));
        throw new Stop(`Your project was not ready within ${minutes} minute${minutes === 1 ? "" : "s"}. Run this command again later, and it carries on from here.`);
      }
      ready.add(project);
      say("Waiting for your project to be ready: done.");
    }

    doing = "Reading where your project stands";
    const read = name => readFileSync(join(setup, name), "utf8");
    const [state] = await query(c, ref, read("state.sql"));
    let reset = false;
    if (state.okb_built && !state.setup_finished) {
      if (state.records || state.files)
        throw new Stop(`${business.project} already holds Real Agent records from an earlier setup, so setup stopped. Real Agent needs to look at it${support ? `. Please email ${support}` : ""}.`);
      const yes = (await ask(`An earlier setup in ${business.project} stopped part way. Type yes to clear it and set up Real Agent again: `)).trim().toLowerCase();
      if (yes !== "yes") throw new Stop("Nothing was changed.");
      reset = true;
    }
    const key = await publishableKey(c, ref);
    let email = readActor(folder)?.ok ? readActor(folder).value.auth_email : null;

    if (!state.setup_finished) {
      // The slug, kept with Real Agent's connector before approve: the saved one after a stop, or the first free try.
      doing = "Keeping your short name with Real Agent";
      const tries = business.held ? [business.slug] : Array.from({ length: LAST_TRY }, (_, i) => slugTry(business.slug, i + 1));
      let held = null;
      for (const slug of tries) if (await claimSlug(site, { projectUrl: url, slug, key }) === "held") { held = slug; break; }
      if (!held) throw new Stop(business.held
        ? `Real Agent's connector says your short name, ${business.slug}, is no longer yours. Please email ${support ?? "Real Agent"}.`
        : `Real Agent's connector says ${business.slug} and each number after it up to ${slugTry(business.slug, LAST_TRY)} are taken. Please email ${support ?? "Real Agent"}.`);
      business = { ...business, slug: held, held: true };
      writeBusiness(folder, business);
      say(`Keeping your short name, ${held}, with Real Agent: done.`);

      doing = "Building your Real Agent knowledge base";
      const all = build.functions(setup);
      const deploy = async f => deployFunction(c, ref, { name: f.name, entrypoint: f.entrypoint_path, verifyJwt: f.verify_jwt,
        files: f.files.map(x => ({ name: x.name, text: readFileSync(x.path, "utf8") })) });
      await deploy(all[0]);
      await query(c, ref, build.approve({ ref, folder, firm: business.name, slug: held, reset }, { here: setup }).sql);
      const runFiles = async names => {
        for (const name of names) {
          const ran = await build.runFile(url, key, name, build.fileText(name, ref, setup));
          if (!ran.ok) throw new Stop(`${doing}: failed. ${name}: ${said(ran.problem)}`);
        }
      };
      await runFiles([...(reset ? ["reset.sql"] : []), "setup.sql", "file-search.sql", "file-search-scopes.sql"]);
      say("Building your Real Agent knowledge base: done.");

      doing = "Setting up file search";
      for (const f of all.slice(1)) await deploy(f);
      await runFiles(["schedule.sql"]);
      say("Setting up file search: done.");

      doing = "Turning on the Data API";
      await exposeOkb(c, ref);
      // The same setting as the role's, which health.sql reads, as data-api.sql gives it.
      await query(c, ref, read("data-api.sql"));
      say("Turning on the Data API: done.");

      // The owner's own sign-in. The project reference is asked only when the address hides it, as a stand-in's does.
      doing = "Your sign-in";
      try {
        email = await ownerSignIn({ url, key, folder, inSetup: true }, (prompt, hidden) => prompt === "Project reference: " ? ref : ask(prompt, hidden), say);
      } catch (err) { throw new Stop(`Your sign-in stopped: ${said(err)} Run this command again to carry on.`); }

      doing = "Making you the administrator";
      await runFiles(["first-administrator.sql"]);
      say("Making you the administrator: done.");
    } else if (!state.runner_ready) {
      say(`Real Agent is already set up in ${business.project}.`);
    }

    if (!email) throw new Stop(`${folder} is not signed in. Run node okb.mjs sign-in --folder "${folder}", then run this command again.`);
    const plan = business.organization ? (await organization(c, business.organization)).plan : null;
    let codes = [];
    if (state.runner_ready || !state.setup_finished) {
      // The checks as the owner, the setup record and the open task, Real Agent's codes, and okb_setup dropped.
      doing = "Checking everything works";
      const [health] = await query(c, ref, read("health.sql"));
      if (health?.ok !== true) throw new Stop(`${doing}: failed. The health check found: ${Object.entries(health ?? {}).filter(([k, v]) => k !== "ok" && v === false).map(([k]) => k).join(", ") || "nothing"}.`);
      const deployed = await functionsList(c, ref);
      const wrong = build.FUNCTIONS.filter(f => !deployed.some(d => d.slug === f.name && d.verify_jwt === f.verify_jwt)).map(f => f.name);
      if (wrong.length) throw new Stop(`${doing}: failed. These hosted functions are missing or have the wrong JWT setting: ${wrong.join(", ")}.`);
      const tools = createTools({ ref, email, agentFolder: folder, defaultSchema: "okb" });
      const call = async (name, args) => JSON.parse((await tools.callTool(name, args)).content[0].text);
      const rpc = (fn, args = {}) => call("rpc", { function: fn, schema: "okb", args });
      const scopes = await rpc("okb_get_scopes");
      const listed = scopes.result?.items ?? scopes.result ?? [];
      const codesSeen = Array.isArray(listed) ? listed.map(x => x.code) : [];
      const missing = SCOPES.filter(s => !codesSeen.includes(s));
      if (scopes.ok === false || missing.length) throw new Stop(`${doing}: failed. ${scopes.problem ?? `Your knowledge base does not list ${missing.join(", ")}.`}`);
      const search = await call("call_function", { name: "file-search", body: { query: "setup check" } });
      if (!Array.isArray(search.result?.hits ?? search.hits)) throw new Stop(`${doing}: failed. File search answered: ${search.problem ?? JSON.stringify(search).slice(0, 200)}`);
      say("Checking everything works: done.");

      doing = "Saving the setup record";
      const [kept] = await query(c, ref, `select
        exists(select 1 from okb.record_version v join okb.record r using (record_id) join okb.scope s on s.scope_id = r.scope_id where s.code = 'administration' and v.title = 'Real Agent setup') as record,
        exists(select 1 from okb.record_version v join okb.record r using (record_id) join okb.scope s on s.scope_id = r.scope_id where s.code = 'administration' and v.title = ${literal(TASK_TITLE)}) as task`);
      const today = new Date().toISOString().slice(0, 10);
      if (!kept.record) {
        const saved = await rpc("okb_add_record", { p_scope: "administration", p_kind: "evidence", p_title: "Real Agent setup",
          p_reason: "The setup command's record of who set the project up, and how.",
          p_fields: { summary: `${email} set Real Agent up for ${business.name}, whose short name is ${business.slug}. OKB and file search were built, the hosted functions deployed and the Data API set, and the health check passed.`,
            source_reference: "okb setup --owner", source_date: today, standing: "observed", limitations: "Written down by the setup command." } });
        if (!saved.record_id && !saved.result?.record_id) throw new Stop(`${doing}: failed. ${saved.problem ?? JSON.stringify(saved).slice(0, 200)}`);
      }
      if (!kept.task) {
        // The owner as okb_setup.person names them, as first-administrator.sql finds them: no typed text goes in the SQL.
        const [me] = await query(c, ref, "select a.actor_id from okb_setup.person p join okb.actor a using (auth_user_id) where p.role = 'owner'");
        const due = new Date(Date.now() + 7 * 86_400_000).toISOString().replace(/\.\d{3}Z$/, "Z").replace(/:\d{2}Z$/, ":00Z");
        const saved = await rpc("okb_add_record", { p_scope: "administration", p_kind: "activity", p_title: TASK_TITLE,
          p_reason: "An open task setup left for the administrator.",
          p_fields: { activity_kind: "task", description: "Add Real Agent's connector to Claude, once Real Agent confirms your business.",
            completion_requirements: "The owner's home card shows in Claude.", assignee_actor_id: me?.actor_id, baseline_finish_at: due } });
        if (!saved.record_id && !saved.result?.record_id) throw new Stop(`${doing}: failed. ${saved.problem ?? JSON.stringify(saved).slice(0, 200)}`);
      }
      await query(c, ref, "drop schema if exists okb_setup cascade;");
      say("Saving the setup record: done.");
    }
    // Setup ends in the folder, as endFolder ends it: okb setup runs okb sync there. Run again after a stop, this is done
    // again, which changes nothing.
    doing = "Ending setup in your folder";
    await endFolder(folder);

    // The five settings of Real Agent's connector, with the slug.
    doing = "Real Agent's connector's settings";
    if (!business.held || typeof business.slug !== "string" || !SLUG.test(business.slug)) throw new Stop(`${folder} holds no short name for ${business.name}. Once Real Agent gives you its address, run node okb.mjs connector-settings.`);
    const settings = await makeSettings({ ref, slug: business.slug }, null, base, c);
    for (const line of settings.lines) say(line);
    if (settings.code !== 0) return settings.code === AGAIN ? AGAIN : 1;

    // The summary. Real Agent's codes the connector did not take are read here, and their file deleted only once they are
    // shown, so a run that stops before this point keeps them for the next.
    try { codes = build.realAgentCodes(folder, { keep: true }); } catch { codes = []; }
    say(`Real Agent is set up in ${business.project}, and you are its administrator.`);
    for (const line of codes) say(`Real Agent's connector did not take its invitation code. Please email it to ${support ?? "Real Agent"}, so Real Agent can sign in: ${line}.`);
    if (plan === "free") say("Your Supabase plan is Free, which pauses a project nobody uses for a week. A paid plan keeps it running.");
    say("One step is left. Once Real Agent confirms your firm, the Owner of your Claude organisation adds Real Agent's connector at this address:");
    say(`${CONNECTOR}/${business.slug}`);
    say("When you connect it in Claude, sign in with the email and password you chose in this setup, not your Claude or Supabase login.");
    // The session the owner ran this from started before their sign-in, so its okb plugin cannot see it: a new one can.
    say(`Start a new Code session on ${folder}, and type done there.`);
    rmSync(join(folder, build.REAL_AGENT_CODE_FILE), { force: true });
    return 0;
  } catch (err) {
    if (err instanceof Stop) say(err.message);
    else if (err instanceof Refused && err.status === 404 && doing === "Waiting for your project to be ready")
      say("Supabase shows this token no such project. Make the token in the account that holds your project, and run this again.");
    else if (err instanceof Refused && (err.status === 401 || err.status === 403)) say(`Supabase refused the token: ${said(err)} Make a new one at ${TOKEN_PAGE}, and run this again.`);
    else if (err instanceof Refused) say(`${doing}: failed. Supabase said: ${said(err)} Every step before it stays done. Run this command again to carry on.`);
    else if (err instanceof Error && err.message === "cancelled.") say("Stopped. Run this command again to carry on.");
    else say(`${doing}: failed. ${said(err)} Run this command again to carry on.`);
    return 1;
  }
}

