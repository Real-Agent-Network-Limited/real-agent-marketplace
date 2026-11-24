// password-reset: a reset code for a person who has lost their password, for a signed-in administrator. The setup
// command deploys it through the Management API with verify_jwt on, with the others, and it stays deployed.
//
// POST .../password-reset, with the caller's own sign-in, JSON { email }.
// It confirms who the caller is with Supabase Auth, then asks OKB, as the caller, with okb_get_actor: only a person
// whose actor is an administrator goes on. Where OKB's second factor setting is administrators, an administrator's
// sign-in without an authenticator's code is turned away, as OKB itself turns it away. Nothing the caller sends says
// who they are.
//
// The person is the enabled person whose sign-in has the email, ignoring case. A person invited who has not joined
// yet has no sign-in, and gets a new invitation code with invite_person instead. Real Agent's own staff are refused:
// a code would let the firm's administrator sign in as Real Agent, so they reset through Real Agent support. The code comes from Supabase Auth's
// admin generateLink, type recovery, with the service role. It sends nothing: the function takes the answer's
// email_otp and leaves its link. The code is in this answer once, for the administrator to pass on, and nowhere else.
// The person gives it, their email and a new password under "Reset your password" on Real Agent's sign-in page,
// which checks it with Supabase Auth. It lasts as long as Supabase Auth's email code lasts, an hour unless the
// project's Email OTP Expiration says otherwise. A new code replaces the one before.
//
// It saves an access record in the Administration scope as the caller, naming the administrator, the person and the
// time, never the code, before it asks for the code. One transaction: a failure keeps nothing in OKB.
//
// Response: { ok: true, name, email, code, sign_in_page, access_record_id } or { ok: false, problem }. sign_in_page is
// the firm's page on Real Agent's connector, from the short name setup keeps, or null when setup kept none. The
// answer never holds a password, a token or a link that signs anyone in.
import postgres from "npm:postgres@3.4.9";
import { createClient } from "npm:@supabase/supabase-js@2.119.0";

const PROJECT = Deno.env.get("SUPABASE_URL")!;
// The connector's address, under which each firm's sign-in page is /<slug>/sign-in/.
const CONNECTOR = "https://mcp.realagent.network";
const EMAIL = /^[^\s@]{1,200}@[^\s@]{1,200}\.[^\s@]{1,50}$/;
// Supabase Auth's email code is 6 to 10 digits long, as the project's Email OTP Length says.
const CODE = /^[0-9]{6,10}$/;

const db = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 1, prepare: false, idle_timeout: 1, onnotice: () => {}, connection: { application_name: "password-reset" } });

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
class Refused extends Error { constructor(public status: number, text: string) { super(text); } }

/** Supabase Auth's check of a sign-in, and its recovery code. The tests point both at a stand-in by SUPABASE_URL. */
export const seam = {
  user: async (token: string, key: string): Promise<string | null> => {
    const res = await fetch(`${PROJECT}/auth/v1/user`, { headers: { Authorization: `Bearer ${token}`, apikey: key } }).catch(() => null);
    const user = res?.ok ? await res.json().catch(() => null) : null;
    return typeof user?.id === "string" ? user.id : null;
  },
  code: async (email: string): Promise<string> => {
    const admin = createClient(PROJECT, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error } = await admin.auth.admin.generateLink({ type: "recovery", email });
    const code = data?.properties?.email_otp;
    if (error || typeof code !== "string" || !CODE.test(code)) {
      // The error's code alone is logged, never the answer, which holds the code and a link.
      console.error("password-reset: generateLink gave no code:", error?.code ?? error?.status ?? (typeof code === "string" ? `length ${code.length}` : "none"));
      throw new Refused(502, "Supabase Auth gave no reset code. Try again in a minute.");
    }
    return code;
  },
};

/** The level of a sign-in Supabase Auth has confirmed, from its token's aal claim: aal2 once the sign-in gave a code
 * from an authenticator app, aal1 otherwise. */
function levelOf(token: string): string {
  try { return JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).aal === "aal2" ? "aal2" : "aal1"; }
  catch { return "aal1"; }
}

/** Runs what follows as the caller, as PostgREST does for a signed-in request: their claims, then the authenticated role. */
// deno-lint-ignore no-explicit-any
async function asCaller(tx: any, caller: { id: string; aal: string }) {
  await tx`select set_config('request.jwt.claims', ${JSON.stringify({ sub: caller.id, role: "authenticated", aal: caller.aal })}, true)`;
  await tx`set local role authenticated`;
}
// deno-lint-ignore no-explicit-any
async function asPostgres(tx: any) {
  await tx`reset role`;
  await tx`select set_config('request.jwt.claims', '', true)`;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { ok: false, problem: "Call this function with POST." });
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const key = req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const id = token ? await seam.user(token, key) : null;
  if (!id) return json(401, { ok: false, problem: "Call this function with your own sign-in." });
  const caller = { id, aal: levelOf(token) };
  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { ok: false, problem: "The request must be JSON." }); }
  const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
  if (!EMAIL.test(email)) return json(400, { ok: false, problem: "Give the email the person signs in with, as email." });

  try {
    // deno-lint-ignore no-explicit-any
    const result = await db.begin(async (tx: any) => {
      // Who the caller is, as OKB itself answers it for their sign-in.
      await asCaller(tx, caller);
      // deno-lint-ignore no-explicit-any
      let me: any = null;
      // A savepoint, so OKB's refusal leaves the transaction open for the reason below.
      // deno-lint-ignore no-explicit-any
      try { me = await tx.savepoint(async (sp: any) => (await sp`select okb.okb_get_actor() as me`)[0].me); } catch { /* answered below */ }
      await asPostgres(tx);
      if (!me) {
        const [{ missing }] = await tx`select okb_private.second_factor_missing(${caller.id}::uuid, ${caller.aal}) as missing`;
        throw new Refused(403, missing
          ? "Your firm asks administrators for a second factor. Sign in with your authenticator's code first, with okb sign-in --second-factor in your folder."
          : "Your sign-in has no actor in your firm's Real Agent knowledge base, so it gives no reset code.");
      }
      const [mine] = await tx`select enabled from okb.actor where actor_id = ${me.actor_id}`;
      if (me.actor_kind !== "human" || me.authority_class !== "administrator" || !mine?.enabled)
        throw new Refused(403, "Only an administrator of your firm's Real Agent knowledge base gives a reset code.");

      // The person, by the email their sign-in holds.
      const [person] = await tx`select x.actor_id, x.display_name, x.enabled, u.email from auth.users u join okb.actor x on x.auth_user_id = u.id
        where lower(btrim(u.email)) = ${email} and x.actor_kind = 'human' order by x.enabled desc, x.actor_id limit 1`;
      if (!person) {
        const [invited] = await tx`select x.display_name from okb_private.invitation i join okb.actor x using (actor_id)
          where i.email = ${email} and i.used_at is null and i.replaced_at is null`;
        throw new Refused(404, invited
          ? `${invited.display_name} has not joined yet, so they have no password to reset. Give them a new invitation code with invite_person.`
          : `Nobody in your firm's Real Agent knowledge base signs in with ${email}.`);
      }
      // Real Agent's own staff: an actor named as setup names them, one with a grant of the real_agent template, or one setup
      // made from okb_setup.person, which a firm set up by hand lacks.
      const [{ named, granted }] = await tx`select x.display_name like '% (Real Agent)' as named,
        exists(select 1 from okb.authorisation z where z.executor_actor_id = x.actor_id and z.reason = 'The real_agent access template.') as granted
        from okb.actor x where x.actor_id = ${person.actor_id}`;
      const [{ people }] = await tx`select to_regclass('okb_setup.person') is not null as people`;
      const [listed] = people ? await tx`select 1 from okb_setup.person p join okb.actor x on x.auth_user_id = p.auth_user_id
        where x.actor_id = ${person.actor_id} and p.role = 'real_agent'` : [];
      if (named || granted || listed) throw new Refused(403, `${person.display_name} is one of Real Agent's staff. Real Agent's staff reset their password through Real Agent support, support@realagent.network.`);
      if (!person.enabled) throw new Refused(409, `${person.display_name} is in OKB but disabled. Enable them first, as bootstrap.sql's step 5 says.`);
      // The firm's short name, which build.mjs approve keeps in okb_setup.firm, for a firm set up with one.
      const [{ kept }] = await tx`select to_regclass('okb_setup.firm') is not null as kept`;
      const [firm] = kept ? await tx`select to_jsonb(f) as row from okb_setup.firm f` : [];
      const slug = typeof firm?.row?.slug === "string" && firm.row.slug ? firm.row.slug : null;

      // The access record, as the caller, before the code is made.
      await asCaller(tx, caller);
      const at = new Date().toISOString();
      const summary = `${me.display_name} asked for a password reset code for ${person.display_name} (${email}) at ${at.slice(0, 16).replace("T", " ")} UTC,`
        + ` to pass on to them. ${person.display_name} sets a new password with it under "Reset your password" on Real Agent's sign-in page. The code is not kept.`;
      const [{ saved }] = await tx`select okb.okb_add_record('administration', 'evidence', ${`Password reset code for ${person.display_name}`},
        ${`Records that ${me.display_name} asked for a password reset code for ${person.display_name}.`},
        ${JSON.stringify({ summary, source_reference: "The password-reset hosted function", source_date: at.slice(0, 10),
          standing: "observed", limitations: "Written by password-reset as the code was made." })}::text::jsonb) as saved`;
      if (saved?.refused === true) throw new Refused(403, String(saved.problem));

      const code = await seam.code(person.email);
      return {
        ok: true, name: person.display_name, email, code,
        sign_in_page: slug ? `${CONNECTOR}/${slug}/sign-in/` : null, access_record_id: saved.record_id,
      };
    });
    return json(200, result);
  } catch (err) {
    if (err instanceof Refused) return json(err.status, { ok: false, problem: err.message });
    // The error's code alone is logged: a database error's text can hold a statement's values.
    console.error("password-reset failed:", (err as { code?: string })?.code ?? (err as Error)?.name ?? "unknown");
    return json(500, { ok: false, problem: "No reset code was made. Try again in a minute." });
  }
});
