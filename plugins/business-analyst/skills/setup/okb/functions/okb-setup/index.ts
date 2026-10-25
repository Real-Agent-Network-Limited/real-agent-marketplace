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
// admin API; an Auth user an earlier attempt made for the same email gets the new password instead. It invites each of
// Real Agent's staff real-agent.ts lists through Supabase Auth's invite, as okb-invite does, or reuses the Auth user
// Auth holds for the email. An invitation Supabase does not send stops nothing: that person is left out. It records
// each person in okb_setup.person, for first-administrator.sql, and each loose end in okb_setup.open_task, which
// first-administrator.sql saves as an open task for the owner: Real Agent not added, when the staff list is empty or an
// invitation was not sent, and the Developer invitation to DEVELOPER_EMAIL. It spends the code. Response: { ok: true,
// email, real_agent, open_tasks } or { ok: false, problem }. The password is never stored, logged or returned.
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

/** One of Real Agent's staff: the Auth user Auth holds for the email, or one Supabase invites, or why it was not sent. */
// deno-lint-ignore no-explicit-any
async function invited(db: any, email: string, name: string): Promise<{ id?: string; made?: boolean; problem?: string }> {
  const [found] = await db`select id from auth.users where lower(email) = lower(${email})`;
  if (found) return { id: found.id, made: false };
  const res = await fetch(`${PROJECT}/auth/v1/invite`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ email, data: { name } }),
  }).catch(() => null);
  const body = res ? await res.json().catch(() => ({})) : {};
  if (!res?.ok || typeof body?.id !== "string") return { problem: res ? authProblem(body ?? {}) : "Supabase Auth could not be reached." };
  return { id: body.id, made: true };
}

/** The open tasks setup leaves the owner, as first-administrator.sql saves them, titled as okb-invite finds them. */
export function openTasks(staff: { name: string; email: string }[], missed: { name: string; email: string; problem: string }[], developer: string | null) {
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
  for (const m of missed) tasks.push({
    title: `Add Real Agent (${m.email}) as a user`,
    description: `Supabase did not send Real Agent's invitation to ${m.email} during setup: ${m.problem} Once ${developer ?? "Real Agent"} has accepted the Developer invitation, ask your database admin: add Real Agent, ${m.email}.`,
    completion_requirements: `An actor named "${m.name} (Real Agent)" is in the knowledge base.`,
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
  const missed: { name: string; email: string; problem: string }[] = [];
  for (const one of STAFF) {
    const address = one.email.toLowerCase();
    const staff = await invited(db, address, `${one.name} (Real Agent)`);
    if (!staff.id) { missed.push({ name: one.name, email: address, problem: `${staff.problem}`.replace(/([^.])$/, "$1.") }); continue; }
    people.push({ auth_user_id: staff.id, name: one.name, email: address, role: "real_agent" });
  }
  const tasks = openTasks(STAFF, missed, DEVELOPER_EMAIL);
  // deno-lint-ignore no-explicit-any
  await db.begin(async (tx: any) => {
    await tx`delete from okb_setup.person`;
    for (const p of people) await tx`insert into okb_setup.person(auth_user_id, name, email, role) values (${p.auth_user_id}, ${p.name}, ${p.email}, ${p.role})`;
    await tx`delete from okb_setup.open_task`;
    for (const [i, t] of tasks.entries())
      await tx`insert into okb_setup.open_task(position, title, description, completion_requirements) values (${i + 1}, ${t.title}, ${t.description}, ${t.completion_requirements})`;
    await tx`delete from okb_setup.owner_code`;
  });
  return json(200, { ok: true, email, real_agent: people.filter(p => p.role === "real_agent").map(p => p.name), open_tasks: tasks.map(t => t.title) });
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
