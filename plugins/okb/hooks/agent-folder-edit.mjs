// Confines the database operator's and the business analyst's Write and Edit to files directly inside the
// agent folder. Refuses any agent's Write and Edit of an actor file; any other agent's other Write and
// Edit go ahead. Reads the tool call from stdin, as Claude Code's PreToolUse hooks receive it. The
// folder is the session's folder when it holds an actor file; otherwise it is the okb plugin's
// agent_folder setting, CLAUDE_PLUGIN_OPTION_AGENT_FOLDER, as the okb server chooses its own. While setup is under way
// in the session's folder, the business analyst's Write and Edit go ahead.
import { lstatSync, realpathSync } from "node:fs";
import { basename, dirname, isAbsolute, resolve } from "node:path";
import { env, stdin, stdout } from "node:process";
import { ACTOR_FILE, readActor } from "../mcp/lib/actor-file.mjs";
import { AGENTS } from "./agent-tools.mjs";
import { SETUP_MARKER, setupOpen } from "../mcp/lib/setup-marker.mjs";

let text = "";
for await (const chunk of stdin) text += chunk;
let call;
try { call = JSON.parse(text); } catch { process.exit(0); }

const deny = reason => {
  stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: reason } }));
  process.exit(0);
};
// The person makes an actor file with the okb plugin's sign-in, never an agent.
if (basename(String(call?.tool_input?.file_path ?? "")).toLowerCase() === ACTOR_FILE)
  deny(`${ACTOR_FILE} names the person a session on its folder signs in as. The person makes it with okb sign-in, given the folder.`);
if (basename(String(call?.tool_input?.file_path ?? "")).toLowerCase() === SETUP_MARKER)
  deny(`${SETUP_MARKER} marks a folder whose setup is under way. Only okb setup writes or removes it.`);
if (!Object.hasOwn(AGENTS, call?.agent_type ?? "")) process.exit(0);
const setting = value => { const t = value?.trim(); return t && !/^\$\{.*\}$/.test(t) ? t : undefined; };
// Windows paths ignore letter case, so there a folder typed in any case is the same folder.
const samePath = (one, other) => process.platform === "win32" ? one.toLowerCase() === other.toLowerCase() : one === other;
const real = path => { try { return realpathSync.native(path); } catch { return null; } };
// While setup is under way in the session's folder, the business analyst's writes go ahead.
if (AGENTS[call.agent_type].setup && setupOpen(real(call.cwd ?? ""))) process.exit(0);

const session = real(call.cwd ?? "");
const found = readActor(session);
if (found && !found.ok) deny(found.problem);
const who = `The ${AGENTS[call.agent_type].name}`;
const folder = found?.folder ?? setting(env.CLAUDE_PLUGIN_OPTION_AGENT_FOLDER);
if (!folder) deny("No agent folder is set for the okb plugin. The person signs in with okb sign-in --folder, which makes the folder the agent folder, or sets agent_folder in the okb plugin's settings.");
const root = real(folder);
if (!root) deny(`The agent folder ${folder} does not exist.`);

const given = String(call.tool_input?.file_path ?? "");
const file = isAbsolute(given) ? given : resolve(call.cwd ?? ".", given);
const name = basename(file);
const parent = resolve(dirname(file));
const inside = samePath(parent, resolve(folder)) || samePath(parent, root) || samePath(real(parent) ?? "", root);
if (!inside || name === "" || name.startsWith(".")) deny(`${given} is not a file directly inside the agent folder, ${folder}. ${who} writes and changes files there only.`);
let named = null;
try { named = lstatSync(file); } catch { /* a new file */ }
if (named?.isSymbolicLink()) deny(`${given} is a link. ${who} writes and changes only files directly inside ${folder}.`);
