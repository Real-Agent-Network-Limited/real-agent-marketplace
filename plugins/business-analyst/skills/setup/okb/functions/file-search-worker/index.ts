// File search's worker. Called every minute by the database's schedule, and by itself when a run
// ends on its time budget, with the worker secret from Vault, once for each kind of work that
// waits: {"job": "extract"} takes files' text and chunks it; {"job": "embed"} makes the chunks'
// vectors; {"job": "graph"} makes the vectors of the entities agents saved from the chunks.
// "call" names the database's record of the call, and each row the run claims is recorded against
// it. Deploy it with verify_jwt off: the secret is its check, not a sign-in.
import { AsyncLocalStorage } from "node:async_hooks";
import postgres from "npm:postgres@3.4.9";
import { extractSections, splitChunks } from "./text.ts";

declare const Supabase: { ai: { Session: new (model: string) => { run(input: string, options: object): Promise<unknown> } } };

const PROJECT = Deno.env.get("SUPABASE_URL")!;
// Storage's own key for this project's server side. It never leaves this function.
const STORAGE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Each run opens its own connection, and closes it when the run ends. Runs the function serves at the
// same time each keep theirs.
const runs = new AsyncLocalStorage<postgres.Sql>();
const sql = ((strings: TemplateStringsArray, ...values: unknown[]) =>
  runs.getStore()!(strings, ...(values as postgres.ParameterOrFragment<never>[]))) as unknown as postgres.Sql;
const model = new Supabase.ai.Session("gte-small");

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const message = (err: unknown) => (err instanceof Error ? err.message : String(err));

async function refused(req: Request): Promise<boolean> {
  const given = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const [row] = await sql`select decrypted_secret as secret from vault.decrypted_secrets where name = 'file_search_worker_secret'`;
  return !row?.secret || given !== row.secret;
}

function objectUrl(bucket: string, name: string): string {
  return `${PROJECT}/storage/v1/object/${encodeURIComponent(bucket)}/${name.split("/").map(encodeURIComponent).join("/")}`;
}

// Supabase stops a run at 2 s of CPU. Measured on 2026-09-30, over 261 runs: a row took up to
// 1,008 ms after the one before, and a run's CPU ended about 200 ms above its elapsed time at its
// last row. A run that starts no row after 700 ms stays under 2,000 ms.
const BUDGET_MS = 700;

/**
 * Takes a row at a time, so an attempt is counted only for a row that is tried. The first row
 * always, and another only in the run's first BUDGET_MS. The model loads during the first row.
 * On the budget, with rows still waiting, the run queues the next run of the same job, as the
 * schedule does.
 */
async function withinBudget<T>(job: string, claim: () => Promise<readonly Record<string, unknown>[]>, one: (row: Record<string, any>) => Promise<T>) {
  const started = performance.now();
  const done: T[] = [];
  while (done.length === 0 || performance.now() - started < BUDGET_MS) {
    const [row] = await claim();
    if (!row) return { done, continued: false };
    done.push(await one(row));
    console.log(`file-search-worker: ${job} ${done.length} at ${Math.round(performance.now() - started)} ms`);
  }
  const [{ more }] = await sql`select file_search.has_work(${job}) as more`;
  if (more) await sql`select file_search.call_worker(${job})`;
  return { done, continued: more as boolean };
}

async function takeText(file: Record<string, any>) {
  const where = `${file.bucket_id}/${file.name}`;
  try {
    const res = await fetch(objectUrl(file.bucket_id, file.name), { headers: { Authorization: `Bearer ${STORAGE_KEY}`, apikey: STORAGE_KEY } });
    if (!res.ok) throw new Error(`Storage answered ${res.status} for ${where}`);
    const got = await extractSections(new Uint8Array(await res.arrayBuffer()), res.headers.get("content-type"), file.name);
    const chunks = got.outcome === "extracted" ? splitChunks(got.sections) : [];
    const sections = got.outcome === "extracted" ? got.sections.map((s, i) => ({ ordinal: i, place: s.place, body: s.text.trim() })) : [];
    await sql`select file_search.record_file_text(${file.version_id}, ${got.outcome}, ${JSON.stringify(chunks)}::text::jsonb, null, ${JSON.stringify(sections)}::text::jsonb)`;
    return { file: where, outcome: got.outcome, chunks: chunks.length };
  } catch (err) {
    await sql`select file_search.record_file_text(${file.version_id}, 'failed', null, ${message(err)})`;
    return { file: where, outcome: "failed", problem: message(err) };
  }
}

/** Each vector is recorded as soon as it is made, so a run stopped part-way keeps what it made. */
async function makeVector(chunk: Record<string, any>) {
  try {
    const vector = Array.from(await model.run(chunk.body, { mean_pool: true, normalize: true }) as number[]);
    await sql`select file_search.record_chunk_vector(${chunk.chunk_id}, ${`[${vector.join(",")}]`}, null)`;
    return true;
  } catch (err) {
    await sql`select file_search.record_chunk_vector(${chunk.chunk_id}, null, ${message(err)})`;
    return false;
  }
}

// Measured on 2026-10-18: a sentence takes the model 115 to 160 ms, so 8 stay well inside a run's 2 s
// of CPU with the model's load.
const SENTENCE_BATCH = 8;

/** A sentence's vector, made once its chunk has one, for an explained search to compare. */
async function makeSentenceVector(sentence: Record<string, any>) {
  try {
    const vector = Array.from(await model.run(sentence.body, { mean_pool: true, normalize: true }) as number[]);
    await sql`select file_search.record_sentence_vector(${sentence.sentence_id}, ${`[${vector.join(",")}]`}, null)`;
    return true;
  } catch (err) {
    await sql`select file_search.record_sentence_vector(${sentence.sentence_id}, null, ${message(err)})`;
    return false;
  }
}

/** A batch of sentences' vectors, one at a time, each recorded as it is made. */
async function makeSentenceVectors(sentences: Record<string, any>[]) {
  const done: { sentence: boolean; ok: boolean }[] = [];
  for (const sentence of sentences) done.push({ sentence: true, ok: await makeSentenceVector(sentence) });
  return done;
}

/** An entity's vector, from its name and type, as a chunk's is made. */
async function makeEntityVector(entity: Record<string, any>) {
  try {
    const vector = Array.from(await model.run(entity.body, { mean_pool: true, normalize: true }) as number[]);
    await sql`select file_search.record_entity_vector(${entity.entity_id}, ${`[${vector.join(",")}]`}, null)`;
    return true;
  } catch (err) {
    await sql`select file_search.record_entity_vector(${entity.entity_id}, null, ${message(err)})`;
    return false;
  }
}

Deno.serve(async (req) => {
  const db = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 1, prepare: false, connection: { application_name: "file-search-worker" } });
  try {
    return await runs.run(db, () => run(req));
  } finally {
    await db.end();
  }
});

async function run(req: Request): Promise<Response> {
  if (await refused(req)) return json(401, { ok: false, problem: "Refused: this is not the file search worker's secret." });
  const body = await req.json().catch(() => undefined);
  const job = body?.job;
  const call = Number.isSafeInteger(body?.call) ? body.call : null;
  if (job === "extract") {
    const { done, continued } = await withinBudget(job, () => sql`select * from file_search.claim_files(1, ${call})`, takeText);
    return json(200, { ok: true, files: done, continued });
  }
  if (job === "embed") {
    // Chunks first, then their sentences once no chunk waits, SENTENCE_BATCH at a time: a run loads the
    // model on its first row, so a row of one short sentence would leave each run one vector.
    const { done, continued } = await withinBudget(job, async () => {
      const chunks = await sql`select * from file_search.claim_chunks(1, ${call})`;
      if (chunks.length) return chunks;
      const sentences = await sql`select * from file_search.claim_sentences(${SENTENCE_BATCH})`;
      return sentences.length ? [{ sentences }] : [];
    }, async (row) => row.sentences ? await makeSentenceVectors(row.sentences) : [{ sentence: false, ok: await makeVector(row) }]);
    const all = done.flat();
    const count = (sentence: boolean, ok: boolean) => all.filter((d) => d.sentence === sentence && d.ok === ok).length;
    return json(200, { ok: true, chunks: { embedded: count(false, true), failed: count(false, false) },
      sentences: { embedded: count(true, true), failed: count(true, false) }, continued });
  }
  if (job === "graph") {
    const { done, continued } = await withinBudget(job, () => sql`select * from file_search.claim_entities(1)`, makeEntityVector);
    return json(200, { ok: true, entities: { embedded: done.filter(Boolean).length, failed: done.filter((ok) => !ok).length }, continued });
  }
  return json(400, { ok: false, problem: 'Name the job: {"job": "extract"}, {"job": "embed"} or {"job": "graph"}.' });
}
