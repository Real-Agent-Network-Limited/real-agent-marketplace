// okb-setup: builds OKB in the firm's project from the setup files on the owner's computer, and makes the owner's
// own sign-in, so neither the Supabase command-line tool nor a paste into the SQL Editor is needed. Deploy it with
// verify_jwt off, through the Supabase connector's deploy_edge_function, with real-agent.ts beside it: it checks
// each call itself.
//
// POST .../okb-setup/sql, the body one setup file's text. It runs a file only when the file's SHA-256 is in
// okb_setup.approved, which only the project's postgres login writes, such as the business analyst through the
// connector's execute_sql. Each approval runs once. The file runs as postgres, as the SQL Editor runs it: sent as one
// request, it is one implicit transaction, so a failure keeps nothing of it, and the approval stays for a second try.
// Response: { ok: true, name } or { ok: false, problem }.
//
// POST .../okb-setup/owner, JSON { code, name, email, password }: the owner's first sign-in, which the okb command's
// sign-in --owner sends. It goes on only when the code's SHA-256 is okb_setup.owner_code's, unexpired, and OKB has
// no actor yet. It makes the owner's Auth user with the password they chose, confirmed, through Supabase Auth's own
// admin API; an Auth user an earlier attempt made for the same email gets the new password instead. For each of Real
// Agent's staff real-agent.ts lists, it reuses the Auth user Auth holds for the email, or else makes a one-time
// invitation code, as okb-invite makes one: three groups of four from an alphabet with no look-alike letters or digits,
// valid for 7 days. It sends no email. It records each person with an Auth user in okb_setup.person, and each code's
// SHA-256 alone in okb_setup.staff_code, for first-administrator.sql, which makes the actors and the invitations okb-join
// spends. It records each loose end in okb_setup.open_task, which first-administrator.sql saves as an open task for the
// owner: the Developer invitation to DEVELOPER_EMAIL, "Send Real Agent its invitation code" for each code, and "Add
// Real Agent as a user" when the staff list is empty. It spends the sign-in code. Response: { ok: true, email,
// real_agent, real_agent_codes: [{ name, email, code, expires_at }], open_tasks } or { ok: false, problem }. Each code is
// in this answer once, and the sign-in saves it for the business analyst's summary. The password is never stored,
// logged or returned.
import postgres from "npm:postgres@3.4.9";
import { DEVELOPER_EMAIL, STAFF } from "./real-agent.ts";

const PROJECT = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DB_URL = Deno.env.get("SUPABASE_DB_URL")!;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const message = (err: unknown) => (err instanceof Error ? err.message : String(err));
const sha256 = async (bytes: Uint8Array) =>
  Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)), b => b.toString(16).padStart(2, "0")).join("");
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Supabase Auth's admin API, with the project's own service key, which only this function's environment holds. */
async function auth(method: string, path: string, body?: unknown): Promise<{ ok: boolean; body: Record<string, unknown> }> {
  const res = await fetch(`${PROJECT}/auth/v1/admin/${path}`, {
    method,
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const parsed = await res.json().catch(() => ({}));
  return { ok: res.ok, body: parsed && typeof parsed === "object" ? parsed : {} };
}
const authProblem = (body: Record<string, unknown>) => String(body.msg ?? body.message ?? body.error_description ?? body.error ?? "Supabase Auth refused it.");

// The code's letters and digits: no 0, 1, I, L, O or U, as okb-invite draws them.
const ALPHABET = "ABCDEFGHJKMNPQRSTVWXYZ23456789";
/** A new invitation code, such as K7QM-3XRD-W9PA, as okb-invite makes one. */
function newCode(): string {
  const out: string[] = [];
  while (out.length < 12) for (const b of crypto.getRandomValues(new Uint8Array(32))) if (b < 240 && out.length < 12) out.push(ALPHABET[b % 30]);
  return [0, 4, 8].map(i => out.slice(i, i + 4).join("")).join("-");
}
/** The code's SHA-256 as okb-join compares it: upper case, without spaces or hyphens. */
const codeHash = (code: string) => sha256(new TextEncoder().encode(code.toUpperCase().replace(/[\s-]+/g, "")));

/** The open tasks setup leaves the owner, as first-administrator.sql saves them, titled as okb-invite and the database admin find them. */
export function openTasks(staff: { name: string; email: string }[], coded: { name: string; email: string; expires_at: string }[], developer: string | null) {
  const tasks: { title: string; description: string; completion_requirements: string }[] = [];
  if (developer) tasks.push({
    title: `Invite ${developer} as a Developer in Supabase`,
    description: `In Supabase, open your organisation's Team page, choose Invite member, and invite ${developer} as a Developer, so Real Agent can apply updates. A Developer can change the database and read its keys, but not your billing, members or settings.`,
    completion_requirements: "The administrator says the invitation is sent.",
  });
  if (!staff.length) tasks.push({
    title: "Add Real Agent as a user",
    description: "Real Agent's staff are not in your knowledge base yet. Ask your database admin to add Real Agent once Real Agent gives you its email address.",
    completion_requirements: "An actor named \"<name> (Real Agent)\" is in the knowledge base.",
  });
  for (const c of coded) tasks.push({
    title: `Send Real Agent its invitation code (${c.email})`,
    description: `Setup made Real Agent's account, ${c.name} (Real Agent), with a one-time invitation code. Email the code to ${c.email}. It works once, until ${c.expires_at.slice(0, 10)}. If the code is lost or runs out, ask your database admin: add Real Agent, ${c.email}.`,
    completion_requirements: `${c.name} (Real Agent) has signed in with the code.`,
  });
  return tasks;
}

/** The Auth user for an email: made, or, when an earlier attempt made it, given this password. Returns its id. */
// deno-lint-ignore no-explicit-any
async function authUser(db: any, email: string, password: string, name: string): Promise<{ id?: string; made?: boolean; problem?: string }> {
  const [found] = await db`select id from auth.users where lower(email) = lower(${email})`;
  const ran = found
    ? await auth("PUT", `users/${found.id}`, { password, email_confirm: true, user_metadata: { name } })
    : await auth("POST", "users", { email, password, email_confirm: true, user_metadata: { name } });
  if (!ran.ok || typeof ran.body.id !== "string") return { problem: authProblem(ran.body) };
  return { id: ran.body.id, made: !found };
}

// deno-lint-ignore no-explicit-any
async function runFile(db: any, text: string): Promise<Response> {
  const hash = await sha256(new TextEncoder().encode(text));
  const [approved] = await db`delete from okb_setup.approved where sha256 = ${hash} returning name`;
  if (!approved) return json(403, { ok: false, problem: "This file is not approved for this project. Approve it first, as the setup skill says." });
  try {
    // No parameters, so the simple protocol: every statement in one request, as one implicit transaction.
    await db.unsafe(text).simple();
  } catch (err) {
    await db`insert into okb_setup.approved(sha256, name) values (${hash}, ${approved.name}) on conflict do nothing`;
    return json(422, { ok: false, name: approved.name, problem: message(err) });
  }
  return json(200, { ok: true, name: approved.name });
}

// deno-lint-ignore no-explicit-any
async function owner(db: any, body: Record<string, unknown>): Promise<Response> {
  const code = typeof body.code === "string" ? body.code : "";
  const name = typeof body.name === "string" ? body.name.trim() : "";
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (!code) return json(400, { ok: false, problem: "The sign-in code is missing." });
  if (!name || name.length > 200) return json(400, { ok: false, problem: "Give your name, as Real Agent should show it." });
  if (!EMAIL.test(email)) return json(400, { ok: false, problem: `${email || "That"} is not an email address.` });
  if (password.length < 8) return json(400, { ok: false, problem: "Choose a password of at least 8 characters." });

  const [held] = await db`select 1 from okb_setup.owner_code where sha256 = ${await sha256(new TextEncoder().encode(code))} and expires_at > now()`;
  if (!held) return json(403, { ok: false, problem: "This sign-in code is not this project's, or it has run out. Ask your business analyst for a new one." });
  const [{ actors }] = await db`select count(*)::int as actors from okb.actor`;
  if (actors > 0) return json(409, { ok: false, problem: "Your firm's first administrator is already made. Sign in with okb sign-in." });

  const you = await authUser(db, email, password, name);
  if (!you.id) return json(400, { ok: false, problem: `Supabase Auth refused your sign-in: ${you.problem}` });
  const people = [{ auth_user_id: you.id, name, email, role: "owner" }];
  const coded: { name: string; email: string; code: string; sha256: string; expires_at: string }[] = [];
  for (const one of STAFF) {
    const address = one.email.toLowerCase();
    const [found] = await db`select id from auth.users where lower(email) = ${address}`;
    if (found) { people.push({ auth_user_id: found.id, name: one.name, email: address, role: "real_agent" }); continue; }
    const code = newCode();
    coded.push({ name: one.name, email: address, code, sha256: await codeHash(code), expires_at: new Date(Date.now() + 7 * 86_400_000).toISOString() });
  }
  const tasks = openTasks(STAFF, coded, DEVELOPER_EMAIL);
  // deno-lint-ignore no-explicit-any
  await db.begin(async (tx: any) => {
    await tx`delete from okb_setup.person`;
    for (const p of people) await tx`insert into okb_setup.person(auth_user_id, name, email, role) values (${p.auth_user_id}, ${p.name}, ${p.email}, ${p.role})`;
    await tx`delete from okb_setup.staff_code`;
    for (const c of coded) await tx`insert into okb_setup.staff_code(email, name, code_sha256, expires_at) values (${c.email}, ${c.name}, ${c.sha256}, ${c.expires_at})`;
    await tx`delete from okb_setup.open_task`;
    for (const [i, t] of tasks.entries())
      await tx`insert into okb_setup.open_task(position, title, description, completion_requirements) values (${i + 1}, ${t.title}, ${t.description}, ${t.completion_requirements})`;
    await tx`delete from okb_setup.owner_code`;
  });
  return json(200, { ok: true, email, real_agent: [...people.filter(p => p.role === "real_agent").map(p => p.name), ...coded.map(c => c.name)],
    real_agent_codes: coded.map(c => ({ name: `${c.name} (Real Agent)`, email: c.email, code: c.code, expires_at: c.expires_at })), open_tasks: tasks.map(t => t.title) });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { ok: false, problem: "Call this function with POST." });
  const route = new URL(req.url).pathname.split("/").filter(Boolean).at(-1);
  if (route !== "sql" && route !== "owner") return json(404, { ok: false, problem: "Call okb-setup/sql or okb-setup/owner." });
  const db = postgres(DB_URL, { max: 1, prepare: false, idle_timeout: 1, onnotice: () => {}, connection: { application_name: "okb-setup" } });
  try {
    if (route === "sql") return await runFile(db, await req.text());
    let body: Record<string, unknown>;
    try { body = await req.json(); } catch { return json(400, { ok: false, problem: "The request must be JSON." }); }
    return await owner(db, body ?? {});
  } catch (err) {
    return json(500, { ok: false, problem: message(err) });
  } finally {
    await db.end({ timeout: 1 });
  }
});
