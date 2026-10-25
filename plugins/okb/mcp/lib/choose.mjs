// Picks the connection for a session: one project and one person per folder. A session's folder that
// holds an actor file works as that file's actor, with the folder as its agent folder. Otherwise it is
// the connection the okb plugin's settings name. Claude Code starts the server in the session's folder
// and gives it as SUPABASE_SESSION_FOLDER. The chosen settings are returned under the names launch.mjs
// and the server read.
import { realpathSync } from "node:fs";
import { readActorFile } from "./actor-file.mjs";

const setting = value => { const t = value?.trim(); return t && !/^\$\{.*\}$/.test(t) ? t : undefined; };
const real = path => { try { return realpathSync.native(path); } catch { return null; } };

/** The environment for launch.mjs, with the connection the session's folder picks. Throws on an actor file that cannot be used. */
export function chooseConnection(env = process.env) {
  const folder = setting(env.SUPABASE_SESSION_FOLDER) && real(env.SUPABASE_SESSION_FOLDER);
  const actor = folder ? readActorFile(folder) : null;
  if (actor && !actor.ok) throw new Error(actor.problem);
  const out = { ...env };
  // The agent folder is the one folder files are uploaded from; an older upload folder setting is dropped.
  delete out.SUPABASE_SESSION_FOLDER;
  delete out.SUPABASE_UPLOAD_FOLDER;
  if (actor) {
    return Object.assign(out, {
      SUPABASE_PROJECT_REF: actor.value.project_ref,
      SUPABASE_AUTH_EMAIL: actor.value.auth_email,
      SUPABASE_AGENT_FOLDER: folder,
      SUPABASE_CONNECTION: "actor file",
    });
  }
  for (const name of ["PROJECT_REF", "AUTH_EMAIL", "AGENT_FOLDER"]) out[`SUPABASE_${name}`] = env[`SUPABASE_${name}`] ?? "";
  out.SUPABASE_CONNECTION = "settings";
  return out;
}
