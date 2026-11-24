// OKB's graph reader, off until the firm adds its own Anthropic API key. Deploy it with verify_jwt off: the
// schedule's secret, or an administrator's sign-in, is its check. Called every 15 minutes by the
// database's schedule, with the secret graph_reader_secret from the Vault, while a batch is open, or, once the key is
// in the Vault, while a part waits. It reads each waiting part of the files in the scopes okb_private.graph_reader_buckets()
// names, every one except private, sessions, Administration, Guides and plugin scopes, with Claude Haiku 5.5, through
// the Message Batches API, and saves what Claude finds as the part's entities and relations, in the name of Graph
// reader. Each entity's type is a class in the firm's glossary, and each relation one of its relationships: OKB
// drops a finding that fits none, and keeps it with its reason. Each run does one of two things, or both in turn:
// - With a batch open, it asks the API for the batch's state. Once the batch has ended, it saves each
//   result, logs the batch's tokens and cost, and closes the batch.
// - With no batch open, it claims up to the settings' batch size of waiting parts, 1,000 to start, and
//   sends them as one batch, one request a part, with the part's chunk_id as its custom_id.
// A result outside the schema, or one OKB refuses, leaves its part waiting with its attempts counted,
// and the third marks it failed. A request the API did not answer leaves its part waiting, with no
// attempt counted. No batch is sent once the month's logged cost reaches the cap in
// file_search.graph_settings. The rules Claude follows are section 19 of the okb plugin's records skill, built
// into prompt.ts by scripts/graph-reader-prompt.ts, followed by the glossary's classes and relationships, read
// from OKB at each run.
//
// An administrator calls it with their own sign-in for three actions. "set_key" keeps the firm's Anthropic API
// key in the Vault, as the secret anthropic_api_key, once the Models API accepts it, which turns the reader on.
// "remove_key" deletes it, which turns the reader off. "check" reports the key as available, missing or refused. The
// key is read on every call, from the Vault, and no reply or error holds it. A failed read of the Vault answers 503,
// "OKB is busy. Try again in a minute.".
//
// Request: {} with the schedule's secret, for a run
//      or: { "action": "check" } or { "action": "remove_key" } with an administrator's sign-in
//      or: { "action": "set_key", "key": "sk-ant-..." } with an administrator's sign-in
import { AsyncLocalStorage } from "node:async_hooks";
import postgres from "npm:postgres@3.4.9";
import Anthropic from "npm:@anthropic-ai/sdk@0.137.0";
import { PROMPT } from "./prompt.ts";

/** The level of the request's sign-in: aal2 once Supabase Auth has confirmed a token whose sign-in gave a code
 * from an authenticator app, aal1 otherwise. OKB refuses a call at aal1 where its second factor setting says. */
const level = new AsyncLocalStorage<{ aal: string }>();
const aal = () => level.getStore()?.aal ?? "aal1";
/** Notes the level of a token Supabase Auth has confirmed, from the aal claim in its payload. */
function confirmed(token: string) {
  const store = level.getStore();
  if (!store) return;
  try { store.aal = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).aal === "aal2" ? "aal2" : "aal1"; }
  catch { store.aal = "aal1"; }
}


const PROJECT = Deno.env.get("SUPABASE_URL")!;
const MODEL = "claude-haiku-5-5";
const MAX_TOKENS = 16000;
// A batch's rates, in dollars a million tokens: half of Claude Haiku 5.5's $0.10 input and $0.50 output.
// The rules are cached for an hour: a cache write costs 2 times the input rate, and a cache read 0.1 times.
const RATES = { input: 0.05, cacheWrite: 0.1, cacheRead: 0.005, output: 0.25 };
// The limits okb_save_extraction holds a part's entities and relations to.
const LIMITS = { entities: 100, relations: 200, name: 200, type: 100, description: 2000 };
const VAULT_KEY = "anthropic_api_key";
const SCHEMA = {
  type: "object", additionalProperties: false, required: ["entities", "relations"],
  properties: {
    entities: {
      type: "array", items: {
        type: "object", additionalProperties: false, required: ["name", "type", "description"],
        properties: { name: { type: "string" }, type: { type: "string" }, description: { type: "string" } },
      },
    },
    relations: {
      type: "array", items: {
        type: "object", additionalProperties: false, required: ["source", "target", "relationship", "keywords", "description"],
        properties: { source: { type: "string" }, target: { type: "string" }, relationship: { type: "string" }, keywords: { type: "array", items: { type: "string" } }, description: { type: "string" } },
      },
    },
  },
};

// Each request's own connection and keys: the key it uses, and a new key set_key is checking.
const runs = new AsyncLocalStorage<{ sql: postgres.Sql; current: string; offered: string }>();
const sql = ((strings: TemplateStringsArray, ...values: unknown[]) =>
  runs.getStore()!.sql(strings, ...(values as postgres.ParameterOrFragment<never>[]))) as unknown as postgres.Sql;
const key = () => runs.getStore()?.current ?? "";
/** Text with each key, wherever it appears, replaced. */
const clean = (text: string) => [runs.getStore()?.current, runs.getStore()?.offered]
  .filter((k): k is string => !!k).reduce((t, k) => t.replaceAll(k, "[key]"), text);
const json = (status: number, body: unknown) =>
  new Response(clean(JSON.stringify(body)), { status, headers: { "Content-Type": "application/json" } });
const message = (err: unknown) => clean(err instanceof Error ? err.message : String(err));

/** The Anthropic client, and Supabase Auth's check of a sign-in. The tests replace them. */
export const seam = {
  connect: () => postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 1, prepare: false, connection: { application_name: "graph-reader" } }),
  client: (apiKey: string) => new Anthropic({ apiKey, maxRetries: 2, timeout: 120_000 }),
  user: async (token: string, apikey: string): Promise<string | null> => {
    const res = await fetch(`${PROJECT}/auth/v1/user`, { headers: { Authorization: `Bearer ${token}`, apikey } });
    const user = res.ok ? await res.json().catch(() => null) : null;
    return typeof user?.id === "string" ? user.id : null;
  },
};

class Refusal extends Error {
  constructor(readonly status: number, readonly body: Record<string, unknown>) { super(String(body.problem)); }
}
const refuse = (status: number, problem: string, more: Record<string, unknown> = {}) => new Refusal(status, { ok: false, problem, ...more });

/** A result's entities and relations, held to the schema and OKB's limits, or the reason it fails. */
export function readResult(text: string): { entities: unknown[]; relations: unknown[] } | { error: string } {
  let got: any;
  try { got = JSON.parse(text); } catch { return { error: "Claude's answer is not JSON" }; }
  if (!got || typeof got !== "object" || !Array.isArray(got.entities) || !Array.isArray(got.relations))
    return { error: "Claude's answer has no entities and relations lists" };
  if (got.entities.length > LIMITS.entities || got.relations.length > LIMITS.relations)
    return { error: `Claude gave ${got.entities.length} entities and ${got.relations.length} relations: a part takes at most ${LIMITS.entities} and ${LIMITS.relations}` };
  const within = (v: unknown, max: number) => typeof v === "string" && v.trim().length >= 1 && v.trim().length <= max;
  for (const e of got.entities) {
    if (!e || !within(e.name, LIMITS.name) || !within(e.type, LIMITS.type) || !within(e.description, LIMITS.description))
      return { error: `An entity is outside the schema: ${JSON.stringify(e).slice(0, 300)}` };
  }
  for (const r of got.relations) {
    if (!r || !within(r.source, LIMITS.name) || !within(r.target, LIMITS.name) || !within(r.relationship, LIMITS.type) || !within(r.description, LIMITS.description)
      || !Array.isArray(r.keywords) || r.keywords.some((k: unknown) => typeof k !== "string"))
      return { error: `A relation is outside the schema: ${JSON.stringify(r).slice(0, 300)}` };
  }
  return { entities: got.entities, relations: got.relations };
}

/** The system prompt: section 19's rules, then the glossary's classes and relationships. */
async function system(): Promise<string> {
  const classes = await sql`select term from okb.glossary_term where kind = 'class' order by lower(term)`;
  const relationships = await sql`select term, from_class, to_class from okb.glossary_term where kind = 'relationship' order by lower(term)`;
  return `${PROMPT}\n\n**The glossary's classes:**\n\n${classes.map((r) => `- ${r.term}`).join("\n")}\n\n**The glossary's relationships:**\n\n${
    relationships.map((r) => `- ${r.term}, from a ${r.from_class} to a ${r.to_class}`).join("\n") || "- The glossary has no relationships yet. Give no relations."}`;
}

/** The open batch's state from the API. Once it has ended, each result is saved and the batch closed. */
async function collect(open: { batch_id: string; api_batch_id: string }) {
  const client = seam.client(key());
  let batch;
  try {
    batch = await client.messages.batches.retrieve(open.api_batch_id);
  } catch (err) {
    if (!(err instanceof Anthropic.NotFoundError)) throw err;
    // The API no longer holds the batch, as after a key from another workspace, or results past their
    // 29 days. Its parts go back to waiting, with no attempt counted, and the batch closes with the reason.
    const problem = `The API no longer holds batch ${open.api_batch_id}, so its parts wait to be sent again`;
    const [{ chunks }] = await sql`select chunks from file_search.graph_batch where batch_id=${open.batch_id}::uuid`;
    const results = (chunks as string[]).map((c) => ({ chunk_id: c, retry: problem }));
    const usage = { input_tokens: 0, cache_write_tokens: 0, cache_read_tokens: 0, output_tokens: 0, cost_usd: 0, ended_at: null, problem };
    const [{ closed }] = await sql`select okb_private.save_graph_batch(${open.batch_id}::uuid, ${JSON.stringify(results)}::text::jsonb, ${JSON.stringify(usage)}::text::jsonb) as closed`;
    return { ...closed, problem };
  }
  if (batch.processing_status !== "ended") return { batch: open.batch_id, state: batch.processing_status, counts: batch.request_counts };
  const results: Record<string, unknown>[] = [];
  const usage = { input_tokens: 0, cache_write_tokens: 0, cache_read_tokens: 0, output_tokens: 0, cost_usd: 0, ended_at: batch.ended_at ?? null };
  for await (const r of await client.messages.batches.results(open.api_batch_id)) {
    const res = r.result as any;
    // A request the API did not answer, such as one it errored, expired or canceled, goes back to
    // waiting with no attempt counted: Claude never read the part.
    if (res.type !== "succeeded") {
      results.push({ chunk_id: r.custom_id, retry: res.type === "errored" ? `The API gave an error: ${res.error?.error?.type ?? res.error?.type ?? "unknown"}` : `The request was ${res.type}` });
      continue;
    }
    const m = res.message;
    usage.input_tokens += m.usage?.input_tokens ?? 0;
    usage.cache_write_tokens += m.usage?.cache_creation_input_tokens ?? 0;
    usage.cache_read_tokens += m.usage?.cache_read_input_tokens ?? 0;
    usage.output_tokens += m.usage?.output_tokens ?? 0;
    if (m.stop_reason !== "end_turn") { results.push({ chunk_id: r.custom_id, error: `Claude stopped with ${m.stop_reason}` }); continue; }
    const text = (m.content ?? []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("");
    results.push({ chunk_id: r.custom_id, ...readResult(text) });
  }
  usage.cost_usd = Number(((usage.input_tokens * RATES.input + usage.cache_write_tokens * RATES.cacheWrite
    + usage.cache_read_tokens * RATES.cacheRead + usage.output_tokens * RATES.output) / 1e6).toFixed(6));
  const [{ closed }] = await sql`select okb_private.save_graph_batch(${open.batch_id}::uuid, ${JSON.stringify(results)}::text::jsonb, ${JSON.stringify(usage)}::text::jsonb) as closed`;
  return { ...closed, ...usage };
}

/** Claims the waiting parts and sends them as one batch. */
async function send() {
  const [{ claim }] = await sql`select file_search.claim_unextracted(okb_private.graph_reader_buckets(), (select batch_size from file_search.graph_settings)) as claim`;
  if (!claim.claimed) return { sent: false, reason: claim.reason, ...(claim.capped ? { capped: true } : {}) };
  const rules = await system();
  const requests = (claim.chunks as { chunk_id: string; text: string }[]).map((c) => ({
    custom_id: c.chunk_id,
    params: {
      model: MODEL, max_tokens: MAX_TOKENS,
      system: [{ type: "text", text: rules, cache_control: { type: "ephemeral", ttl: "1h" } }],
      messages: [{ role: "user", content: `<part>\n${c.text.replaceAll("</part>", "</ part>")}\n</part>` }],
      output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } },
    },
  }));
  let batch;
  try {
    batch = await seam.client(key()).messages.batches.create({ requests } as any);
  } catch (err) {
    await sql`select file_search.graph_batch_unsent(${claim.batch_id}::uuid, ${`The batch was not sent: ${message(err)}`})`;
    throw err;
  }
  // The API holds the batch now. Its id is recorded on this run's connection, or else on a new one.
  // A batch never recorded is cancelled, and logged with its id. Its claim closes after 10 minutes.
  try {
    await recordSent(claim.batch_id, batch.id);
  } catch (err) {
    await seam.client(key()).messages.batches.cancel(batch.id)
      .catch((e) => console.error(`graph-reader could not cancel batch ${batch.id}:`, message(e)));
    throw err;
  }
  return { sent: true, batch: claim.batch_id, parts: requests.length };
}

async function recordSent(batch: string, apiBatch: string) {
  for (let attempt = 1; ; attempt++) {
    try {
      if (attempt === 1) await sql`select file_search.graph_batch_sent(${batch}::uuid, ${apiBatch}, ${MODEL})`;
      else {
        const db = seam.connect();
        try { await db`select file_search.graph_batch_sent(${batch}::uuid, ${apiBatch}, ${MODEL})`; } finally { await db.end(); }
      }
      return;
    } catch (err) {
      console.error(`graph-reader could not record batch ${apiBatch} for claim ${batch}, attempt ${attempt}:`, message(err));
      if (attempt === 3) throw new Error(`The API holds batch ${apiBatch}, and OKB could not record it: ${message(err)}`);
    }
  }
}

/** One run: the open batch's results, then a new batch once none is open. */
async function run() {
  const [{ open }] = await sql`select file_search.open_graph_batch() as open`;
  let collected = null;
  if (open?.api_batch_id) {
    collected = await collect(open);
    if (!collected.closed) return { ok: true, open: collected };
  } else if (open) return { ok: true, open: { batch: open.batch_id, state: "claimed, not yet sent" } };
  return { ok: true, ...(collected ? { closed: collected } : {}), ...(await send()) };
}

/** Keeps a new key in the Vault once the Models API accepts it. */
async function setKey(given: unknown) {
  const candidate = typeof given === "string" ? given.trim() : "";
  if (!/^sk-ant-[A-Za-z0-9_-]{20,300}$/.test(candidate)) throw refuse(400, "Give the Anthropic API key, which starts sk-ant-, as key. Nothing was kept.");
  runs.getStore()!.offered = candidate;
  const model = await seam.client(candidate).models.retrieve(MODEL).catch((err) => {
    if (err instanceof Anthropic.AuthenticationError || err instanceof Anthropic.PermissionDeniedError)
      throw refuse(422, "Anthropic refused the new key. Nothing was kept.");
    throw refuse(502, `Anthropic did not confirm the new key: ${message(err)}. Nothing was kept.`);
  });
  await runs.getStore()!.sql.begin(async (tx) => {
    await tx`select pg_advisory_xact_lock(hashtextextended(${VAULT_KEY}, 19483))`;
    const [row] = await tx`select id from vault.secrets where name = ${VAULT_KEY}`;
    if (row) await tx`select vault.update_secret(${row.id}::uuid, ${candidate})`;
    else await tx`select vault.create_secret(${candidate}, ${VAULT_KEY}, ${"The firm's Anthropic API key, which graph-reader uses, set with its set_key action"})`;
  });
  runs.getStore()!.current = candidate;
  return { ok: true, key: "set", model: model.id };
}

/** Deletes the key from the Vault, which turns the reader off. An open batch is still collected at the next run
 * while its results are held, then nothing more is sent. */
async function removeKey() {
  const gone = await runs.getStore()!.sql.begin(async (tx) => {
    await tx`select pg_advisory_xact_lock(hashtextextended(${VAULT_KEY}, 19483))`;
    return await tx`delete from vault.secrets where name = ${VAULT_KEY} returning id`;
  });
  runs.getStore()!.current = "";
  return { ok: true, key: gone.length ? "removed" : "missing" };
}

async function check() {
  if (!key()) return { ok: true, key: "missing" };
  try {
    const model = await seam.client(key()).models.retrieve(MODEL);
    return { ok: true, key: "available", model: model.id };
  } catch (err) {
    if (err instanceof Anthropic.AuthenticationError || err instanceof Anthropic.PermissionDeniedError) return { ok: true, key: "refused" };
    throw refuse(502, `Anthropic did not answer: ${message(err)}`);
  }
}

Deno.serve(async (req) => {
  const db = seam.connect();
  try {
    return await level.run({ aal: "aal1" }, () => runs.run({ sql: db, current: "", offered: "" }, () => serve(req)));
  } finally {
    await db.end();
  }
});

async function serve(req: Request): Promise<Response> {
  if (req.method !== "POST") return json(405, { ok: false, problem: "Call this function with POST." });
  try {
    let busy = false;
    try {
      const [row] = await sql`select decrypted_secret from vault.decrypted_secrets where name = ${VAULT_KEY}`;
      runs.getStore()!.current = row?.decrypted_secret ?? "";
    } catch (err) {
      console.error("graph-reader could not read the Vault:", message(err));
      busy = true;
    }
    const given = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const args = await req.json().catch(() => ({})) as Record<string, unknown>;
    const scheduled = !busy && given && await sql`select decrypted_secret as s from vault.decrypted_secrets where name = 'graph_reader_secret'`
      .then(([row]) => !!row?.s && row.s === given);
    if (busy) throw refuse(503, "OKB is busy. Try again in a minute.", { busy: true });
    if (scheduled) {
      if (!key()) throw refuse(503, "The graph reader is off: the firm's Anthropic API key is not in the Vault. An administrator types it on the graph reader card in Real Agent's connector, as the business analyst describes.", { key: "missing" });
      return json(200, await run());
    }
    const user = given ? await seam.user(given, req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "") : null;
    if (!user) return json(401, { ok: false, problem: "Call this function with an administrator's sign-in." });
    confirmed(given);
    const [admin] = await sql`select okb_private.second_factor_missing(${user}::uuid, ${aal()}) as missing
      from okb.actor a join okb.actor h on h.actor_id = a.accountable_human_id
      where a.auth_user_id = ${user}::uuid and a.enabled and a.authority_class = 'administrator' and h.enabled and h.actor_kind = 'human'`;
    if (!admin) throw refuse(403, "Only an administrator sets, removes or checks graph-reader's key.");
    if (admin.missing) throw refuse(403, "Sign in with a code from your authenticator app, then try again.", { second_factor: true });
    if (args.action === "set_key") return json(200, await setKey(args.key));
    if (args.action === "remove_key") return json(200, await removeKey());
    if (args.action === "check") return json(200, await check());
    throw refuse(400, "action is check, set_key or remove_key.");
  } catch (err) {
    if (err instanceof Refusal) return json(err.status, err.body);
    console.error("graph-reader failed:", message(err));
    return json(500, { ok: false, problem: `The run failed: ${message(err)}` });
  }
}
