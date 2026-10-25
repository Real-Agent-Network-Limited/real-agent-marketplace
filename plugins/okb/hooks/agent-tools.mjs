// Keeps the database operator and the database admin to the okb plugin's tools, Claude in Chrome's tools that
// open and read a page, never at a Supabase address, for the database operator the person's Google and Microsoft 365
// connectors as CONNECTORS gives them, and the built-in tools in BUILT_IN, beside each agent's disallowedTools. Every other MCP tool is refused,
// the Supabase connector's among them, since it reaches past OKB's grants. Read reads a skill's own files, inside the
// installed plugins' folder, and the files in each folder added to the session. Glob and Grep search those added folders
// alone, and copy_to_agent_folder copies a file from one into the agent folder. For run_code, from any agent or session,
// on any server whose tool is named run_code, it saves those folders for the session's folder, and run_code reads them alone. Reads the tool
// call from stdin, as Claude Code's PreToolUse hooks receive it; any other agent's calls go ahead. one-issue.mjs,
// agent-folder-edit.mjs and connector-agreed.mjs take their agents from AGENTS here.
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
import { closeSync, openSync, readFileSync, readSync, realpathSync, writeFileSync } from "node:fs";
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
// The okb tools only the database admin uses: invite_person, which adds a person through the okb-invite hosted function.
// call_function naming okb-invite is the same call, and is the database admin's alone too.
export const ADMIN_ONLY = { tools: ["invite_person"], functions: ["okb-invite"], agent: "real-agent:database-admin" };

// Claude in Chrome's server, the same in a terminal and in the desktop app, and its tools that open and read a page.
// Its tools that click, type, fill a form, run a script or upload a file are refused.
export const CHROME = "claude-in-chrome";
export const CHROME_READ = ["navigate", "read_page", "get_page_text", "find", "tabs_context_mcp", "tabs_create_mcp", "tabs_close_mcp"];
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

// The Google Calendar, Google Drive and Google Sheets connectors' tools, each to read and to change, as Claude names them.
const CALENDAR = ["list_calendars", "list_events", "search_events", "get_event", "suggest_time", "create_event", "update_event",
  "delete_event", "respond_to_event"];
const DRIVE = ["search_files", "list_recent_files", "get_file_metadata", "get_file_permissions", "read_file_content",
  "download_file_content", "create_file", "update_file", "copy_file", "share_file", "trash_file"];
const SHEETS = ["get_spreadsheet", "get_values", "update_values", "append_values", "batch_clear_values", "update_formulas",
  "insert_dimension", "update_spreadsheet", "copy_sheet_to_another_spreadsheet"];
// UNCONFIRMED: the Microsoft 365 connector's server name and tool names. No Real Agent computer has had it
// connected, and Anthropic's connector page lists its services, not its tools. MICROSOFT_365_SERVERS holds its server's
// name in a terminal session, by the claude_ai_<name> pattern of the Google connectors. MICROSOFT_365_PREFIXES and
// MICROSOFT_365_SHARED hold its tools, from a third party's listing on 24 October 2026: outlook_email_search,
// outlook_calendar_search, sharepoint_search, sharepoint_folder_search, find_meeting_availability and read_resource. Its
// Teams tool, chat_message_search, is left out, since decision 2.33 names Outlook mail and calendar, OneDrive, SharePoint
// and Excel alone. Change these three lists once the connector is seen on a computer: `claude mcp list`, or a denied call's
// tool name in the refusal, shows each name.
export const MICROSOFT_365_SERVERS = ["claude_ai_Microsoft_365"];
export const MICROSOFT_365_PREFIXES = ["outlook_", "sharepoint_", "onedrive_", "excel_"];
export const MICROSOFT_365_SHARED = ["find_meeting_availability", "read_resource"];
const microsoft = tool => MICROSOFT_365_PREFIXES.some(p => tool.startsWith(p));

// A connector's server in the desktop app: an id for it in place of its name.
const DESKTOP_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// Each connector: what the person calls it, its server's names in a terminal session, the tools only it has, which mark a
// desktop id as its own for the session, and whether a tool is one of its own. Under a desktop id, a connector's own tools
// go ahead and mark the id; its other tools go ahead only on an id so marked.
export const CONNECTORS = {
  calendar: { label: "Google Calendar", names: ["claude_ai_Google_Calendar"], own: tool => ["list_calendars", "suggest_time"].includes(tool), has: tool => CALENDAR.includes(tool) },
  drive: { label: "Google Drive", names: ["claude_ai_Google_Drive"], own: tool => ["list_recent_files", "get_file_permissions"].includes(tool), has: tool => DRIVE.includes(tool) },
  sheets: { label: "Google Sheets", names: ["claude_ai_Google_Sheets"], own: tool => tool === "get_spreadsheet", has: tool => SHEETS.includes(tool) },
  microsoft365: { label: "Microsoft 365", names: MICROSOFT_365_SERVERS, own: microsoft, has: tool => microsoft(tool) || MICROSOFT_365_SHARED.includes(tool) },
};

/** The connector a tool belongs to on the server, given the desktop ids the session has marked as each connector's, or null. */
export function connectorOf(server, tool, marked = {}) {
  for (const [key, c] of Object.entries(CONNECTORS)) {
    if (!c.has(tool)) continue;
    if (c.names.includes(server)) return key;
    if (DESKTOP_ID.test(server) && (c.own(tool) || (marked[key] ?? []).includes(server))) return key;
  }
  return null;
}

/** The connectors a desktop id is marked as by this call: each whose own tools hold the tool. */
export function marksFor(server, tool) {
  if (!DESKTOP_ID.test(server)) return [];
  return Object.entries(CONNECTORS).filter(([, c]) => c.own(tool)).map(([key]) => key);
}

/** The session's connector state, kept in a file named for the session where the agents cannot write: { marked: { calendar:
 * [ids], ... }, agreed: [connector keys] }. */
export function connectorState(session, dir = tmpdir()) {
  const file = join(dir, `okb-connectors-${String(session).replace(/[^\w-]/g, "")}.json`);
  let state = {};
  try { state = JSON.parse(readFileSync(file, "utf8")) ?? {}; } catch {}
  return { marked: state.marked ?? {}, agreed: Array.isArray(state.agreed) ? state.agreed : [], file,
    save(next) { writeFileSync(file, JSON.stringify({ marked: next.marked ?? this.marked, agreed: next.agreed ?? this.agreed }), { mode: 0o600 }); } };
}

// The agent_type Claude Code gives each agent, and what its refusals call it.
// The database operator alone uses the person's connectors, as decision 2.33 gives it.
export const AGENTS = {
  "real-agent:database-operator": { name: "database operator", connectors: true },
  "real-agent:database-admin": { name: "database admin", connectors: false },
};

// The built-in tools both agents use. Any other, such as one a later Claude Code adds, is refused. Read, Glob and Grep
// reach only the folders below.
// Artifact publishes a checked page on the person's own Claude account, private until they share it.
const BUILT_IN = ["Skill", "Write", "Edit", "WebSearch", "WebFetch", "ToolSearch", "ListPlugins", "Read", "Glob", "Grep", "Artifact"];

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

/** Whether the agent may call the tool, with the call's input: true for any agent but these two; for them, only their own
 * tools, invite_person and call_function naming okb-invite for the database admin alone, and a connector's
 * tools on its own server, given the desktop ids the session has marked. A connector's tool still needs the person's
 * agreement in the session, which the hook asks for. */
export function allowed(agentType, toolName, marked = {}, input = {}) {
  if (!AGENTS[agentType]) return true;
  if (!String(toolName).startsWith("mcp__")) return BUILT_IN.includes(String(toolName));
  const [, server = "", ...rest] = String(toolName).split("__");
  const tool = rest.join("__");
  if (server === SERVER && agentType !== ADMIN_ONLY.agent
    && (ADMIN_ONLY.tools.includes(tool) || (tool === "call_function" && ADMIN_ONLY.functions.includes(String(input?.name ?? "").trim())))) return false;
  return (server === SERVER && OKB.includes(tool)) || (server === CHROME && CHROME_READ.includes(tool))
    || (AGENTS[agentType].connectors && connectorOf(server, tool, marked) !== null);
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
    const state = AGENTS[call?.agent_type]?.connectors && tool.startsWith("mcp__") ? connectorState(call?.session_id ?? "none") : null;
    if (state) {
      const marks = marksFor(server, name).filter(key => !(state.marked[key] ?? []).includes(server));
      for (const key of marks) state.marked[key] = [...(state.marked[key] ?? []), server];
      if (marks.length) state.save({ marked: state.marked });
    }
    if (!allowed(call?.agent_type ?? "", tool, state?.marked, call?.tool_input)) {
      const other = DESKTOP_ID.test(server) ? Object.values(CONNECTORS).find(c => c.has(name)) : null;
      const adminOnly = server === SERVER && (ADMIN_ONLY.tools.includes(name) || name === "call_function");
      deny(other
        ? `The ${who} uses ${name} only on ${other.label}. Use one of ${other.label}'s own tools on it first, so the hook knows ${server} is ${other.label}.`
        : adminOnly ? `The ${who} adds no one: inviting a person is the database admin's, @real-agent:database-admin.`
        : `The ${who} does not use ${tool}.`);
    }
    if (AGENTS[call?.agent_type] && tool === `mcp__${CHROME}__navigate` && !chromeUrlAllowed(call?.tool_input?.url))
      deny(`The ${AGENTS[call.agent_type].name} opens no Supabase address in Chrome, and only web addresses.`);
    const connector = state ? connectorOf(server, name, state.marked) : null;
    if (connector && !state.agreed.includes(connector))
      ask(`Your ${who} asks to use your ${CONNECTORS[connector].label} connector, for ${name}. Allow this once to agree for the rest of this session; deny it to keep ${CONNECTORS[connector].label} closed to your ${who}.`);
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
