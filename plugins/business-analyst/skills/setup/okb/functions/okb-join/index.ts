// okb-join: a person invited with okb-invite spends their one-time invitation code and chooses their own password. Deploy
// it with verify_jwt off, through the Supabase connector's deploy_edge_function: the person has no sign-in yet, so it
// checks each call itself. It is a function of its own, not a mode of okb-invite, because Supabase sets verify_jwt for a
// whole function, and okb-invite must keep it on; and not a mode of okb-setup, which runs approved setup files as
// postgres and has no business being called by every new member of staff. So the public surface is this one path.
//
// POST .../okb-join, JSON { email, code, password }, which the okb command's sign-in --join sends. It goes on only when
// okb_private.invitation holds an open invitation for the email whose SHA-256 is the code's, unexpired, unused, and with
// fewer than 5 wrong tries. A wrong code counts a try against the email's open invitation, and the fifth locks it. A
// wrong, expired, spent or locked code, and an email with no invitation, all get the same plain refusal, which does not
// say whether the email is known. With the right code, it makes the person's Auth user with the password they chose,
// confirmed, through Supabase Auth's own admin API with the service key only this function's environment holds; links
// it to the actor okb-invite made, with okb_private.provision_actor_sign_in, approved by the administrator who invited
// them, which OKB's audit log shows as the actor's change; makes their sessions scope, as bootstrap.sql's step 3e does;
// and marks the code used. One transaction: a failure keeps nothing in OKB, and the Auth user it made is taken off again.
//
// Response: { ok: true, name, email } or { ok: false, problem }. The password is never stored, logged or returned, and
// the answer holds no code, token or link.
import postgres from "npm:postgres@3.4.9";

const PROJECT = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// The wrong tries that lock a code, as okb_private.invitation's check allows.
const TRIES = 5;
// The one answer to every code that does not open an invitation.
export const NO_MATCH = "That email and invitation code do not match an open invitation. Check both, or ask your administrator for a new code.";

const db = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 1, prepare: false, idle_timeout: 1, onnotice: () => {}, connection: { application_name: "okb-join" } });

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const message = (err: unknown) => (err instanceof Error ? err.message : String(err));
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
/** The code as okb-invite hashed it: upper case, without spaces or hyphens. */
const codeKey = (code: string) => code.toUpperCase().replace(/[\s-]+/g, "");
const codeHash = async (code: string) =>
  Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(codeKey(code)))), b => b.toString(16).padStart(2, "0")).join("");

class Refused extends Error { constructor(public status: number, text: string) { super(text); } }

/** Supabase Auth's admin API, with the project's own service key. */
async function auth(method: string, path: string, body?: unknown): Promise<{ ok: boolean; body: Record<string, unknown> }> {
  const res = await fetch(`${PROJECT}/auth/v1/admin/${path}`, {
    method,
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  }).catch(() => null);
  const parsed = res ? await res.json().catch(() => ({})) : {};
  return { ok: Boolean(res?.ok), body: parsed && typeof parsed === "object" ? parsed : {} };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { ok: false, problem: "Call this function with POST." });
  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { ok: false, problem: "The request must be JSON." }); }
  const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
  const code = typeof body?.code === "string" ? codeKey(body.code) : "";
  const password = typeof body?.password === "string" ? body.password : "";
  if (!EMAIL.test(email)) return json(400, { ok: false, problem: `${email || "That"} is not an email address.` });
  if (!code) return json(400, { ok: false, problem: "Give the invitation code your administrator gave you." });
  if (password.length < 8 || password.length > 72) return json(400, { ok: false, problem: "Choose a password of 8 to 72 characters." });

  // The Auth user this call made, taken off again when OKB keeps nothing.
  let madeId: string | null = null;
  try {
    // deno-lint-ignore no-explicit-any
    const result = await db.begin(async (tx: any) => {
      const [open] = await tx`select i.invitation_id, i.actor_id, i.code_sha256, i.wrong_tries, i.invited_by_actor_id, i.expires_at > clock_timestamp() as live,
          a.display_name, a.enabled, a.auth_user_id
        from okb_private.invitation i join okb.actor a using (actor_id)
        where i.email = ${email} and i.used_at is null and i.replaced_at is null for update of i`;
      if (!open || open.wrong_tries >= TRIES || !open.live || !open.enabled || open.auth_user_id) return { refused: NO_MATCH };
      if (open.code_sha256 !== await codeHash(code)) {
        // Kept, though the call is refused: the transaction commits the try.
        await tx`update okb_private.invitation set wrong_tries = wrong_tries + 1 where invitation_id = ${open.invitation_id}`;
        return { refused: NO_MATCH };
      }
      // The administrator who invited them approves the link, or, when they are no longer one, an enabled administrator.
      const [approver] = await tx`select a.actor_id from okb.actor a where a.enabled and a.actor_kind = 'human' and a.authority_class = 'administrator'
        order by a.actor_id = ${open.invited_by_actor_id} desc, a.actor_id limit 1`;
      if (!approver) throw new Refused(409, "Your firm's Real Agent knowledge base has no administrator to approve your sign-in. Ask your administrator.");

      const made = await auth("POST", "users", { email, password, email_confirm: true, user_metadata: { name: open.display_name } });
      if (!made.ok || typeof made.body.id !== "string") {
        const said = String(made.body.msg ?? made.body.message ?? made.body.error_description ?? made.body.error ?? "Supabase Auth could not be reached.");
        throw new Refused(/registered|exists/i.test(said) ? 409 : 400, /registered|exists/i.test(said)
          ? `${email} already has a sign-in in your firm's project. Ask your administrator to add you again.`
          : `Supabase refused the password: ${said.replace(/([^.])$/, "$1.")} Choose another.`);
      }
      madeId = made.body.id;
      await tx`select okb_private.provision_actor_sign_in(${approver.actor_id}::uuid, ${open.actor_id}::uuid, ${madeId}::uuid)`;
      // Their sessions scope, as bootstrap.sql's step 3e makes it.
      const sessions = `sessions_${madeId!.replaceAll("-", "")}`;
      const [{ scope_id }] = await tx`insert into okb.scope(code, display_name, description, created_by)
        values (${sessions}, ${`${open.display_name}'s sessions`}, ${`The text of each session ${open.display_name} has had with their agent.`}, ${approver.actor_id}) returning scope_id`;
      await tx`select okb_private.provision_grant(${approver.actor_id}::uuid, gen_random_uuid(), ${open.actor_id}::uuid, ${scope_id}::uuid, array['evidence'], null::uuid,
        array['read','create','edit','delete'], null::timestamptz, 'Their agent keeps the text of each session with them here.')`;
      await tx`update okb_private.invitation set used_at = clock_timestamp() where invitation_id = ${open.invitation_id}`;
      return { ok: true, name: open.display_name, email };
    });
    if ("refused" in result) return json(403, { ok: false, problem: result.refused });
    return json(200, result);
  } catch (err) {
    if (madeId) await auth("DELETE", `users/${madeId}`);
    if (err instanceof Refused) return json(err.status, { ok: false, problem: err.message });
    console.error("okb-join failed:", message(err));
    return json(500, { ok: false, problem: `okb-join failed: ${message(err)}` });
  }
});
