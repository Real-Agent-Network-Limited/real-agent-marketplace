#!/usr/bin/env node
// The okb plugin's MCP server over stdio. It signs one person in to their client's Supabase project and
// calls its database functions as them: `whoami`, `rpc`, `call_function`, `upload_file`, `list_files`,
// `download_file` and `read_file`, from lib/tools.mjs, with `update_plugins`, `check_plugins`, which also
// gives what the session's folder holds, and `copy_to_agent_folder`. It also draws and prints pages from what the
// database returns, on files directly inside the agent folder: `draw_graph`, `draw_search`, `draw_board`,
// `draw_state_machine`, `state_machine_payload`, `draw_reference`, `draw_sop`, `report_page`, `print_pdf`,
// `embed_pictures`, `create_workbook`, `edit_workbook`, `copy_samples` and `check_text`, from lib/pages.mjs. `run_code`, from
// lib/code.mjs, runs Python or JavaScript on the agent folder's files, signed in or not.
//
// One folder works in one project, as one person. A session's folder that holds an actor file,
// .okb-actor.json, works as its actor, and is the agent folder. Otherwise the plugin's settings name
// the project, the person and the agent folder. An actor file or a setting that cannot be used stops the
// server with one sentence on stderr, because a server that starts anyway would hand the agent tools
// that are not the person's.
//
// The protocol is newline-delimited JSON-RPC, written directly, so the server needs Node alone.
// Nothing is read from the project at start; each call reads the session, so a missing one costs that
// call only.
import { chooseConnection } from "./lib/choose.mjs";
import { launchPlan, setting } from "./lib/launch.mjs";
import { accountEmail } from "./lib/session.mjs";
import { sessionFolderStatus } from "./lib/session-folder.mjs";
import { createTools as databaseTools, TOOLS as DATABASE_TOOLS } from "./lib/tools.mjs";
import { createTools as pageTools } from "./lib/pages.mjs";
import { createCodeTool } from "./lib/code.mjs";

const SERVER = { name: "okb", version: "0.1.0" };
const DEFAULT_PROTOCOL = "2025-06-18";
// Every OKB function is in the okb schema, the one schema a client's project exposes.
export const SCHEMA = "okb";
const IDLE_NOTICE = "No one is signed in for this folder, so the okb plugin serves only its page tools, run_code and check_plugins. The person signs in with okb sign-in --folder, as the actor skill describes.";

let env, plan;
try { env = chooseConnection(); plan = launchPlan(env); }
catch (err) { plan = { ok: false, problem: err instanceof Error ? err.message : String(err) }; }
if (!plan.ok) {
  process.stderr.write(`[okb] ${plan.problem}\n`);
  process.exit(78);
}

const ref = setting(env.SUPABASE_PROJECT_REF);
// Which Auth user this agent is, so a session saved for another is never used.
const email = accountEmail(setting(env.SUPABASE_AUTH_EMAIL));
// The one folder the person puts files in, which `upload_file` reads from, and the tools read call
// arguments from and write results and pages to. The server runs outside the agent's sandbox.
const agentFolder = setting(env.SUPABASE_AGENT_FOLDER) ?? null;
// whisper.cpp's program and model, for recordings, when they are not where Homebrew puts them.
const whisperSettings = { whisperCli: setting(env.SUPABASE_WHISPER_CLI), whisperModel: setting(env.SUPABASE_WHISPER_MODEL) };

// The session's folder, as Claude Code gives it, and the agent folder the settings name, for check_plugins.
const sessionFolder = setting(process.env.SUPABASE_SESSION_FOLDER) ?? null;
const agentFolders = [setting(process.env.SUPABASE_AGENT_FOLDER)];
const pages = pageTools({ agentFolder });
const database = plan.idle ? null : databaseTools({ ref, email, agentFolder, defaultSchema: SCHEMA, whisperSettings, sessionFolder, agentFolders });
// With no one signed in, check_plugins still gives what the session's folder holds, so a disconnected folder is named.
const CHECK_PLUGINS = DATABASE_TOOLS.find(t => t.name === "check_plugins");
// run_code needs no sign-in for JavaScript, or for Python once this computer holds the runtime.
const code = createCodeTool({ ref: plan.idle ? null : ref, email: plan.idle ? null : email, agentFolder, sessionFolder });
const TOOLS = [...(database?.TOOLS ?? [CHECK_PLUGINS]), ...pages.TOOLS, ...code.TOOLS];
const PAGE_TOOLS = new Set(pages.TOOLS.map(t => t.name));
const CODE_TOOLS = new Set(code.TOOLS.map(t => t.name));

const send = msg => process.stdout.write(JSON.stringify(msg) + "\n");
const reply = (id, result) => send({ jsonrpc: "2.0", id, result });

async function callTool(name, args) {
  if (PAGE_TOOLS.has(name)) return pages.callTool(name, args ?? {});
  if (CODE_TOOLS.has(name)) return code.callTool(name, args ?? {});
  if (database) return database.callTool(name, args ?? {});
  if (name === "check_plugins") {
    const folder = sessionFolderStatus(sessionFolder, { agentFolders });
    return { content: [{ type: "text", text: JSON.stringify({ ok: false, problem: IDLE_NOTICE, ...(folder ? { sessionFolder: folder } : {}) }, null, 2) }] };
  }
  return { content: [{ type: "text", text: JSON.stringify({ ok: false, problem: `${IDLE_NOTICE} ${name} needs a signed-in person.` }, null, 2) }] };
}

async function handle({ id, method, params }) {
  if (method === "initialize")
    return reply(id, { protocolVersion: params?.protocolVersion ?? DEFAULT_PROTOCOL, capabilities: { tools: {} }, serverInfo: SERVER, ...(plan.idle ? { instructions: IDLE_NOTICE } : {}) });
  if (id === undefined) return;
  if (method === "tools/list") return reply(id, { tools: TOOLS });
  if (method === "tools/call") return reply(id, await callTool(params?.name, params?.arguments));
  if (method === "ping") return reply(id, {});
  if (method === "resources/list") return reply(id, { resources: [] });
  if (method === "prompts/list") return reply(id, { prompts: [] });
  send({ jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } });
}

// Calls in flight are counted, so stdin closing never cuts off an answer still on its way.
let buffer = "";
let inFlight = 0;
let ended = false;
// Exit once written output has reached the pipe; exiting at once cuts a large answer short.
const settle = () => { if (ended && inFlight === 0) process.stdout.write("", () => process.exit(0)); };

process.stdin.setEncoding("utf-8");
process.stdin.on("data", async chunk => {
  inFlight += 1;
  buffer += chunk;
  try {
    let nl;
    while ((nl = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, nl).trim();
      buffer = buffer.slice(nl + 1);
      if (!line) continue;
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      try { await handle(msg); }
      catch (err) {
        if (msg?.id !== undefined) send({ jsonrpc: "2.0", id: msg.id, error: { code: -32603, message: err instanceof Error ? err.message : String(err) } });
      }
    }
  } finally {
    inFlight -= 1;
    settle();
  }
});
process.stdin.on("end", () => { ended = true; settle(); });
