// okb-upgrade: applies one of Real Agent's signed upgrades to the firm's OKB, for Real Agent's own actor. Deploy it with
// verify_jwt on, through the Supabase connector's deploy_edge_function, with upgrade-key.ts beside it. It stays
// deployed: setup deploys it with the others. It is how Real Agent keeps a client's OKB current, with no role in the
// client's Supabase organisation.
//
// POST .../okb-upgrade, with the caller's own sign-in, JSON { series, number, name, sql, signature }, which
// scripts/sign-upgrade.mjs writes: series "okb" for the upgrades/ folder or "file_search" for file-search-upgrades/,
// the upgrade's four-digit number and name, as its file is named, the file's whole text, and an Ed25519 signature over
// the text's exact UTF-8 bytes, in base64. It confirms who the caller is with Supabase Auth, then asks OKB, as the
// caller, with okb_get_actor: only an enabled person who holds every grant of the real_agent access template, as
// apply_access_template reads a grant as held, goes on. An administrator holds no template's grants, so is refused.
// Nothing the caller sends says who they are.
//
// It verifies the signature with Real Agent's upgrade public key, in upgrade-key.ts, so only a file Real Agent signed
// runs, unchanged. The file's first line must name the same upgrade, as "-- <number>-<name>". The series' ledger,
// okb_private.schema_upgrade or file_search.schema_upgrade, must hold every earlier number and not this one: an upgrade
// already applied, and one whose earlier upgrade is missing, are refused. It runs the file as the postgres login, as
// okb-setup runs an approved setup file, in one transaction with the checks, under a lock, so two calls never run at
// once. The file records its own id in its ledger, as every upgrade does, and the function refuses one that does not.
// A failure keeps nothing.
//
// Response: { ok: true, upgrade, ledger } or { ok: false, problem }. The answer holds no key, token or secret.
import postgres from "npm:postgres@3.4.9";
import { UPGRADE_PUBLIC_KEY } from "./upgrade-key.ts";

const PROJECT = Deno.env.get("SUPABASE_URL")!;
const LEDGERS: Record<string, string> = { okb: "okb_private.schema_upgrade", file_search: "file_search.schema_upgrade" };
// The largest upgrade text it takes.
const MAX_TEXT = 2_000_000;

const db = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 1, prepare: false, idle_timeout: 1, onnotice: () => {}, connection: { application_name: "okb-upgrade" } });

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const message = (err: unknown) => (err instanceof Error ? err.message : String(err));
class Refused extends Error { constructor(public status: number, text: string) { super(text); } }

/** The signed-in caller, as Supabase Auth itself confirms, or null. */
async function signedIn(req: Request): Promise<string | null> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const key = req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!token) return null;
  const res = await fetch(`${PROJECT}/auth/v1/user`, { headers: { Authorization: `Bearer ${token}`, apikey: key } }).catch(() => null);
  const user = res?.ok ? await res.json().catch(() => null) : null;
  return typeof user?.id === "string" ? user.id : null;
}

const fromBase64 = (text: string) => Uint8Array.from(atob(text), c => c.charCodeAt(0));

/** True when signature is Real Agent's Ed25519 signature over text's UTF-8 bytes. */
export async function signedByRealAgent(text: string, signature: string, publicKey = UPGRADE_PUBLIC_KEY): Promise<boolean> {
  let sig: Uint8Array, raw: Uint8Array;
  try { sig = fromBase64(signature); raw = fromBase64(publicKey); } catch { return false; }
  if (sig.length !== 64 || raw.length !== 32) return false;
  const key = await crypto.subtle.importKey("raw", raw, { name: "Ed25519" }, false, ["verify"]);
  return await crypto.subtle.verify({ name: "Ed25519" }, key, sig, new TextEncoder().encode(text));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { ok: false, problem: "Call this function with POST." });
  const caller = await signedIn(req);
  if (!caller) return json(401, { ok: false, problem: "Call this function with your own sign-in." });
  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { ok: false, problem: "The request must be JSON." }); }

  try {
    // deno-lint-ignore no-explicit-any
    const result = await db.begin(async (tx: any) => {
      // One upgrade at a time in a project.
      await tx`select pg_advisory_xact_lock(hashtext('okb-upgrade'))`;
      // Who the caller is, as OKB itself answers it for their sign-in.
      await tx`select set_config('request.jwt.claims', ${JSON.stringify({ sub: caller, role: "authenticated" })}, true)`;
      await tx`set local role authenticated`;
      // deno-lint-ignore no-explicit-any
      let me: any;
      try { [{ me }] = await tx`select okb.okb_get_actor() as me`; }
      catch { throw new Refused(403, "Your sign-in has no actor in this Real Agent knowledge base, so it applies no upgrade."); }
      await tx`reset role`;
      await tx`select set_config('request.jwt.claims', '', true)`;
      const [{ realAgent }] = await tx`select a.enabled and a.actor_kind = 'human' and t.code is not null and jsonb_array_length(t.grants) > 0
        and not exists(select 1 from jsonb_array_elements(t.grants) g where not exists(
          select 1 from okb.authorisation z join okb.scope s using (scope_id)
          where z.executor_actor_id = a.actor_id and s.code = g->>'scope' and z.record_id is null and z.mode = 'standing_permission'
            and z.record_kinds @> array(select jsonb_array_elements_text(g->'record_kinds'))
            and z.allowed_actions @> array(select jsonb_array_elements_text(g->'actions'))
            and ((g->>'own_records')::boolean or not z.own_records)
            and okb_private.authority_live(z.authorisation_id))) as "realAgent"
        from okb.actor a left join okb.access_template t on t.code = 'real_agent' where a.actor_id = ${me.actor_id}`;
      if (!realAgent) throw new Refused(403, "Only Real Agent's own actor, with the real_agent access template, applies an upgrade.");

      // The upgrade, as Real Agent signed it.
      const series = typeof body?.series === "string" ? body.series : "okb";
      const ledger = LEDGERS[series];
      if (!ledger) throw new Refused(400, "The series is okb or file_search.");
      const number = typeof body?.number === "string" ? body.number : "";
      const name = typeof body?.name === "string" ? body.name : "";
      const text = typeof body?.sql === "string" ? body.sql : "";
      if (!/^[0-9]{4}$/.test(number) || !/^[a-z0-9][a-z0-9-]*$/.test(name)) throw new Refused(400, "Give the upgrade's four-digit number and its name, as its file is named.");
      if (!text || text.length > MAX_TEXT) throw new Refused(400, "Give the upgrade's whole text, as its file holds it.");
      if (typeof body?.signature !== "string" || !body.signature) throw new Refused(403, "This upgrade is not signed, so it was not applied. Sign it with scripts/sign-upgrade.mjs.");
      if (!await signedByRealAgent(text, body.signature)) throw new Refused(403, "This upgrade's signature is not Real Agent's, or the file was changed after it was signed, so it was not applied.");
      const id = `${number}-${name}`;
      const header = /^-- ([0-9]{4}-[a-z0-9-]+)(?::|\s*$)/.exec(text.split("\n", 1)[0]);
      if (header?.[1] !== id) throw new Refused(400, `The file's first line names ${header?.[1] ?? "no upgrade"}, not ${id}, so it was not applied.`);

      // Its place in the series' ledger.
      const held = (await tx.unsafe(`select id from ${ledger} order by id`)).map((r: { id: string }) => r.id);
      const numbers = held.map((h: string) => Number(h.slice(0, 4)));
      const n = Number(number);
      const last = numbers.length ? Math.max(...numbers) : 0;
      if (held.includes(id) || numbers.includes(n)) throw new Refused(409, `Upgrade ${number} is already applied here, so it was not applied again.`);
      if (n < last) throw new Refused(409, `Upgrade ${id} is out of order: this project already holds upgrade ${String(last).padStart(4, "0")}, so it was not applied.`);
      if (n > last + 1) throw new Refused(409, `Upgrade ${id} needs upgrade ${String(last + 1).padStart(4, "0")} first, so it was not applied.`);

      // The file, as the postgres login, as okb-setup runs an approved file: every statement in one request.
      try { await tx.unsafe(text).simple(); }
      catch (err) { throw new Refused(422, `Upgrade ${id} failed, and nothing of it was kept: ${message(err)}`); }
      await tx`reset role`;
      const after = (await tx.unsafe(`select id from ${ledger} order by id`)).map((r: { id: string }) => r.id);
      if (!after.includes(id)) throw new Refused(422, `Upgrade ${id} did not record itself in ${ledger}, so nothing of it was kept.`);
      return { ok: true, upgrade: id, ledger: after };
    });
    return json(200, result);
  } catch (err) {
    if (err instanceof Refused) return json(err.status, { ok: false, problem: err.message });
    console.error("okb-upgrade failed:", err);
    return json(500, { ok: false, problem: `okb-upgrade failed: ${message(err)}` });
  }
});
