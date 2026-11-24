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

// Supabase stops an instance at 2 s of CPU, counted across every request the instance serves.
// Measured on 2026-11-15 on a development project running this worker, over 65 instances and 433 rows of 18 to 1,200
// characters, with a budget of 1,000 ms: a row kept the CPU busy for up to 464 ms, and an instance
// used 150 to 210 ms of CPU besides its rows, booting and waiting on the database. The busiest
// instance used 1,574 ms. With 900 ms, an instance's last row starts under 900 ms and ends under
// 1,400 ms, and the instance stays under 1,600 ms.
const BUDGET_MS = 900;

// The time this instance's rows have kept the CPU busy, across every request it serves, and how
// many rows. Waits on Storage and the database are not counted. A row's time is the elapsed time of
// its CPU-bound work, the model's first load included, so it is at least the CPU it used.
let instanceMs = 0;
let instanceRows = 0;

/** Times work that keeps the CPU busy, and adds its elapsed time to the instance's count. */
async function counted<T>(work: () => Promise<T> | T): Promise<T> {
  const started = performance.now();
  try {
    return await work();
  } finally {
    instanceMs += performance.now() - started;
  }
}

// An instance runs one row at a time, across every request it serves at once, so a row starts only
// once the rows before it are counted.
let turn: Promise<unknown> = Promise.resolve();
function oneAtATime<T>(work: () => Promise<T>): Promise<T> {
  const mine = turn.then(work);
  turn = mine.catch(() => {});
  return mine;
}

/**
 * Takes a row at a time, so an attempt is counted only for a row that is tried. A row starts while
 * the instance's count is under BUDGET_MS, and the first row of the instance always. The model loads
 * during the first row. A request whose instance is over the budget takes no row, and the next
 * minute's schedule calls the worker again. On the budget, with rows still waiting after this
 * request's rows, the run queues the next run of the same job, as the schedule does.
 */
async function withinBudget<T>(job: string, claim: () => Promise<readonly Record<string, unknown>[]>, one: (row: Record<string, any>) => Promise<T>) {
  const done: T[] = [];
  for (;;) {
    const step = await oneAtATime(async () => {
      if (instanceRows > 0 && instanceMs >= BUDGET_MS) return { took: false, over: true };
      const [row] = await claim();
      if (!row) return { took: false, over: false };
      const before = instanceMs;
      const result = await one(row);
      instanceRows++;
      console.log(`file-search-worker: ${job} ${done.length + 1}, ${describe(row)} in ${Math.round(instanceMs - before)} ms, instance ${Math.round(instanceMs)} ms over ${instanceRows} rows`);
      return { took: true, over: false, result };
    });
    if (step.took) done.push(step.result as T);
    else if (step.over) {
      if (done.length === 0) console.log(`file-search-worker: ${job} took no row: the instance's rows have used ${Math.round(instanceMs)} ms over ${instanceRows} rows`);
      break;
    }
    else return { done, continued: false };
  }
  if (done.length === 0) return { done, continued: false };
  const [{ more }] = await sql`select file_search.has_work(${job}) as more`;
  if (more) await sql`select file_search.call_worker(${job})`;
  return { done, continued: more as boolean };
}

const describe = (row: Record<string, any>) => row.sentences
  ? `${row.sentences.length} sentences of ${row.sentences.reduce((n: number, s: Record<string, any>) => n + s.body.length, 0)} characters`
  : row.body !== undefined ? `${row.body.length} characters` : "a file";

async function takeText(file: Record<string, any>) {
  const where = `${file.bucket_id}/${file.name}`;
  try {
    const res = await fetch(objectUrl(file.bucket_id, file.name), { headers: { Authorization: `Bearer ${STORAGE_KEY}`, apikey: STORAGE_KEY } });
    if (!res.ok) throw new Error(`Storage answered ${res.status} for ${where}`);
    const bytes = new Uint8Array(await res.arrayBuffer());
    const got = await counted(() => extractSections(bytes, res.headers.get("content-type"), file.name));
    const { chunks, count, sections } = await counted(() => {
      const split = got.outcome === "extracted" ? splitChunks(got.sections) : [];
      const sections = got.outcome === "extracted" ? got.sections.map((s, i) => ({ ordinal: i, place: s.place, body: s.text.trim() })) : [];
      return { chunks: JSON.stringify(split), count: split.length, sections: JSON.stringify(sections) };
    });
    await sql`select file_search.record_file_text(${file.version_id}, ${got.outcome}, ${chunks}::text::jsonb, null, ${sections}::text::jsonb)`;
    return { file: where, outcome: got.outcome, chunks: count };
  } catch (err) {
    await sql`select file_search.record_file_text(${file.version_id}, 'failed', null, ${message(err)})`;
    return { file: where, outcome: "failed", problem: message(err) };
  }
}

/** Each vector is recorded as soon as it is made, so a run stopped part-way keeps what it made. */
async function makeVector(chunk: Record<string, any>) {
  try {
    const vector = Array.from(await counted(() => model.run(chunk.body, { mean_pool: true, normalize: true })) as number[]);
    await sql`select file_search.record_chunk_vector(${chunk.chunk_id}, ${`[${vector.join(",")}]`}, null)`;
    return true;
  } catch (err) {
    await sql`select file_search.record_chunk_vector(${chunk.chunk_id}, null, ${message(err)})`;
    return false;
  }
}

// A claim of sentences takes at most SENTENCE_BATCH, while their lengths add up to SENTENCE_CHARS,
// and always one. Measured on 2026-11-15 on a development project running this worker: a sentence takes the model about
// 180 ms and a further 0.1 ms for each character, 181 ms for 44 characters and 298 ms for 1,093. Two
// sentences of 900 characters take about 450 ms, as long as the slowest chunk, and a sentence of
// 1,200 characters alone about 300 ms.
const SENTENCE_BATCH = 2;
const SENTENCE_CHARS = 900;

/** A sentence's vector, made once its chunk has one, for an explained search to compare. */
async function makeSentenceVector(sentence: Record<string, any>) {
  try {
    const vector = Array.from(await counted(() => model.run(sentence.body, { mean_pool: true, normalize: true })) as number[]);
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
    const vector = Array.from(await counted(() => model.run(entity.body, { mean_pool: true, normalize: true })) as number[]);
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
    // Chunks first, then their sentences once no chunk waits, a batch at a time: a run loads the
    // model on its first row, so a row of one short sentence would leave each run one vector.
    const { done, continued } = await withinBudget(job, async () => {
      const chunks = await sql`select * from file_search.claim_chunks(1, ${call})`;
      if (chunks.length) return chunks;
      // A database not yet given 0005-worker-budget has the claim of a count alone.
      const sentences = await sql`select * from file_search.claim_sentences(${SENTENCE_BATCH}, ${SENTENCE_CHARS})`
        .catch((err) => {
          if (err?.code !== "42883") throw err;
          console.log("file-search-worker: claim_sentences(integer, integer) is missing, so sentences are claimed with no character budget. Apply file search upgrade 0005-worker-budget.");
          return sql`select * from file_search.claim_sentences(${SENTENCE_BATCH})`;
        });
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
