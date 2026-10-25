// A workflow plugin's access.json, as the add-staff skill reads it and publish-plugin.mjs checks it before a
// release: the workflow's own scope, each role that works in the workflow with its grants in OKB, and the roles
// that read the workflow plugin's own scope, plugins_<workflow>, where its releases are.
//
//   node access-json.mjs <access.json> <plugin name>   prints each problem, and exits 1 with any
//
// The format, with every field required:
//   {
//     "workflow": "<the plugin's name, as its plugin.json gives it>",
//     "scope": { "code": "<scope code>", "display_name": "<scope name>", "description": "<what it holds>" },
//     "roles": {
//       "<role>": { "description": "<who holds it, in plain words>",
//                   "grants": [ { "scope": "<code>", "record_kinds": [...], "actions": [...], "own_records": <true|false> } ] }
//     },
//     "plugin_readers": [ "<role>", ... ]
//   }
// A grant is as an access template in OKB gives one, as okb_get_access_templates reads it, and as
// okb_grant_permission issues it. plugin_readers names each role whose people install the workflow's plugin:
// add-staff gives each of them PLUGIN_READ_GRANT in the plugin's scope, and okb sync installs the plugin only
// for a person whose grants reach that scope.
import { readFileSync, realpathSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const KINDS = ["activity", "decision", "model", "evidence"];
export const ACTIONS = ["read", "create", "edit", "start", "hold", "complete", "reopen", "cancel", "decide", "delete"];
/** The scopes every OKB holds. A role may be given work in these beside its workflow's own scope, never in plugins. */
export const KEPT_SCOPES = ["general", "routines", "reference", "plugins", "administration"];
/** A workflow plugin's own scope, where its releases are: plugins_ and its name, each hyphen an underscore, as okb sync and publish-plugin.mjs name it. */
export const pluginScope = workflow => `plugins_${String(workflow).replaceAll("-", "_")}`;
/** The grant add-staff gives each person of a role plugin_readers names, in the workflow plugin's scope. */
export const PLUGIN_READ_GRANT = { record_kinds: ["evidence"], actions: ["read"], own_records: false };
const CODE = /^[a-z][a-z0-9_]{0,62}$/;
const ROLE = /^[a-z][a-z0-9_]{0,62}$/;
const text = value => typeof value === "string" && value.trim().length > 0;
const keys = (value, wanted) => value && typeof value === "object" && !Array.isArray(value) && Object.keys(value).sort().join(",") === [...wanted].sort().join(",");

/** Each problem with an access.json's value, as a sentence, or [] when add-staff can use it. */
export function checkAccess(value, plugin) {
  const problems = [];
  if (!keys(value, ["workflow", "scope", "roles", "plugin_readers"])) return ["access.json holds exactly workflow, scope, roles and plugin_readers."];
  if (value.workflow !== plugin) problems.push(`workflow is ${JSON.stringify(value.workflow)}, and the plugin is ${plugin}.`);
  const scope = value.scope;
  if (!keys(scope, ["code", "display_name", "description"])) problems.push("scope holds exactly code, display_name and description.");
  else {
    if (!CODE.test(String(scope.code))) problems.push(`scope.code, ${JSON.stringify(scope.code)}, is not lower case letters, digits and underscores, starting with a letter.`);
    if (KEPT_SCOPES.includes(scope.code) || String(scope.code).startsWith("sessions_") || String(scope.code).startsWith("plugins_"))
      problems.push(`scope.code, ${scope.code}, is a scope every OKB keeps for itself; a workflow has a scope of its own.`);
    if (!text(scope.display_name) || !text(scope.description)) problems.push("scope's display_name and description are written out.");
  }
  const roles = value.roles;
  if (!roles || typeof roles !== "object" || Array.isArray(roles) || !Object.keys(roles).length) return [...problems, "roles names at least one role."];
  for (const [name, role] of Object.entries(roles)) {
    const at = `Role ${name}`;
    if (!ROLE.test(name)) problems.push(`${at}: its name is not lower case letters, digits and underscores, starting with a letter.`);
    if (!keys(role, ["description", "grants"])) { problems.push(`${at} holds exactly description and grants.`); continue; }
    if (!text(role.description)) problems.push(`${at} has no description.`);
    if (!Array.isArray(role.grants) || !role.grants.length) { problems.push(`${at} has no grant.`); continue; }
    role.grants.forEach((grant, i) => {
      const g = `${at}, grant ${i + 1}`;
      if (!keys(grant, ["scope", "record_kinds", "actions", "own_records"])) { problems.push(`${g} holds exactly scope, record_kinds, actions and own_records.`); return; }
      if (grant.scope !== scope?.code && !["general", "routines", "reference"].includes(grant.scope))
        problems.push(`${g} is in ${JSON.stringify(grant.scope)}: a role works in its workflow's scope, ${scope?.code}, and in general, routines or reference alone.`);
      if (!Array.isArray(grant.record_kinds) || !grant.record_kinds.length || grant.record_kinds.some(k => !KINDS.includes(k)))
        problems.push(`${g}'s record_kinds are some of ${KINDS.join(", ")}.`);
      if (!Array.isArray(grant.actions) || !grant.actions.length || grant.actions.some(a => !ACTIONS.includes(a)))
        problems.push(`${g}'s actions are some of ${ACTIONS.join(", ")}.`);
      if (typeof grant.own_records !== "boolean") problems.push(`${g}'s own_records is true or false.`);
      else if (grant.own_records && Array.isArray(grant.actions)) {
        if (!grant.actions.includes("read")) problems.push(`${g} is limited to own records, so it carries read.`);
        if (grant.actions.includes("delete")) problems.push(`${g} is limited to own records, so it carries no delete.`);
      }
      if (new Set(grant.actions ?? []).size !== (grant.actions ?? []).length || new Set(grant.record_kinds ?? []).size !== (grant.record_kinds ?? []).length)
        problems.push(`${g} names an action or a record kind twice.`);
    });
    if (!role.grants.some(g => g?.scope === scope?.code)) problems.push(`${at} has no grant in its workflow's scope, ${scope?.code}.`);
  }
  const readers = value.plugin_readers;
  if (!Array.isArray(readers) || !readers.length) problems.push(`plugin_readers names at least one role, whose people install the plugin from ${pluginScope(plugin)}.`);
  else {
    for (const name of readers) if (!Object.hasOwn(roles, name)) problems.push(`plugin_readers names ${JSON.stringify(name)}, which is not one of the roles.`);
    if (new Set(readers).size !== readers.length) problems.push("plugin_readers names a role twice.");
  }
  return problems;
}

const real = file => { try { return realpathSync(file); } catch { return file; } };
if (process.argv[1] && real(fileURLToPath(import.meta.url)) === real(resolve(process.argv[1]))) {
  const [file, plugin] = process.argv.slice(2);
  if (!file || !plugin) { process.stderr.write("Usage: node access-json.mjs <access.json> <plugin name>\n"); process.exit(2); }
  let value;
  try { value = JSON.parse(readFileSync(file, "utf8")); } catch (err) { process.stdout.write(`${file} is not readable JSON: ${err.message}\n`); process.exit(1); }
  const problems = checkAccess(value, plugin);
  for (const p of problems) process.stdout.write(`${p}\n`);
  process.exit(problems.length ? 1 : 0);
}
