// okb's client for Supabase's Management API, https://api.supabase.com, shared by okb connector-settings and
// okb setup --owner. Each call follows the API's own description, https://api.supabase.com/api/v1-json.
//
// The client holds a personal access token the owner pastes at a hidden prompt, for one run only. The token goes
// in the Authorization header and nowhere else: a refusal's message has it taken out, even when Supabase's answer
// echoes the request, and the client prints nothing.
//
// OKB_TEST_MANAGEMENT_API names a stand-in for the Management API, for the plugin's tests. It is used only when it
// is a loopback http address, such as http://127.0.0.1:<port>, and ignored otherwise. A command that uses it says
// so before any prompt.
import process, { stdin, stdout } from "node:process";

export const API = "https://api.supabase.com";
const LOOPBACK = /^http:\/\/(?:127\.0\.0\.1|localhost|\[::1\]):\d{1,5}$/;
/** The services a project needs before setup can build in it: the database, the Data API, sign-in and files. */
const SERVICES = "auth,db,rest,storage";
/** The most projects one page holds, as the v1-json allows. */
const PAGE = 100;

/** The Management API's address: the real one, or a loopback stand-in named by OKB_TEST_MANAGEMENT_API. */
export function apiBase(env = process.env) {
  const given = env.OKB_TEST_MANAGEMENT_API;
  return given && LOOPBACK.test(given) ? given : API;
}

/** A refused or failed call, with Supabase's own message. */
export class Refused extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

/** Supabase's own message from an answer's body. */
function message(text, status) {
  try {
    const body = JSON.parse(text);
    const said = body?.message ?? body?.error_description ?? body?.error ?? body?.msg;
    if (said) return typeof said === "string" ? said : JSON.stringify(said);
  } catch { /* not JSON */ }
  return text.trim() || `HTTP ${status}`;
}

/** text with every copy of secret taken out. */
const without = (text, secret) => secret ? text.split(secret).join("[token]") : text;
/** The longest refusal message kept, so an answer that echoes a whole request stays one readable line. */
const MESSAGE_MAX = 500;
/** A message cut to MESSAGE_MAX characters, after the token is taken out, so a cut never leaves part of it. */
const capped = text => text.length > MESSAGE_MAX ? `${text.slice(0, MESSAGE_MAX - 1)}…` : text;

/**
 * A client for the Management API with token. call(method, path, body, { allow404 }) calls path, such as
 * /v1/organizations, and returns the answer's JSON, or null for a 404 when allowed. A FormData body goes as
 * multipart, any other body as JSON. A refusal throws Refused with Supabase's message, the token taken out.
 */
export function managementClient(token, base = apiBase()) {
  return {
    async call(method, path, body, { allow404 = false } = {}) {
      const form = body instanceof FormData;
      const res = await fetch(`${base}${path}`, {
        method,
        headers: { authorization: `Bearer ${token}`, accept: "application/json", ...(body && !form ? { "content-type": "application/json" } : {}) },
        ...(body ? { body: form ? body : JSON.stringify(body) } : {}),
      });
      const text = await res.text();
      if (res.status === 404 && allow404) return null;
      if (!res.ok) throw new Refused(res.status, capped(without(message(text, res.status), token)));
      if (!text) return {};
      try { return JSON.parse(text); }
      catch { throw new Refused(res.status, "Supabase's answer was not JSON."); }
    },
  };
}

/** The organisations the token reaches: [{ slug, name }]. GET /v1/organizations. */
export async function organizations(c) {
  return (await c.call("GET", "/v1/organizations")).map(o => ({ slug: o.slug, name: o.name }));
}

/** One organisation with its plan: free, pro, team, enterprise or platform. GET /v1/organizations/{slug}. */
export async function organization(c, slug) {
  const o = await c.call("GET", `/v1/organizations/${encodeURIComponent(slug)}`);
  return { slug, name: o.name, plan: o.plan };
}

/** Every project in the organisation, page by page: [{ ref, name, status }]. GET /v1/organizations/{slug}/projects. */
export async function projects(c, orgSlug) {
  const all = [];
  for (let offset = 0; ; ) {
    const { projects: page = [], pagination } = await c.call("GET", `/v1/organizations/${encodeURIComponent(orgSlug)}/projects?offset=${offset}&limit=${PAGE}`);
    all.push(...page.map(p => ({ ref: p.ref, name: p.name, status: p.status })));
    offset += page.length;
    if (!page.length || offset >= (pagination?.count ?? 0)) return all;
  }
}

/** A project reference: 20 lower-case letters and digits. */
export const PROJECT_REF = /^[a-z0-9]{20}$/;

/**
 * Creates a project, and returns { ref }, or { ref: null } when Supabase's answer holds no project reference, in ref
 * or, as older answers have it, in id. POST /v1/projects. dbPass goes in the body alone, and is taken out of a
 * refusal's message, as the token is.
 */
export async function createProject(c, { orgSlug, name, region, dbPass }) {
  let made;
  try { made = await c.call("POST", "/v1/projects", { name, organization_slug: orgSlug, db_pass: dbPass, region_selection: { type: "specific", code: region } }); }
  catch (err) {
    if (err instanceof Refused && dbPass) throw new Refused(err.status, err.message.split(dbPass).join("[password]"));
    throw err;
  }
  const ref = made?.ref ?? made?.id;
  return { ref: typeof ref === "string" && PROJECT_REF.test(ref) ? ref : null };
}

/** Whether every service the project needs answers healthy. GET /v1/projects/{ref}/health. */
async function healthy(c, ref) {
  const services = await c.call("GET", `/v1/projects/${encodeURIComponent(ref)}/health?services=${encodeURIComponent(SERVICES)}`);
  return Array.isArray(services) && services.length > 0 && services.every(s => s.healthy === true);
}

/** Answers that no later poll can change: a bad request, a refused token, a project the token cannot see. */
const FINAL = [400, 401, 403, 404, 422];

/**
 * Polls the project's health every everyMs until it is healthy, and returns true, or false once timeoutMs has
 * passed. A poll Supabase turns down while the project comes up counts as not healthy yet, and so does a poll that
 * cannot reach Supabase at all, such as a network blip. It stops at once with Supabase's message on 400 or 422, a
 * refused token, 401 or 403, and a project the token cannot see, 404.
 */
export async function waitHealthy(c, ref, { timeoutMs = 600000, everyMs = 10000, now = Date.now, sleep = ms => new Promise(r => setTimeout(r, ms)) } = {}) {
  const until = now() + timeoutMs;
  for (;;) {
    try { if (await healthy(c, ref)) return true; }
    catch (err) {
      // fetch throws a TypeError when the request never got an answer.
      const unreached = err instanceof TypeError;
      if (!unreached && (!(err instanceof Refused) || FINAL.includes(err.status))) throw err;
    }
    if (now() >= until) return false;
    await sleep(everyMs);
  }
}

/** Runs sql in the project's database, and returns its rows. POST /v1/projects/{ref}/database/query. */
export async function query(c, ref, sql) {
  const rows = await c.call("POST", `/v1/projects/${encodeURIComponent(ref)}/database/query`, { query: sql });
  return Array.isArray(rows) ? rows : [];
}

/**
 * Deploys a hosted function from its files, creating it when it does not exist. POST /v1/projects/{ref}/functions/deploy,
 * multipart: one "file" part per file, under its name, and a "metadata" part with entrypoint_path, name and verify_jwt.
 */
export async function deployFunction(c, ref, { name, entrypoint, verifyJwt, files }) {
  const form = new FormData();
  form.append("metadata", JSON.stringify({ entrypoint_path: entrypoint, name, verify_jwt: verifyJwt }));
  for (const f of files) form.append("file", new Blob([f.text], { type: "application/typescript" }), f.name);
  await c.call("POST", `/v1/projects/${encodeURIComponent(ref)}/functions/deploy?slug=${encodeURIComponent(name)}`, form);
}

/** Deletes a hosted function. DELETE /v1/projects/{ref}/functions/{function_slug}. A function already gone is not an error. */
export async function deleteFunction(c, ref, slug) {
  await c.call("DELETE", `/v1/projects/${encodeURIComponent(ref)}/functions/${encodeURIComponent(slug)}`, undefined, { allow404: true });
}

/** The project's hosted functions: [{ slug, verify_jwt }]. GET /v1/projects/{ref}/functions. */
export async function functionsList(c, ref) {
  return (await c.call("GET", `/v1/projects/${encodeURIComponent(ref)}/functions`)).map(f => ({ slug: f.slug, verify_jwt: f.verify_jwt }));
}

/** The project's publishable key. GET /v1/projects/{ref}/api-keys, never asking Supabase to reveal a secret key. */
export async function publishableKey(c, ref) {
  const key = (await c.call("GET", `/v1/projects/${encodeURIComponent(ref)}/api-keys`)).find(k => k.type === "publishable" && k.api_key);
  if (!key) throw new Refused(404, "Supabase shows no publishable key for this project.");
  return key.api_key;
}

/** The Data API serves okb, beside public and graphql_public, and reloads its schema. PATCH /v1/projects/{ref}/postgrest. */
export async function exposeOkb(c, ref) {
  await c.call("PATCH", `/v1/projects/${encodeURIComponent(ref)}/postgrest`, { db_schema: "public, graphql_public, okb" });
  await query(c, ref, "notify pgrst, 'reload schema'");
}

/** One hidden line from the terminal, never echoed, as the sign-in asks for a password. */
export function askHidden(prompt) {
  if (!stdin.isTTY || typeof stdin.setRawMode !== "function") return Promise.reject(new Error("This command needs an interactive terminal."));
  stdin.setEncoding("utf-8");
  stdin.setRawMode(true);
  stdout.write(prompt);
  return new Promise((resolve, reject) => {
    let value = "";
    const finish = (error, answer) => {
      stdin.off("data", take);
      stdin.off("end", closed);
      stdin.setRawMode(false);
      stdin.pause();
      error ? reject(error) : resolve(answer);
    };
    // A terminal that brackets a paste sends ESC[200~ before it and ESC[201~ after it. They are dropped.
    const MARKS = ["\u001b[200~", "\u001b[201~"];
    const take = chunk => {
      for (const char of chunk) {
        if (char === "\r" || char === "\n") { stdout.write("\n"); return finish(null, value.trim()); }
        if (char === "\u0003") { stdout.write("\n"); return finish(new Error("cancelled.")); }
        // Ctrl-D ends the answer as Enter does, once something was typed.
        if (char === "\u0004") {
          if (!value) continue;
          stdout.write("\n");
          return finish(null, value.trim());
        }
        if (char === "\u007f" || char === "\b") value = value.slice(0, -1);
        else {
          value += char;
          const mark = MARKS.find(m => value.endsWith(m));
          if (mark) value = value.slice(0, -mark.length);
        }
      }
    };
    const closed = () => finish(new Error("input closed."));
    stdin.on("data", take);
    stdin.on("end", closed);
    stdin.resume();
  });
}
