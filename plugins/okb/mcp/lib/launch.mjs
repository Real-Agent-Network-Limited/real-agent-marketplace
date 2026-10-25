// The checks the okb server makes on its connection before it serves a tool: one project, and one
// Supabase Auth user signed in to it. A refusal here is a refusal to start, rather than a tool that
// fails later with a sentence nobody can act on.

/** A reference is the project's own subdomain: twenty lowercase characters and nothing else. */
const PROJECT_REF = /^[a-z0-9]{20}$/;

/** A value, or undefined when empty or left as Claude Code's unfilled `${user_config.…}`. */
export function setting(value) {
  const trimmed = value?.trim();
  return trimmed && !/^\$\{.*\}$/.test(trimmed) ? trimmed : undefined;
}

/**
 * Whether the server may start with this environment, as chooseConnection returns it:
 * `{ ok: true, projectRef }`, `{ ok: true, idle: true }` when no Auth user is named, or
 * `{ ok: false, problem }`. An access token in the environment is never passed on.
 */
export function launchPlan(env = process.env) {
  const ref = setting(env.SUPABASE_PROJECT_REF);
  if (ref && !PROJECT_REF.test(ref)) return { ok: false, problem: `SUPABASE_PROJECT_REF is not a project reference: ${ref}` };
  const { SUPABASE_ACCESS_TOKEN: _dropped, ...rest } = env;
  // After the format check on purpose: no actor named serves no database tools, but a malformed reference refuses.
  if (!setting(env.SUPABASE_AUTH_EMAIL)) return { ok: true, idle: true, env: rest };
  if (!ref) return { ok: false, problem: "The okb plugin needs a project reference, the client's project the person signs in to. Sign in with --folder, or set project_ref in the okb plugin's settings." };
  return { ok: true, projectRef: ref, env: rest };
}
