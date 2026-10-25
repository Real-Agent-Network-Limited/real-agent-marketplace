// okb-invite: adds one person to the firm's OKB in one call, for a signed-in administrator. Deploy it with
// verify_jwt on, through the Supabase connector's deploy_edge_function. It stays deployed: setup deploys it with the others.
//
// POST .../okb-invite, with the caller's own sign-in, JSON { name, email, template } or { name, email, workflow, role }.
// It confirms who the caller is with Supabase Auth, then asks OKB, as the caller, with okb_get_actor: only a person
// whose actor is an administrator goes on. Nothing the caller sends says who they are.
//
// For an email Supabase Auth already holds, it makes the person's actor on that Auth user, with their sessions scope,
// as bootstrap.sql's steps 3b and 3e do, and no code is needed. Otherwise it makes no Auth user and sends no email: it
// makes the person's actor with no sign-in yet, with okb_private.provision_invited_actor, and a one-time invitation
// code for the email, kept in okb_private.invitation as its SHA-256 alone. The code is three groups of four from an
// alphabet with no look-alike letters or digits, about 59 bits, valid for 7 days, spent once, and locked after 5 wrong
// tries. Inviting the email again replaces an unused code. The person spends it with okb-join, which makes their Auth
// user with the password they choose and their sessions scope. The actor is "<name> (Real Agent)" for the real_agent
// template. It gives the template's grants, or for a workflow role the basic template's, the role's grants from the
// newest release of the workflow's access.json in its plugins_<workflow> scope, and read of that scope for a role
// plugin_readers names, each approved by the caller. A person already in OKB keeps their actor and gets only the grants
// they lack. It saves the access record in the Administration scope as the caller. With the real_agent template, it
// completes the open "Add Real Agent" tasks setup left in Administration, with the access record linked as the evidence
// that supports each. One transaction: a failure keeps nothing in OKB.
//
// Response: { ok: true, name, email, actor_id, sign_in: "code" | "existing", code and code_expires_at for "code",
// template | workflow and role, grants, access_record_id, completed_tasks } or { ok: false, problem }. The code is in
// this answer once, and nowhere else; it never holds a password, a token or a link.
import postgres from "npm:postgres@3.4.9";

const PROJECT = Deno.env.get("SUPABASE_URL")!;
// How long a code lasts. okb-join counts its wrong tries.
const CODE_DAYS = 7;
// The code's letters and digits: no 0, 1, I, L, O or U, so none is mistaken for another when read aloud or typed.
const ALPHABET = "ABCDEFGHJKMNPQRSTVWXYZ23456789";
// The open task setup saves when Real Agent is not added yet, as functions/okb-setup/index.ts titles it.
const ADD_REAL_AGENT = "Add Real Agent";

const db = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 1, prepare: false, idle_timeout: 1, onnotice: () => {}, connection: { application_name: "okb-invite" } });

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const message = (err: unknown) => (err instanceof Error ? err.message : String(err));
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const ACTIONS = ["read", "create", "edit", "start", "hold", "complete", "reopen", "cancel", "decide", "delete"];

type Grant = { scope: string; record_kinds: string[]; actions: string[]; own_records: boolean };
class Refused extends Error { constructor(public status: number, text: string) { super(text); } }

/** The signed-in caller and their token, as Supabase Auth itself confirms, or null. */
async function signedIn(req: Request): Promise<{ id: string; token: string; key: string } | null> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const key = req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!token) return null;
  const res = await fetch(`${PROJECT}/auth/v1/user`, { headers: { Authorization: `Bearer ${token}`, apikey: key } }).catch(() => null);
  const user = res?.ok ? await res.json().catch(() => null) : null;
  return typeof user?.id === "string" ? { id: user.id, token, key } : null;
}

/** Runs fn as the caller, as PostgREST does for a signed-in request: their claims, then the authenticated role. */
// deno-lint-ignore no-explicit-any
async function asCaller(tx: any, id: string) {
  await tx`select set_config('request.jwt.claims', ${JSON.stringify({ sub: id, role: "authenticated" })}, true)`;
  await tx`set local role authenticated`;
}
// deno-lint-ignore no-explicit-any
async function asPostgres(tx: any) {
  await tx`reset role`;
  await tx`select set_config('request.jwt.claims', '', true)`;
}
/** OKB answers a refusal it logs as { refused: true, problem }: raised here, so the transaction keeps nothing. */
// deno-lint-ignore no-explicit-any
const answered = (r: any) => { if (r?.refused === true) throw new Refused(403, String(r.problem)); return r; };

/** The grants of an access template, from OKB. */
// deno-lint-ignore no-explicit-any
async function templateGrants(tx: any, code: string): Promise<{ authority_class: string; grants: Grant[] }> {
  const [t] = await tx`select authority_class, grants from okb.access_template where code = ${code}`;
  if (!t) {
    const codes = (await tx`select code from okb.access_template order by code`).map((r: { code: string }) => r.code);
    throw new Refused(400, `There is no access template ${code}. OKB holds ${codes.join(", ")}.`);
  }
  return { authority_class: t.authority_class, grants: t.grants };
}

/** A workflow role's grants, from the newest release of the workflow's access.json that the caller may read. */
// deno-lint-ignore no-explicit-any
async function roleGrants(tx: any, caller: { id: string; token: string; key: string }, workflow: string, role: string): Promise<Grant[]> {
  const bucket = `plugins_${workflow.replaceAll("-", "_")}`;
  await asCaller(tx, caller.id);
  const releases = (await tx`select name from storage.objects where bucket_id = ${bucket} and name ~ '^[^/]+/MANIFEST$' order by name desc`)
    .map((r: { name: string }) => r.name.split("/")[0]);
  await asPostgres(tx);
  // deno-lint-ignore no-explicit-any
  let file: any = null;
  for (const release of releases) {
    const res = await fetch(`${PROJECT}/storage/v1/object/authenticated/${bucket}/${release}/plugins/${workflow}/access.json`,
      { headers: { Authorization: `Bearer ${caller.token}`, apikey: caller.key } }).catch(() => null);
    if (!res?.ok) continue;
    file = await res.json().catch(() => null);
    if (file) break;
  }
  if (!file) throw new Refused(400, `The ${workflow} workflow has no release in its scope, ${bucket}, so its roles are not known yet. Ask Real Agent to publish it.`);
  const given = file.roles?.[role];
  if (!given || !Array.isArray(given.grants)) throw new Refused(400, `The ${workflow} workflow has no role ${role}. Its roles are ${Object.keys(file.roles ?? {}).join(", ")}.`);
  const grants: Grant[] = [...given.grants];
  if (Array.isArray(file.plugin_readers) && file.plugin_readers.includes(role))
    grants.push({ scope: bucket, record_kinds: ["evidence"], actions: ["read"], own_records: false });
  for (const g of grants) {
    if (typeof g?.scope !== "string" || !Array.isArray(g.record_kinds) || !Array.isArray(g.actions) || typeof g.own_records !== "boolean")
      throw new Refused(400, `The ${workflow} workflow's access.json has a grant OKB cannot read: ${JSON.stringify(g)}.`);
    const [s] = await tx`select 1 from okb.scope where code = ${g.scope} and enabled`;
    if (!s) throw new Refused(400, `The ${workflow} workflow's scope ${g.scope} is not in OKB yet. Add it first, as the add-staff skill's section 2 says.`);
  }
  return grants;
}

/** A new invitation code, such as K7QM-3XRD-W9PA: 12 characters, each from 30, drawn without bias. */
function newCode(): string {
  const out: string[] = [];
  while (out.length < 12) {
    for (const b of crypto.getRandomValues(new Uint8Array(32))) {
      // 240 is the largest multiple of 30 below 256, so every character is equally likely.
      if (b < 240 && out.length < 12) out.push(ALPHABET[b % 30]);
    }
  }
  return [0, 4, 8].map(i => out.slice(i, i + 4).join("")).join("-");
}
/** The code as okb-join compares it: upper case, without spaces or hyphens. */
const codeKey = (code: string) => code.toUpperCase().replace(/[\s-]+/g, "");
const codeHash = async (code: string) =>
  Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(codeKey(code)))), b => b.toString(16).padStart(2, "0")).join("");

const plain = (g: Grant, scopes: Map<string, string>) =>
  `${scopes.get(g.scope) ?? g.scope}: ${g.actions.join(", ")}${g.own_records ? ", on their own records" : ""}`;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { ok: false, problem: "Call this function with POST." });
  const caller = await signedIn(req);
  if (!caller) return json(401, { ok: false, problem: "Call this function with your own sign-in." });
  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { ok: false, problem: "The request must be JSON." }); }
  const name = typeof body?.name === "string" ? body.name.trim() : "";
  const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
  const template = typeof body?.template === "string" ? body.template.trim().toLowerCase() : "";
  const workflow = typeof body?.workflow === "string" ? body.workflow.trim().toLowerCase() : "";
  const role = typeof body?.role === "string" ? body.role.trim().toLowerCase() : "";
  // deno-lint-ignore no-control-regex
  if (!name || name.length > 200 || /[\u0000-\u001f]/.test(name)) return json(400, { ok: false, problem: "Give the person's name, as Real Agent should show it, as name." });
  if (!EMAIL.test(email)) return json(400, { ok: false, problem: `${email || "That"} is not an email address.` });
  if (Boolean(template) === Boolean(workflow || role) || (!template && !(workflow && role)))
    return json(400, { ok: false, problem: "Give either an access template, as template, or a workflow and one of its roles, as workflow and role." });
  if (workflow && !/^[a-z0-9][a-z0-9-]{0,62}$/.test(workflow)) return json(400, { ok: false, problem: `${workflow} is not a workflow plugin's name.` });

  try {
    // deno-lint-ignore no-explicit-any
    const result = await db.begin(async (tx: any) => {
      // Who the caller is, as OKB itself answers it for their sign-in.
      await asCaller(tx, caller.id);
      // deno-lint-ignore no-explicit-any
      let me: any;
      try { [{ me }] = await tx`select okb.okb_get_actor() as me`; }
      catch { throw new Refused(403, "Your sign-in has no actor in your firm's Real Agent knowledge base, so it invites nobody."); }
      await asPostgres(tx);
      const [mine] = await tx`select enabled from okb.actor where actor_id = ${me.actor_id}`;
      if (me.actor_kind !== "human" || me.authority_class !== "administrator" || !mine?.enabled)
        throw new Refused(403, "Only an administrator of your firm's Real Agent knowledge base invites a person.");

      const basic = await templateGrants(tx, template || "basic");
      const grants: Grant[] = [...basic.grants];
      if (!template) grants.push(...await roleGrants(tx, caller, workflow, role));
      const realAgent = template === "real_agent";
      const display = realAgent && !/\(Real Agent\)$/.test(name) ? `${name} (Real Agent)` : name;
      const authority = template ? basic.authority_class : "restricted";

      // The person: on the Auth user Supabase Auth holds for the email, or on the open invitation for it, or new.
      const [found] = await tx`select id from auth.users where lower(email) = ${email}`;
      const [pending] = found ? [] : await tx`select actor_id from okb_private.invitation where email = ${email} and used_at is null and replaced_at is null for update`;
      let [actor] = found
        ? await tx`select actor_id, display_name, enabled from okb.actor where auth_user_id = ${found.id}`
        : pending ? await tx`select actor_id, display_name, enabled from okb.actor where actor_id = ${pending.actor_id}` : [];
      if (actor && !actor.enabled) throw new Refused(409, `${actor.display_name} is in OKB but disabled. Enable them first, as bootstrap.sql's step 5 says.`);
      if (!actor && found) {
        const [{ id }] = await tx`select okb_private.provision_actor(${me.actor_id}::uuid, ${found.id}::uuid, ${display}, 'human', null, ${authority}, false) as id`;
        actor = { actor_id: id, display_name: display };
      } else if (!actor) {
        const [{ id }] = await tx`select okb_private.provision_invited_actor(${me.actor_id}::uuid, ${display}, ${authority}) as id`;
        actor = { actor_id: id, display_name: display };
      }
      // Their sessions scope, as bootstrap.sql's step 3e makes it, once they have a sign-in; okb-join makes it otherwise.
      if (found) {
        const sessions = `sessions_${found.id.replaceAll("-", "")}`;
        const [had] = await tx`select scope_id from okb.scope where code = ${sessions}`;
        if (!had) {
          const [{ scope_id }] = await tx`insert into okb.scope(code, display_name, description, created_by)
            values (${sessions}, ${`${actor.display_name}'s sessions`}, ${`The text of each session ${actor.display_name} has had with their agent.`}, ${me.actor_id}) returning scope_id`;
          await tx`select okb_private.provision_grant(${me.actor_id}::uuid, gen_random_uuid(), ${actor.actor_id}::uuid, ${scope_id}::uuid, array['evidence'], null::uuid,
            array['read','create','edit','delete'], null::timestamptz, 'Their agent keeps the text of each session with them here.')`;
        }
      }
      // A one-time code for a person with no sign-in yet, replacing any unused one for the email.
      let code: string | null = null, expires: string | null = null;
      if (!found) {
        code = newCode();
        await tx`update okb_private.invitation set replaced_at = clock_timestamp() where email = ${email} and used_at is null and replaced_at is null`;
        const [row] = await tx`insert into okb_private.invitation(actor_id, email, code_sha256, invited_by_actor_id, expires_at)
          values (${actor.actor_id}, ${email}, ${await codeHash(code)}, ${me.actor_id}, clock_timestamp() + ${`${CODE_DAYS} days`}::interval) returning expires_at`;
        expires = new Date(row.expires_at).toISOString();
      }

      // Each grant the person lacks, approved by the caller. A grant is held when a live one on the whole scope has each
      // of its kinds and actions, limited to own records only where this one is, as apply_access_template reads it.
      const reason = template ? `The ${template} access template.` : `The ${role} role in the ${workflow} workflow, from its access.json.`;
      const given: Grant[] = [];
      for (const g of grants) {
        const kinds = g.record_kinds, acts = ACTIONS.filter(a => g.actions.includes(a));
        const [held] = await tx`select 1 from okb.authorisation z join okb.scope s using (scope_id) where z.executor_actor_id = ${actor.actor_id} and s.code = ${g.scope}
          and z.record_id is null and z.mode = 'standing_permission' and z.record_kinds @> ${kinds}::text[] and z.allowed_actions @> ${acts}::text[]
          and (${g.own_records} or not z.own_records) and okb_private.authority_live(z.authorisation_id)`;
        if (held) continue;
        await tx`select okb_private.provision_grant(${me.actor_id}::uuid, gen_random_uuid(), ${actor.actor_id}::uuid, (select scope_id from okb.scope where code = ${g.scope}),
          ${kinds}::text[], null::uuid, ${acts}::text[], null::timestamptz, ${reason}, ${g.own_records})`;
        given.push({ ...g, actions: acts });
      }
      const scopes = new Map<string, string>((await tx`select code, display_name from okb.scope`).map((s: { code: string; display_name: string }) => [s.code, s.display_name]));
      const open = realAgent
        ? (await tx`select distinct on (v.record_id) v.record_id, v.title, v.payload->>'state' as state from okb.record_version v join okb.record r using (record_id)
            join okb.scope s on s.scope_id = r.scope_id where s.code = 'administration' and r.kind = 'activity' and r.deleted_at is null
            order by v.record_id, v.change_no desc`)
            .filter((t: { title: string; state: string }) => t.title.startsWith(ADD_REAL_AGENT) && !["completed", "cancelled"].includes(t.state)
              && (t.title === `${ADD_REAL_AGENT} as a user` || t.title.toLowerCase().includes(email)))
        : [];

      // The access record, and the tasks it closes, as the caller.
      await asCaller(tx, caller.id);
      const what = template ? `the ${template} access template` : `the ${role} role in the ${workflow} workflow`;
      const summary = `${me.display_name} ${found ? "added" : "invited"} ${actor.display_name} (${email}) and gave them ${what}`
        + (given.length ? `: ${given.map(g => plain(g, scopes)).join("; ")}.` : ", whose grants they already held.")
        + (found ? " They already had a sign-in, so no code was made." : ` Their one-time invitation code lasts until ${expires!.slice(0, 10)}; they choose their own password when they use it.`);
      const [{ saved }] = await tx`select okb.okb_add_record('administration', 'evidence', ${`Access for ${actor.display_name}: ${template || `${role} in ${workflow}`}`},
        ${`Records the access given to ${actor.display_name}.`}, ${JSON.stringify({ summary, source_reference: "The okb-invite hosted function", source_date: new Date().toISOString().slice(0, 10),
          standing: "observed", limitations: "Written by okb-invite as the grants were given." })}::text::jsonb) as saved`;
      answered(saved);
      const completed: string[] = [];
      for (const t of open) {
        const [{ linked }] = await tx`select okb.okb_link(${saved.record_id}::text, ${t.record_id}::text, 'supports', ${`${actor.display_name} is in OKB.`}) as linked`;
        answered(linked);
        // OKB moves a task from pending to completed through in_progress.
        if (t.state !== "in_progress") {
          const [{ started }] = await tx`select okb.okb_set_state(${t.record_id}::text, 'in_progress', ${`Adding ${actor.display_name}.`}) as started`;
          answered(started);
        }
        const [{ done }] = await tx`select okb.okb_set_state(${t.record_id}::text, 'completed', ${`${actor.display_name} is in OKB.`}, ${`okb-invite added ${actor.display_name}.`}) as done`;
        answered(done);
        completed.push(t.title);
      }
      return {
        ok: true, name: actor.display_name, email, actor_id: actor.actor_id, sign_in: found ? "existing" : "code",
        ...(code ? { code, code_expires_at: expires } : {}),
        ...(template ? { template } : { workflow, role }),
        grants: given.map(g => ({ scope: scopes.get(g.scope) ?? g.scope, actions: g.actions, own_records: g.own_records })),
        access_record_id: saved.record_id, completed_tasks: completed,
      };
    });
    return json(200, result);
  } catch (err) {
    if (err instanceof Refused) return json(err.status, { ok: false, problem: err.message });
    const code = (err as { code?: string })?.code;
    if (code === "42501" || code === "22023" || code === "23514") return json(400, { ok: false, problem: message(err) });
    console.error("okb-invite failed:", err);
    return json(500, { ok: false, problem: `okb-invite failed: ${message(err)}` });
  }
});
