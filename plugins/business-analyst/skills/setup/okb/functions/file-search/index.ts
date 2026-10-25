// File search, called by a user's agent with the user's own sign-in. It confirms who the user is
// with Supabase Auth, turns the question into a vector, then searches as that user, so the
// project's own Storage rules decide which files the search covers. Deploy it with verify_jwt on.
//
// Request: { "query": "...", "bucket": "<bucket>" (optional), "limit": 1-50 (optional),
// "explain": true (optional) }. An explained search also gives each hit's sentences, with their
// similarity to the question, from the sentence vectors file-search-worker stored.
// Response: file_search.search's result as it returns it: hits, reference_hits (the reference
// scope's own top hits, in a search that names no bucket; empty when a bucket is named), sections
// (the reference hits' first) and stages.
import postgres from "npm:postgres@3.4.9";

declare const Supabase: { ai: { Session: new (model: string) => { run(input: string, options: object): Promise<unknown> } } };

const PROJECT = Deno.env.get("SUPABASE_URL")!;
// Each connection is named for the function, and closes after a second idle.
const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 1, prepare: false, idle_timeout: 1, connection: { application_name: "file-search" } });
const model = new Supabase.ai.Session("gte-small");

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const message = (err: unknown) => (err instanceof Error ? err.message : String(err));

/** The signed-in user, as Supabase Auth itself confirms, or null for a missing or refused token. */
async function signedIn(req: Request): Promise<{ id: string } | null> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const res = await fetch(`${PROJECT}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "" },
  });
  const user = res.ok ? await res.json().catch(() => null) : null;
  return typeof user?.id === "string" ? { id: user.id } : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { ok: false, problem: "Call this function with POST." });
  const user = await signedIn(req);
  if (!user) return json(401, { ok: false, problem: "Call this function with the user's own sign-in." });
  let args: { query?: unknown; bucket?: unknown; limit?: unknown; explain?: unknown };
  try { args = await req.json(); } catch { return json(400, { ok: false, problem: "The request must be JSON." }); }
  const query = typeof args?.query === "string" ? args.query.trim() : "";
  if (!query) return json(400, { ok: false, problem: "Give the question as query." });
  const limit = args.limit === undefined ? 10 : Number(args.limit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 50) return json(400, { ok: false, problem: "limit must be a whole number from 1 to 50." });
  if (args.bucket !== undefined && typeof args.bucket !== "string") return json(400, { ok: false, problem: "bucket must be a bucket's name." });
  const bucket = typeof args.bucket === "string" ? args.bucket : null;
  if (args.explain !== undefined && typeof args.explain !== "boolean") return json(400, { ok: false, problem: "explain must be true or false." });

  let vector: string | null = null;
  let degraded: string | null = null;
  try {
    vector = `{${Array.from(await model.run(query, { mean_pool: true, normalize: true }) as number[]).join(",")}}`;
  } catch (err) {
    degraded = `The semantic search did not run: ${message(err)}`;
  }

  try {
    const result = await sql.begin(async (tx) => {
      // As PostgREST does for a signed-in request: the user's claims, then the authenticated role.
      await tx`select set_config('request.jwt.claims', ${JSON.stringify({ sub: user.id, role: "authenticated" })}, true)`;
      await tx`set local role authenticated`;
      const [row] = await tx`select file_search.search(${query}, ${vector}::real[], ${bucket}, ${limit}, ${args.explain === true}) as result`;
      return row?.result;
    });
    if (!result || typeof result !== "object") return json(500, { ok: false, problem: "The search returned nothing to read." });
    if (degraded) result.degraded = degraded;
    return json(200, result);
  } catch (err) {
    // The search's own refusals say what to change; anything else is this service's fault, and is logged.
    const code = (err as { code?: string })?.code;
    if (code === "42501") return json(401, { ok: false, problem: message(err) });
    if (code === "22023") return json(400, { ok: false, problem: message(err) });
    console.error("file-search failed:", err);
    return json(500, { ok: false, problem: "File search failed. Try again later, or tell the project's administrator." });
  }
});
