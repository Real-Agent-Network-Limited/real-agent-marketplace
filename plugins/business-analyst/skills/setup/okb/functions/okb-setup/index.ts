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
// admin API; an Auth user an earlier attempt made for the same email gets the new password instead. It makes an Auth
// user for each of Real Agent's staff real-agent.ts lists, with a long random password nobody is told. It records
// each in okb_setup.person, for first-administrator.sql, and spends the code. Response: { ok: true, email,
// real_agent } or { ok: false, problem }. The password is never stored, logged or returned.
import postgres from "npm:postgres@3.4.9";
import { STAFF } from "./real-agent.ts";

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

/** A password nobody is told: 32 random bytes as hex. */
const unknownPassword = () => Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, "0")).join("");

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
  const made = you.made ? [you.id] : [];
  for (const one of STAFF) {
    const staff = await authUser(db, one.email.toLowerCase(), unknownPassword(), one.name);
    if (!staff.id) {
      for (const id of made) await auth("DELETE", `users/${id}`);
      return json(400, { ok: false, problem: `Supabase Auth refused Real Agent's sign-in for ${one.email}: ${staff.problem}` });
    }
    if (staff.made) made.push(staff.id);
    people.push({ auth_user_id: staff.id, name: one.name, email: one.email.toLowerCase(), role: "real_agent" });
  }
  // deno-lint-ignore no-explicit-any
  await db.begin(async (tx: any) => {
    await tx`delete from okb_setup.person`;
    for (const p of people) await tx`insert into okb_setup.person(auth_user_id, name, email, role) values (${p.auth_user_id}, ${p.name}, ${p.email}, ${p.role})`;
    await tx`delete from okb_setup.owner_code`;
  });
  return json(200, { ok: true, email, real_agent: STAFF.map(s => s.name) });
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
