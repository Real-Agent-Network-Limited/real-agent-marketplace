// Keeps the database operator and the business analyst to the okb plugin's tools, every Claude in Chrome tool outside
// Supabase's pages, for the database operator every connector and plugin the person has
// but those REFUSED_SERVERS and SUPABASE_TOOLS name, and the built-in tools in BUILT_IN, beside each agent's disallowedTools. Every other MCP tool is refused,
// the Supabase connector's among them, since it reaches past OKB's grants. Read reads a skill's own files, inside the
// installed plugins' folder, and the files in each folder added to the session. Glob and Grep search those added folders
// alone, and copy_to_agent_folder copies a file from one into the agent folder. For run_code, from any agent or session,
// on any server whose tool is named run_code, it saves those folders for the session's folder, and run_code reads them alone. Reads the tool
// call from stdin, as Claude Code's PreToolUse hooks receive it; any other agent's calls go ahead. The business analyst is
// held in every folder, before, during and after setup, since okb setup --owner does setup's work on the owner's computer.
// one-issue.mjs, agent-folder-edit.mjs and connector-agreed.mjs take their agents from AGENTS here.
//
// A connector's tools go ahead only on its own server, and only once the person has agreed in the session. The first
// call to each connector in a session is put to the person in Claude Code's permission prompt, with
// permissionDecision "ask". connector-agreed.mjs, a PostToolUse hook, which runs only once a call has run, so once the
// person allowed it, records the connector as agreed for the session, and its later calls go ahead.
//
// Claude Code names no added folder in a hook's input. The session's transcript, at transcript_path, holds them in its
// environment attachment, written with the session's first message: {"type": "attachment", "attachment": {"type":
// "environment", "snapshot": {"additionalWorkingDirectories": ["/Users/you/Downloads"]}}}. A folder added later in the
// session is in no attachment, so the agent reads it only in a new session.
//
// A desktop connector's server is an id. The transcript's deferred_tools_delta and prompt_snapshot attachments list each
// id's tools from the session's first turn, so the hook knows an id as Supabase's, or as Gmail's or another named
// connector's, before any call to it. The marks a Supabase tool's call puts on its id stay.
//
// Every agent and session is refused the calls loginCall names, which open or save a shared login's password.
//
// The hook changes no call's input.
import { closeSync, openSync, readFileSync, readSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, resolve, sep } from "node:path";
import { argv, env, stdin, stdout } from "node:process";
import { saveSessionFolders } from "../mcp/lib/code.mjs";
import { fileURLToPath } from "node:url";

// The okb server's tools, as Claude Code names a plugin's server: plugin_<plugin>_<server>.
export const SERVER = "plugin_okb_okb";
export const OKB = ["whoami", "rpc", "call_function", "upload_file", "list_files", "download_file", "read_file",
  "draw_graph", "draw_search", "draw_board", "draw_state_machine", "state_machine_payload", "draw_reference", "draw_sop", "report_page", "print_pdf",
  "embed_pictures", "check_text", "update_plugins", "check_plugins", "copy_to_agent_folder", "create_workbook", "edit_workbook", "copy_samples", "run_code",
  "invite_person"];
// The okb tools only the business analyst, the administrators' agent, uses: invite_person, which adds a person through the
// okb-invite hosted function. call_function naming okb-invite is the same call, and is the business analyst's alone too, as
// is call_function naming password-reset, which gives a person's reset code.
export const ADMIN_ONLY = { tools: ["invite_person"], functions: ["okb-invite", "password-reset"], agent: "business-analyst:business-analyst" };

// Claude in Chrome's server, the same in a terminal and in the desktop app. Both agents may use every one of its tools. They
// open no Supabase address with navigate, alone or inside browser_batch, work in no tab last seen at a Supabase address or
// never seen, and make no browser_batch action after one that can change a page. chrome-tabs.mjs, a PostToolUse hook, keeps
// each tab's last seen address.
export const CHROME = "claude-in-chrome";
export const CHROME_NAVIGATE_REFUSED = "opens no Supabase address in Chrome, and only web addresses.";
export const CHROME_TAB_REFUSED = "works in no Supabase page in Chrome.";
export const CHROME_TAB_UNSEEN = "works only in a Chrome tab whose address it has seen. Call tabs_context_mcp first, then make this call again.";
export const CHROME_TAB_UNNAMED = "names the Chrome tab it works in, by its tabId, in each call and each browser_batch action, except tabs_context_mcp and tabs_create_mcp.";
export const CHROME_STALE = "lists Chrome's tabs with tabs_context_mcp after each call that can change a page, before the next call, since a page can move after the call returns.";
export const CHROME_UPLOAD_REFUSED = "sends no file from this computer to a web page with Claude in Chrome. Upload a file to the knowledge base with upload_file.";
// The Claude in Chrome tools that send a file from this computer to a page. They stay refused: a file anywhere on the
// computer could go to any site.
const CHROME_UPLOADS = ["file_upload", "upload_image"];
// The Claude in Chrome tools that name no tab: the tab list, and a new tab, whose result shows it.
const CHROME_NO_TAB = ["tabs_context_mcp", "tabs_create_mcp"];
export const CHROME_BATCH_REFUSED = "makes no browser_batch action after one that can change a page, such as navigate, javascript_tool, form_input, or a click, key or typing in computer. Make the later actions as calls of their own.";
// The addresses Claude in Chrome may not open: Supabase's dashboard and every project's API, which reach past OKB's grants.
const CHROME_REFUSED = /^([\w-]+\.)*(supabase\.com|supabase\.co|supabase\.in)$/i;

/** Whether Claude in Chrome may open the address: any web address but Supabase's. A trailing dot, as in
 * supabase.com., names the same host, so it is stripped first. */
export function chromeUrlAllowed(url) {
  try {
    const { protocol, hostname } = new URL(String(url));
    return (protocol === "https:" || protocol === "http:") && !CHROME_REFUSED.test(hostname.replace(/\.+$/, ""));
  } catch { return false; }
}

/** Whether a browser_batch's navigate actions each open an address chromeUrlAllowed allows. */
export function chromeBatchAllowed(input = {}) {
  const actions = Array.isArray(input?.actions) ? input.actions : [];
  return actions.every(a => String(a?.name ?? "").replace(/^mcp__claude-in-chrome__/, "") !== "navigate" || chromeUrlAllowed(a?.input?.url));
}

// The Claude in Chrome tools that leave a page as it is, and computer's actions that do. Every other action may move a tab.
const CHROME_STILL = ["read_page", "get_page_text", "find", "tabs_context_mcp", "read_console_messages", "read_network_requests"];
const COMPUTER_STILL = ["screenshot", "wait", "scroll", "scroll_to", "zoom", "hover"];

/** Whether a browser_batch makes no action after one that can change a page. A script or a click on one tab can move
 * another, so a change counts for every tab. */
export function chromeBatchOrdered(input = {}) {
  let changed = false;
  for (const a of Array.isArray(input?.actions) ? input.actions : []) {
    if (changed) return false;
    const name = String(a?.name ?? "").replace(/^mcp__claude-in-chrome__/, "");
    changed = !(CHROME_STILL.includes(name) || (name === "computer" && COMPUTER_STILL.includes(a?.input?.action)));
  }
  return true;
}

/** The tab ids a Chrome call names: its own tabId, and each tabId in a browser_batch's actions. */
export function chromeTabIds(input = {}) {
  const ids = [input?.tabId, ...(Array.isArray(input?.actions) ? input.actions.map(a => a?.input?.tabId) : [])];
  return ids.filter(id => id !== undefined && id !== null).map(String);
}

const chromeName = name => String(name ?? "").replace(/^mcp__claude-in-chrome__/, "");

/** Whether a Chrome call names its tab, as a whole number, in the call and in each browser_batch action: every tool but
 * tabs_context_mcp and tabs_create_mcp acts on a tab, and one it does not name is one the tab note cannot check. */
export function chromeTabsNamed(tool, input = {}) {
  const named = id => /^[1-9][0-9]*$/.test(String(id ?? ""));
  if (tool === "browser_batch") {
    const actions = Array.isArray(input?.actions) ? input.actions : [];
    return actions.length > 0 && actions.every(a => CHROME_NO_TAB.includes(chromeName(a?.name)) || named(a?.input?.tabId));
  }
  return CHROME_NO_TAB.includes(tool) || named(input?.tabId);
}

/** Whether a Chrome call, or any of a browser_batch's actions, sends a file from this computer. */
export function chromeUploads(tool, input = {}) {
  return CHROME_UPLOADS.includes(tool)
    || (tool === "browser_batch" && (Array.isArray(input?.actions) ? input.actions : []).some(a => CHROME_UPLOADS.includes(chromeName(a?.name))));
}

/** Whether a Chrome call can change a page: every call but a read, the tab list, a new tab and computer's still actions. A
 * page can move after the call returns, so the tab note is stale after it until tabs_context_mcp. */
export function chromeChanges(tool, input = {}) {
  const changes = (name, action) => !(CHROME_STILL.includes(name) || name === "tabs_create_mcp" || (name === "computer" && COMPUTER_STILL.includes(action)));
  if (tool === "browser_batch") return (Array.isArray(input?.actions) ? input.actions : []).some(a => changes(chromeName(a?.name), a?.input?.action));
  return changes(tool, input?.action);
}

/** Each tab's id and address in a Claude in Chrome result's Tab Context block, as { id: url }. The block is a text block of
 * its own that starts with "Tab Context:", and its lines read `• tabId 729764785: "Example Domain" ("https://example.com/")`.
 * Only the last such block counts, so a page's own text cannot stand in for it. A tab listed twice keeps a Supabase
 * address over any other. */
export function chromeTabsSeen(response) {
  const texts = typeof response === "string" ? [response]
    : Array.isArray(response) ? response.map(b => typeof b === "string" ? b : b?.type === "text" ? b.text : "") : [];
  const block = texts.filter(t => typeof t === "string" && /^\s*Tab Context:\n/.test(t)).pop();
  const seen = {};
  for (const m of (block ?? "").matchAll(/^\s*•\s*tabId (\d+): .*\("([^"\n]*)"\)\s*$/gm))
    if (!chromeTabRefused(seen[m[1]])) seen[m[1]] = m[2];
  return seen;
}

/** The tab note before a Chrome call the hook lets through. A call that can change a page makes the note stale, and counts
 * one more change in gen, before it runs, so a call that fails, or one running beside it, leaves the note stale.
 * tabs_context_mcp records in listings, by its own tool_use_id, the changes counted when its list began; the newest 20 are
 * kept. */
export function chromeTabsBefore(tabs, tool, input = {}, callId = null) {
  const gen = Number.isInteger(tabs.gen) ? tabs.gen : 0;
  if (chromeChanges(tool, input)) return { ...tabs, stale: true, gen: gen + 1 };
  if (tool === "tabs_context_mcp" && callId) return { ...tabs, listings: Object.fromEntries([...Object.entries(tabs.listings ?? {}), [String(callId), gen]].slice(-20)) };
  return tabs;
}

/** The tab note after a Chrome result: each tab's address as the result shows it. A tab noted at a Supabase address keeps it,
 * unless the result is tabs_context_mcp's, which reads each tab's address from Chrome itself. tabs_context_mcp's list
 * replaces the note's addresses, so a tab it leaves out is unseen again, and clears stale only when it lists a tab and no
 * call that can change a page began after the list did. Any other call that can change a page leaves the note stale. */
export function chromeTabsAfter(tabs, seen, tool, input = {}, callId = null) {
  const { stale, gen, listings, ...addresses } = tabs;
  const meta = { ...(stale ? { stale } : {}), ...(Number.isInteger(gen) ? { gen } : {}), ...(listings ? { listings } : {}) };
  if (tool === "tabs_context_mcp") {
    // This list's own start, by its tool_use_id: an older list, or one the hook never saw begin, clears nothing.
    const started = callId ? listings?.[String(callId)] : undefined;
    const rest = Object.fromEntries(Object.entries(listings ?? {}).filter(([id]) => id !== String(callId)));
    if (!Object.keys(seen).length) return { ...tabs, ...(listings ? { listings: rest } : {}) };
    const next = { ...seen, ...(Number.isInteger(gen) ? { gen } : {}), ...(Object.keys(rest).length ? { listings: rest } : {}) };
    if (started !== (Number.isInteger(gen) ? gen : 0)) next.stale = true;
    return next;
  }
  const next = { ...addresses };
  for (const [id, url] of Object.entries(seen)) if (!chromeTabRefused(addresses[id])) next[id] = url;
  if (chromeChanges(tool, input)) meta.stale = true;
  return { ...next, ...meta };
}

/** Each tab's last seen address, kept in a file named for the session, as { id: url }. */
export function chromeTabs(session, dir = tmpdir()) {
  const file = join(dir, `okb-chrome-tabs-${String(session).replace(/[^\w-]/g, "")}.json`);
  let tabs = {};
  try { tabs = JSON.parse(readFileSync(file, "utf8")) ?? {}; } catch {}
  return { tabs, file };
}

/** Changes the session's tab note under its lock, so two hooks never write over each other: change takes the note as it is
 * now and gives the note to save, or null to save nothing. A lock older than 10 seconds is a hook that stopped, and is
 * removed. Gives the note saved, or null when the lock could not be taken within 2 seconds. */
export function changeChromeTabs(session, change, dir = tmpdir()) {
  const { file } = chromeTabs(session, dir);
  const lock = `${file}.lock`;
  let fd = null;
  for (let tries = 0; tries < 100 && fd === null; tries++) {
    try { fd = openSync(lock, "wx", 0o600); }
    catch (err) {
      if (err.code !== "EEXIST") throw err;
      try { if (Date.now() - statSync(lock).mtimeMs > 10_000) { rmSync(lock, { force: true }); continue; } } catch {}
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 20);
    }
  }
  if (fd === null) return null;
  try {
    const { tabs } = chromeTabs(session, dir);
    const next = change(tabs);
    if (next && next !== tabs) saveChromeTabs(file, next);
    return next ?? tabs;
  } finally { closeSync(fd); rmSync(lock, { force: true }); }
}

/** Saves the session's tab note, readable by the person alone, as a new file renamed into place. */
export function saveChromeTabs(file, tabs) {
  const part = `${file}.${process.pid}`;
  writeFileSync(part, JSON.stringify(tabs), { mode: 0o600 });
  renameSync(part, file);
}

/** Whether a tab's last seen address is Supabase's. An address that is not a web address, such as chrome://newtab/, goes
 * ahead. The hook refuses a tab never seen with CHROME_TAB_UNSEEN. */
export function chromeTabRefused(url) {
  if (typeof url !== "string") return false;
  try { const { hostname } = new URL(url); return CHROME_REFUSED.test(hostname.replace(/\.+$/, "")); } catch { return false; }
}

// Every connector and plugin the person has is the database operator's, as decision 2.34 gives it, to ingest from and to
// work in, once the person has agreed in the session. These servers are never its: those that reach the database past
// OKB's grants, and those that drive the computer, a browser or the app. The okb plugin's own server and Claude in Chrome
// are held by their own rules above.
export const REFUSED_SERVERS = [/supabase/i, /postgres|pgadmin|beekeeper/i, /^plugin_okb[-_]/, /^terminal$/, /^computer-use$/,
  /^Claude_Browser$/, /playwright/i, /^Claude_Code_iOS_Simulator$/, /^ccd_/, /^scheduled-tasks$/, /^rea$/];
// Real Agent's connector, the one that draws the home card, the Dashboard button, the approval card, the graph reader card and the Login card,
// known by its tools' names on any server, since in the desktop app its server is an id. Both agents call them with no agreement asked, and a
// call to one records no agreement for the rest of its server.
export const REAL_AGENT = ["show_home", "show_approval", "show_graph_reader", "show_logins"];
// The tools only a card calls, for its page and its own tools. Claude keeps them from the model, and a card's own calls
// never pass this hook (seen in a live session: the hook saw show_home, and none of the card's card_page and card_call).
// So both agents are refused them by name on any server, as a second layer to Claude's, whether a card's tool is
// reached through card_call or called by its own name.
// The list holds every tool the connector registers with appTool, in any file of workers/connector/src, and hook.test.mjs
// checks it against that file.
export const CARD_ONLY = ["card_page", "card_call", "card_state", "save_version", "home_state", "task_list", "task_save", "task_open", "task_state", "run_call", "card_find_records", "card_record", "graph_reader_save", "graph_reader_off",
  "logins_list", "login_open", "login_save", "login_remove"];
// Real Agent's connector's record, file and routine tools and the records card, for claude.ai and the phone, which load
// no plugins. This hook is the okb plugin's, so a session it runs in has the plugin's own server. Its rpc, list_files and
// file tools reach the same records and files, and the workflow plugins okb sync installs hold the same routines. Both
// agents are refused these names on any server but the okb plugin's own, so they keep to the plugin's tools in Claude
// Code. Each name starts okb, so another connector's guide, list_files or show_records is never refused.
export const CONNECTOR_RECORDS = ["okb", "okb_list_files", "okb_file_search", "okb_file_link", "okb_file_upload_link", "okb_guide", "okb_help", "okb_routines", "okb_routine", "okb_show_records"];

// The calls that open or save a shared login's password, refused to every agent and every session: the okb plugin's and the
// supabase plugin's rpc of okb_open_login or okb_save_login, and their call_function whose body names login_open, login_save
// or card_call; the okb tool of Real Agent's connector naming either function; the connector's login_open and login_save,
// and its card_call of either; and a Bash or PowerShell command, an execute_sql or apply_migration query and an Agent prompt
// that match LOGIN_TEXT. A built-in tool is passed by its own name, with no server. A person opens a login on the Login card.
export const LOGIN_REFUSED = "A shared login's password is opened, typed and generated on the Login card alone. Show the Login card with Real Agent's connector's show_logins.";
const LOGIN_FUNCTIONS = ["okb_open_login", "okb_save_login"];
const LOGIN_TOOLS = ["login_open", "login_save"];
export const LOGIN_TEXT = /okb_(open|save)_login|login_(open|save)|decrypted_secret|vault\./i;
export function loginCall(server, tool, input = {}) {
  const fn = String(input?.function ?? "").trim().toLowerCase().replace(/^"?okb"?\./, "").replaceAll('"', "");
  const plugin = server === SERVER || server === "plugin_supabase_supabase";
  if (plugin && tool === "rpc" && LOGIN_FUNCTIONS.includes(fn)) return true;
  if (plugin && tool === "call_function" && /login_open|login_save|card_call/.test(JSON.stringify(input?.body ?? null))) return true;
  if (server && tool === "okb" && LOGIN_FUNCTIONS.includes(fn)) return true;
  if (server && (LOGIN_TOOLS.includes(tool) || (tool === "card_call" && LOGIN_TOOLS.includes(input?.name)))) return true;
  if (!server && ["Bash", "PowerShell"].includes(tool)) return LOGIN_TEXT.test(String(input?.command ?? ""));
  if (["execute_sql", "apply_migration"].includes(tool)) return LOGIN_TEXT.test(String(input?.query ?? ""));
  if (!server && ["Agent", "Task"].includes(tool)) return LOGIN_TEXT.test(String(input?.prompt ?? ""));
  return false;
}

/** Whether the tool is one of Real Agent's connector's record, file or routine tools, on a server other than the okb plugin's. */
export const connectorRecord = (server, tool) => server !== SERVER && CONNECTOR_RECORDS.includes(tool);

/** Whether the tool, exactly mcp__<server>__<tool>, is one of Real Agent's connector's, by its tool's name. */
export function realAgentTool(toolName) {
  const parts = String(toolName).split("__");
  return parts.length === 3 && parts[0] === "mcp" && parts[1] !== "" && REAL_AGENT.includes(parts[2]);
}

// The Supabase connector's tools, refused on any server, since in the desktop app the connector's server is an id. Each
// call to one also marks its id as Supabase's for the session, and every tool on a marked id is refused. search_docs, its
// one tool that reads only Supabase's own documentation, is left out, since other connectors share the name.
export const SUPABASE_TOOLS = ["execute_sql", "apply_migration", "list_tables", "list_extensions", "list_migrations",
  "get_advisors", "get_logs", "query_logs", "get_project_url", "get_publishable_keys", "get_anon_key", "generate_typescript_types",
  "list_edge_functions", "get_edge_function", "deploy_edge_function", "create_branch", "list_branches", "delete_branch",
  "merge_branch", "reset_branch", "rebase_branch", "list_projects", "get_project", "create_project", "pause_project",
  "restore_project", "list_organizations", "get_organization", "get_cost", "confirm_cost"];

// What the person calls a connector, by its server's name in a terminal session or, for a desktop id, by a tool only it
// has. A plugin's server, plugin_<plugin>_<server>, is called by its plugin. Any other server is called by its name.
const NAMED = [
  { label: "Google Calendar", names: ["claude_ai_Google_Calendar"], own: ["list_calendars", "list_events", "suggest_time", "respond_to_event"] },
  { label: "Google Drive", names: ["claude_ai_Google_Drive"], own: ["list_recent_files", "get_file_permissions", "read_file_content", "download_file_content"] },
  { label: "Google Sheets", names: ["claude_ai_Google_Sheets"], own: ["get_spreadsheet", "get_values", "append_values"] },
  { label: "Gmail", names: ["claude_ai_Gmail"], own: ["search_threads", "get_thread", "list_labels", "list_drafts"] },
  { label: "Slack", names: ["claude_ai_Slack"], own: ["slack_read_channel", "slack_read_thread", "slack_search_public", "slack_send_message"] },
  { label: "Microsoft 365", names: ["claude_ai_Microsoft_365"], own: ["outlook_email_search", "outlook_calendar_search", "sharepoint_search"] },
];

// A connector's server in the desktop app: an id for it in place of its name.
const DESKTOP_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** What the prompt calls the server, from its name or, for a desktop id, the connector the session's tool list shows it to
 * be, or the tool called on it. */
export function labelOf(server, tool, names = {}) {
  if (DESKTOP_ID.test(server) && names[server]) return `${names[server]} connector`;
  const named = NAMED.find(c => c.names.includes(server)) ?? (DESKTOP_ID.test(server) ? NAMED.find(c => c.own.includes(tool)) : null);
  if (named) return `${named.label} connector`;
  const plugin = /^plugin_([^_]+)_/.exec(server);
  if (plugin) return `${plugin[1]} plugin`;
  return DESKTOP_ID.test(server) ? `connector ${server}` : `${server.replace(/^claude_ai_/, "").replace(/_/g, " ")} connector`;
}

/** The connector or plugin server the tool is on, as the key the session agrees to, given the desktop ids the session has
 * marked as Supabase's, or null for the okb server, Claude in Chrome and every server or tool the operator never uses. */
export function connectorOf(server, tool, marked = {}) {
  if (!server || server === SERVER || server === CHROME) return null;
  if (REFUSED_SERVERS.some(r => r.test(server)) || SUPABASE_TOOLS.includes(tool) || (marked.supabase ?? []).includes(server)) return null;
  // Code runs only in the okb plugin's own run_code, which reads only the agent folder and the folders added to the session.
  if (tool === "run_code") return null;
  if (REAL_AGENT.includes(tool)) return null;
  return server;
}

/** The marks this call puts on a desktop id: Supabase's, when the tool is one of its own. */
export function marksFor(server, tool) {
  return DESKTOP_ID.test(server) && SUPABASE_TOOLS.includes(tool) ? ["supabase"] : [];
}

// The Supabase connector's tools that no other connector has. A desktop id whose tool list holds them all is Supabase's.
export const SUPABASE_OWN = ["execute_sql", "apply_migration", "deploy_edge_function"];

/** Each desktop id's tools in the transcript's deferred_tools_delta attachments, and in its prompt_snapshot attachments,
 * which list the tools loaded from the start, read from the byte offset given, as { servers: { id: [tool, ...] }, offset },
 * offset being where the next read starts. Each line is parsed, so a message's text that quotes one counts for nothing.
 * Null when the transcript cannot be read. */
export function listedServers(transcript, from = 0) {
  let fd;
  try { fd = openSync(String(transcript), "r"); } catch { return null; }
  const servers = {};
  let offset = from;
  try {
    const part = Buffer.alloc(1 << 20);
    let rest = Buffer.alloc(0), read;
    while ((read = readSync(fd, part, 0, part.length, offset + rest.length)) > 0) {
      const chunk = Buffer.concat([rest, part.subarray(0, read)]);
      const last = chunk.lastIndexOf(10);
      if (last < 0) { rest = chunk; continue; }
      for (const line of chunk.subarray(0, last).toString("utf8").split("\n")) {
        if (!line.includes('"deferred_tools_delta"') && !line.includes('"prompt_snapshot"')) continue;
        let entry;
        try { entry = JSON.parse(line); } catch { continue; }
        const kind = entry?.type === "attachment" ? entry.attachment?.type : null;
        if (kind !== "deferred_tools_delta" && kind !== "prompt_snapshot") continue;
        const names = kind === "prompt_snapshot"
          ? (Array.isArray(entry.attachment.tools) ? entry.attachment.tools : []).map(t => t?.name)
          : [...(entry.attachment.addedNames ?? []), ...(entry.attachment.readdedNames ?? [])];
        for (const name of names) {
          const [mcp, server = "", ...tool] = String(name).split("__");
          if (mcp !== "mcp" || !DESKTOP_ID.test(server) || !tool.length) continue;
          (servers[server] ??= []).push(tool.join("__"));
        }
      }
      offset += last + 1;
      rest = chunk.subarray(last + 1);
    }
  } catch { return null; } finally { closeSync(fd); }
  return { servers, offset };
}

/** What the listed desktop ids are: { supabase: [ids] } for each whose tools hold SUPABASE_OWN, and names, each id
 * whose tools hold all of a named connector's own tools, with that connector's label. */
export function listedMarks(servers) {
  const marks = { supabase: [], names: {} };
  for (const [server, tools] of Object.entries(servers)) {
    if (SUPABASE_OWN.every(t => tools.includes(t))) marks.supabase.push(server);
    const named = NAMED.find(c => c.own.every(t => tools.includes(t)));
    if (named) marks.names[server] = named.label;
  }
  return marks;
}

/** The session's connector state, kept in a file named for the session where the agents cannot write: { marked: { supabase:
 * [ids] }, agreed: [connector keys], names: { id: label }, listed: { transcript, offset } }, names and listed only once the
 * transcript's tool lists have been read. */
export function connectorState(session, dir = tmpdir()) {
  const file = join(dir, `okb-connectors-${String(session).replace(/[^\w-]/g, "")}.json`);
  let state = {};
  try { state = JSON.parse(readFileSync(file, "utf8")) ?? {}; } catch {}
  return { marked: state.marked ?? {}, agreed: Array.isArray(state.agreed) ? state.agreed : [], names: state.names ?? {}, listed: state.listed ?? null, file,
    save(next) {
      const names = next.names ?? this.names, listed = next.listed ?? this.listed;
      writeFileSync(file, JSON.stringify({ marked: next.marked ?? this.marked, agreed: next.agreed ?? this.agreed,
        ...(Object.keys(names).length ? { names } : {}), ...(listed ? { listed } : {}) }), { mode: 0o600 });
    } };
}

// The agent_type Claude Code gives each agent, and what its refusals call it.
// The database operator alone uses the person's connectors and plugins, as decision 2.34 gives it.
export const AGENTS = {
  "real-agent:database-operator": { name: "database operator", connectors: true },
  "business-analyst:business-analyst": { name: "business analyst", connectors: false },
};

// The built-in tools both agents use. Any other, such as one a later Claude Code adds, is refused. Read, Glob and Grep
// reach only the folders below.
// Artifact publishes a checked page on the person's own Claude account, private until they share it, and ArtifactData
// reads and updates that page's saved data. A session that starts either agent gets its answer through SubagentHandback.
// PowerShell and the desktop app's update_plan are in each agent's disallowedTools, and refused here too.
const BUILT_IN = ["Skill", "Write", "Edit", "WebSearch", "WebFetch", "ToolSearch", "ListPlugins", "Read", "Glob", "Grep", "Artifact", "ArtifactData", "SubagentHandback"];

// The installed plugins' folder: ~/.claude/plugins/cache/real-agent, three folders above this hook in
// cache/real-agent/okb/<version>/hooks. A skill's own files, such as its references, are there.
export const PLUGINS = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

/** The folders added to the session, from the first environment attachment in its transcript, which Claude Code writes
 * with the first message. The transcript is read a part at a time up to that line. Each line is parsed, so a message's
 * text that quotes one counts for nothing. None when the transcript cannot be read or holds no such line. */
export function addedFolders(transcript) {
  let fd;
  try { fd = openSync(String(transcript), "r"); } catch { return []; }
  try {
    const part = Buffer.alloc(1 << 16);
    let rest = "", read;
    while ((read = readSync(fd, part, 0, part.length, null)) > 0 || rest) {
      const text = rest + (read > 0 ? part.toString("utf8", 0, read) : "\n");
      const lines = text.split("\n");
      rest = read > 0 ? lines.pop() : "";
      for (const line of lines) {
        if (!line.includes('"environment"')) continue;
        let entry;
        try { entry = JSON.parse(line); } catch { continue; }
        if (entry?.type !== "attachment" || entry.attachment?.type !== "environment") continue;
        const added = entry.attachment.snapshot?.additionalWorkingDirectories;
        return Array.isArray(added) ? added.filter(f => typeof f === "string" && isAbsolute(f)) : [];
      }
    }
    return [];
  } finally { closeSync(fd); }
}

/** Whether the path's real path, links followed, is inside one of the folders, or with self, is one. */
export function inside(file, folders, self = false) {
  if (typeof file !== "string" || !file || !isAbsolute(file)) return false;
  let path;
  try { path = realpathSync(file); } catch { return false; }
  return folders.some(folder => {
    let root;
    try { root = realpathSync(folder); } catch { return false; }
    return path.startsWith(root + sep) || (self && path === root);
  });
}

/** Whether Read may open the file: only when its real path, links followed, is inside the plugins' folder or a folder
 * added to the session. */
export function readAllowed(file, plugins = PLUGINS, added = []) {
  return inside(file, [plugins, ...added]);
}

/** Whether Glob or Grep may search: only in a folder added to the session, or a folder inside one, given as a full path,
 * with a pattern that names no other folder. */
export function searchAllowed(tool, input, added = []) {
  const patterns = [tool === "Glob" ? input?.pattern : input?.glob].filter(p => p !== undefined);
  if (patterns.some(p => typeof p !== "string" || isAbsolute(p) || /^~|(^|[\\/])\.\.([\\/]|$)/.test(p))) return false;
  return inside(input?.path, added, true);
}

/** Whether the agent may call the tool, with the call's input: true for any agent but these two; otherwise only their own
 * tools, invite_person and call_function naming okb-invite for the business analyst alone, and a connector's
 * tools on its own server, given the desktop ids the session has marked. A connector's tool still needs the person's
 * agreement in the session, which the hook asks for. */
export function allowed(agentType, toolName, marked = {}, input = {}) {
  if (!AGENTS[agentType]) return true;
  if (!String(toolName).startsWith("mcp__")) return BUILT_IN.includes(String(toolName));
  const [, server = "", ...rest] = String(toolName).split("__");
  const tool = rest.join("__");
  if (rest.length === 1 && server !== "" && CARD_ONLY.includes(tool)) return false;
  if (connectorRecord(server, tool)) return false;
  if (server === SERVER && agentType !== ADMIN_ONLY.agent
    && (ADMIN_ONLY.tools.includes(tool) || (tool === "call_function" && ADMIN_ONLY.functions.includes(String(input?.name ?? "").trim())))) return false;
  // Real Agent's connector's tools, on a server that is neither refused nor marked as Supabase's.
  if (realAgentTool(toolName) && !REFUSED_SERVERS.some(r => r.test(server)) && !(marked?.supabase ?? []).includes(server)) return true;
  return (server === SERVER && OKB.includes(tool)) || server === CHROME
    || (AGENTS[agentType].connectors && connectorOf(server, tool, marked) !== null);
}

/** Why the agent is refused one of Real Agent's connector's record, file or routine tools, named in full as tool, and what
 * it uses in Claude Code. */
export function connectorRefusal(who, name, tool) {
  if (name === "okb_routines" || name === "okb_routine")
    return `The ${who} follows a routine with its workflow plugin's own skill, which okb sync installs in Claude Code, not ${tool}.`;
  if (name === "okb_help") return `The ${who} answers how-to questions with the real-agent:support skill, not ${tool}.`;
  return `The ${who} reaches records and files with the okb plugin's own tools, such as rpc, list_files and read_file, not ${tool}.`;
}

const real = file => { try { return realpathSync(file); } catch { return file; } };
// Any failure here refuses the call, since Claude Code runs a tool whose hook errs.
if (argv[1] && real(fileURLToPath(import.meta.url)) === real(argv[1])) {
  const deny = reason => { stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: reason } })); process.exit(0); };
  const ask = reason => { stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: reason } })); process.exit(0); };
  try {
    let text = "";
    for await (const chunk of stdin) text += chunk;
    let call;
    try { call = JSON.parse(text); } catch { deny("The okb plugin's agent-tools hook could not read the tool call."); }
    const tool = String(call?.tool_name ?? "");
    const who = AGENTS[call?.agent_type]?.name;
    // A skill's own file is read with no look at the transcript.
    if (who && tool === "Read" && readAllowed(call?.tool_input?.file_path)) process.exit(0);
    if (who && (["Read", "Glob", "Grep"].includes(tool) || tool === `mcp__${SERVER}__copy_to_agent_folder`)) {
      const added = addedFolders(call?.transcript_path);
      const folders = added.length ? `the folders added to this session when it started: ${added.join(", ")}` : "no folder, since none was added to this session when it started";
      if (tool === "Read" && !readAllowed(call?.tool_input?.file_path, PLUGINS, added))
        deny(`The ${who} reads with Read only its skills' own files, in ${PLUGINS}, and ${folders}. Read a file in the agent folder with read_file. A folder added during a session is read in a new session.`);
      if ((tool === "Glob" || tool === "Grep") && !searchAllowed(tool, call?.tool_input, added))
        deny(`The ${who} searches with ${tool} only in ${folders}, named in full as path, with a pattern that names no other folder. A folder added during a session is searched in a new session.`);
      if (tool.endsWith("__copy_to_agent_folder") && !inside(call?.tool_input?.source_file, added))
        deny(`The ${who} copies into the agent folder only a file in ${folders}. A folder added during a session is copied from in a new session.`);
    }
    const [, server = "", ...rest] = tool.split("__"), name = rest.join("__");
    if (loginCall(server, server ? name : tool, call?.tool_input)) deny(LOGIN_REFUSED);
    // Both agents' calls mark a desktop id as Supabase's, and both are held by the marks. Only the database operator
    // is asked to agree to a connector.
    const marking = AGENTS[call?.agent_type] && tool.startsWith("mcp__") ? connectorState(call?.session_id ?? "none") : null;
    if (marking) {
      const state = marking;
      // The session's tool list, read from where the last call left off, marks each desktop id it shows to be Supabase's,
      // and names each it shows to be a named connector.
      const listed = typeof call?.transcript_path === "string"
        ? listedServers(call.transcript_path, state.listed?.transcript === call.transcript_path ? state.listed.offset : 0) : null;
      const found = listed ? listedMarks(listed.servers) : { supabase: [], names: {} };
      for (const key of marksFor(server, name)) found[key] = [...(found[key] ?? []), server];
      let changed = false;
      for (const id of found.supabase) if (!(state.marked.supabase ?? []).includes(id)) { state.marked.supabase = [...(state.marked.supabase ?? []), id]; changed = true; }
      for (const [id, label] of Object.entries(found.names)) if (state.names[id] !== label) { state.names[id] = label; changed = true; }
      if (listed && listed.offset !== state.listed?.offset) { state.listed = { transcript: call.transcript_path, offset: listed.offset }; changed = true; }
      if (changed) state.save({ marked: state.marked, names: state.names, listed: state.listed });
    }
    const state = AGENTS[call?.agent_type]?.connectors ? marking : null;
    if (!allowed(call?.agent_type ?? "", tool, marking?.marked, call?.tool_input)) {
      const adminOnly = server === SERVER && (ADMIN_ONLY.tools.includes(name) || name === "call_function");
      deny(adminOnly ? `The ${who} adds no one and gives no reset code: inviting a person and resetting a password are your administrator's, with their business analyst, @business-analyst:business-analyst.`
        : connectorRecord(server, name) ? connectorRefusal(who, name, tool)
        : tool === "mcp__ccd_turn__update_plan" ? `The ${who} does not keep a task list.`
        : `The ${who} does not use ${tool}.`);
    }
    if (who && server === CHROME) {
      if ((name === "navigate" && !chromeUrlAllowed(call?.tool_input?.url)) || (name === "browser_batch" && !chromeBatchAllowed(call?.tool_input)))
        deny(`The ${who} ${CHROME_NAVIGATE_REFUSED}`);
      if (name === "browser_batch" && !chromeBatchOrdered(call?.tool_input)) deny(`The ${who} ${CHROME_BATCH_REFUSED}`);
      if (chromeUploads(name, call?.tool_input)) deny(`The ${who} ${CHROME_UPLOAD_REFUSED}`);
      if (!chromeTabsNamed(name, call?.tool_input)) deny(`The ${who} ${CHROME_TAB_UNNAMED}`);
      const { tabs } = chromeTabs(call?.session_id ?? "none");
      const ids = chromeTabIds(call?.tool_input);
      if (ids.some(id => chromeTabRefused(tabs[id]))) deny(`The ${who} ${CHROME_TAB_REFUSED}`);
      if (ids.some(id => typeof tabs[id] !== "string")) deny(`The ${who} ${CHROME_TAB_UNSEEN}`);
      // The note is checked for staleness and marked before the call runs, under its lock, so two calls made at once never
      // both pass a fresh note. A note that cannot be locked or saved refuses the call.
      let staleNow = false, saved = null;
      try {
        saved = changeChromeTabs(call?.session_id ?? "none", now => {
          if (now.stale === true && name !== "tabs_context_mcp") { staleNow = true; return null; }
          return chromeTabsBefore(now, name, call?.tool_input, call?.tool_use_id);
        });
      } catch { saved = null; }
      if (staleNow) deny(`The ${who} ${CHROME_STALE}`);
      if (saved === null) deny(`The ${who} works in Chrome only while its tab note can be saved, in ${chromeTabs(call?.session_id ?? "none").file}.`);
    }
    const connector = state ? connectorOf(server, name, state.marked) : null;
    if (connector && !state.agreed.includes(connector))
      ask(`Your ${who} asks to use your ${labelOf(server, name, state.names)}, for ${name}. Allow this once to agree for the rest of this session; deny it to keep ${labelOf(server, name, state.names).replace(/ (connector|plugin)$/, "")} closed to your ${who}.`);
    // run_code reads the folders the session was started with, from its transcript, saved here for the session's folder
    // just before each call, on any server whose tool is run_code. The server takes none from the call.
    if (tool.startsWith("mcp__") && name === "run_code") {
      const folders = addedFolders(call?.transcript_path);
      for (const folder of new Set([call?.cwd, env.CLAUDE_PROJECT_DIR].filter(f => typeof f === "string" && isAbsolute(f)))) saveSessionFolders(folder, folders);
    }
    process.exit(0);
  } catch (err) {
    deny(`The okb plugin's agent-tools hook failed: ${err instanceof Error ? err.message : err}`);
  }
}
