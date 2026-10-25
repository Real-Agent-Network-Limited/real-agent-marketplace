// Deletes one file from its bucket and its text and embeddings from the database, for the
// signed-in user. Storage decides, by the project's own rules, whether the user may delete the
// file; only once it has, are the file's text and embeddings deleted. The file's versions stay,
// marked purged, as the record that it was indexed. Deploy it with verify_jwt on.
//
// Request: { "bucket": "<bucket>", "file": "<the file's path in the bucket>" }.
import postgres from "npm:postgres@3.4.9";

const PROJECT = Deno.env.get("SUPABASE_URL")!;
// Each connection is named for the function, and closes after a second idle.
const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 1, prepare: false, idle_timeout: 1, connection: { application_name: "file-search-purge" } });

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

/** The signed-in user and their token, as Supabase Auth itself confirms, or null. */
async function signedIn(req: Request): Promise<{ id: string; token: string; key: string } | null> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const key = req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!token) return null;
  const res = await fetch(`${PROJECT}/auth/v1/user`, { headers: { Authorization: `Bearer ${token}`, apikey: key } });
  const user = res.ok ? await res.json().catch(() => null) : null;
  return typeof user?.id === "string" ? { id: user.id, token, key } : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { ok: false, problem: "Call this function with POST." });
  const user = await signedIn(req);
  if (!user) return json(401, { ok: false, problem: "Call this function with the user's own sign-in." });
  let args: { bucket?: unknown; file?: unknown };
  try { args = await req.json(); } catch { return json(400, { ok: false, problem: "The request must be JSON." }); }
  if (typeof args?.bucket !== "string" || typeof args?.file !== "string" || !args.bucket || !args.file)
    return json(400, { ok: false, problem: "Give the file's bucket and its path in the bucket, as bucket and file." });
  const { bucket, file } = args as { bucket: string; file: string };

  try {
    // The file, as the user sees it under the project's rules.
    const [found] = await sql.begin(async (tx) => {
      await tx`select set_config('request.jwt.claims', ${JSON.stringify({ sub: user.id, role: "authenticated" })}, true)`;
      await tx`set local role authenticated`;
      return await tx`select id from storage.objects where bucket_id = ${bucket} and name = ${file}`;
    });
    if (!found) return json(404, { ok: false, problem: `No file ${file} in ${bucket} that this user may open.` });

    const path = `${encodeURIComponent(bucket)}/${file.split("/").map(encodeURIComponent).join("/")}`;
    const deleted = await fetch(`${PROJECT}/storage/v1/object/${path}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${user.token}`, apikey: user.key },
    }).catch(() => null);
    // The user can see the file, so a 4xx is Storage refusing them; anything else is an outage.
    if (deleted && deleted.status >= 400 && deleted.status < 500) {
      const said = await deleted.json().catch(() => null);
      return json(403, { ok: false, problem: `Storage refused to delete the file, so its text was kept: ${said?.message ?? `HTTP ${deleted.status}`}` });
    }
    if (!deleted?.ok) {
      console.error("file-search-purge: Storage did not answer the delete:", deleted?.status);
      return json(502, { ok: false, problem: "Storage could not be reached, so nothing was deleted. Try again later." });
    }
    const [{ chunks }] = await sql`select file_search.purge(${found.id}) as chunks`;
    return json(200, { ok: true, bucket, file, chunks_deleted: chunks });
  } catch (err) {
    console.error("file-search-purge failed:", err);
    return json(500, { ok: false, problem: "Purging the file failed. Tell the project's administrator, who can finish it with file_search.purge_file." });
  }
});
