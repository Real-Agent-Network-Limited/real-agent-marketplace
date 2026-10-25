// Uploads session copies from <agent folder>/sessions/ into the person's sessions scope in OKB, replacing
// the file already there, and purges each copy whose session's title has changed.
//
//   node session-upload.mjs <sessions folder> <actor|settings> <name.md> ... [-<old name.md> ...]
//
// It signs in with the person's saved sign-in, for the project and email in the actor file of the
// folder that holds the sessions folder (`actor`), or in the okb plugin's settings (`settings`). The
// sessions scope is the scope whose code starts sessions_ where the person themselves holds a live,
// standing grant with create. An administrator sees the grants of every actor, so only a grant whose
// executor is the signed-in actor counts. With no saved sign-in or no such grant, it ends with nothing
// uploaded. Each failure is added to upload-problems.log in the sessions folder. Each copy uploaded is
// noted, with its time, in .uploaded.json there, which session-history.mjs reads.
import { appendFileSync, readFileSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { readActor } from "../mcp/lib/actor-file.mjs";
import { accountEmail } from "../mcp/lib/session.mjs";
import { createTools } from "../mcp/lib/tools.mjs";
import { UPLOADED, uploaded } from "./session-copy.mjs";

/** The okb plugin's id in Claude Code's settings. */
const PLUGIN_ID = "okb@real-agent";
const SCHEMA = "okb";

/** The project and email of the actor file in the folder that holds `sessionsFolder`, or null. */
export function actorConnection(sessionsFolder) {
  const actor = readActor(dirname(sessionsFolder));
  return actor?.ok ? { ref: actor.value.project_ref, email: actor.value.auth_email } : null;
}

/** The okb plugin's project and email, from Claude Code's settings, or null. */
export function connection(home = homedir(), configDir = process.env.CLAUDE_CONFIG_DIR) {
  try {
    const settings = JSON.parse(readFileSync(join(configDir || join(home, ".claude"), "settings.json"), "utf-8"));
    const options = settings?.pluginConfigs?.[PLUGIN_ID]?.options ?? {};
    const ref = String(options.project_ref ?? "").trim();
    const email = accountEmail(options.auth_email);
    return ref && email ? { ref, email } : null;
  } catch { return null; }
}

/** The code of the scope the actor's own grants give for sessions, or null. */
export function sessionsScope(grants, scopes, actorId, now = Date.now()) {
  if (!actorId) return null;
  const codes = new Map(scopes.map(s => [s.scope_id, s.code]));
  for (const grant of grants) {
    if (grant.executor_actor_id !== actorId || grant.mode !== "standing_permission") continue;
    const code = codes.get(grant.scope_id);
    if (!code?.startsWith("sessions_") || grant.record_id || grant.own_records || grant.revoked_at) continue;
    if (grant.expires_at && Date.parse(grant.expires_at) <= now) continue;
    if ((grant.allowed_actions ?? []).includes("create")) return code;
  }
  return null;
}

function note(sessionsFolder, change) {
  const list = uploaded(sessionsFolder);
  change(list);
  writeFileSync(join(sessionsFolder, UPLOADED), JSON.stringify(list, null, 1) + "\n");
}

const answer = content => JSON.parse(content.content[0].text);

/** One OKB function's answer. */
async function call(tools, name, args = {}) {
  const out = answer(await tools.callTool("rpc", { function: name, schema: SCHEMA, args }));
  if (!out.ok) throw new Error(`${name}: ${out.problem}`);
  return out.result;
}

/** Every item of a paged OKB function. */
async function all(tools, name, args = {}) {
  const items = [];
  let cursor;
  do {
    const out = answer(await tools.callTool("rpc", { function: name, schema: SCHEMA, args: cursor ? { ...args, p_cursor: cursor } : args }));
    if (!out.ok) throw new Error(`${name}: ${out.problem}`);
    items.push(...(out.result?.items ?? []));
    cursor = out.result?.next_cursor;
  } while (cursor);
  return items;
}

/** Uploads the copies named and purges the old names. Returns a list of problems. */
export async function upload(sessionsFolder, which, names, tools = null) {
  const problems = [];
  if (!tools) {
    const who = which === "actor" ? actorConnection(sessionsFolder) : connection();
    if (!who) return problems;
    tools = createTools({ ref: who.ref, email: who.email, agentFolder: sessionsFolder });
  }
  let scope;
  try {
    const me = (await call(tools, "okb_get_actor"))?.actor_id;
    scope = sessionsScope(await all(tools, "okb_get_authorisations", { p_executor_id: me }), await all(tools, "okb_get_scopes"), me);
  }
  catch (err) { return [err instanceof Error ? err.message : String(err)]; }
  if (!scope) return problems;
  for (const name of names) {
    const old = name.startsWith("-");
    const file = old ? name.slice(1) : name;
    const out = old
      ? answer(await tools.callTool("call_function", { name: "file-search-purge", body: { bucket: scope, file } }))
      : answer(await tools.callTool("upload_file", { bucket: scope, path: file, file: join(sessionsFolder, file), content_type: "text/markdown", overwrite: true }));
    if (!out.ok) { problems.push(`${file}: ${out.problem}`); continue; }
    note(sessionsFolder, list => {
      if (old) delete list[file];
      else list[file] = statSync(join(sessionsFolder, file)).mtimeMs;
    });
  }
  return problems;
}

const real = path => { try { return realpathSync(path); } catch { return path; } };
if (process.argv[1] && real(fileURLToPath(import.meta.url)) === real(process.argv[1])) {
  const [sessionsFolder, which, ...names] = process.argv.slice(2);
  let problems;
  try { problems = await upload(sessionsFolder, which, names); }
  catch (err) { problems = [err instanceof Error ? err.message : String(err)]; }
  if (problems.length) {
    const at = new Date().toISOString();
    try { appendFileSync(join(sessionsFolder, "upload-problems.log"), problems.map(p => `${at} ${p}\n`).join("")); } catch { /* nowhere to report it */ }
  }
}
