// What the session's folder holds, for the agents' check at the start of a session: its actor file, its agent setting,
// whether `okb setup` made it, the agent and account its earlier sessions had, and the last lines of its
// upload-problems.log. A folder that lost its actor file or agent setting, as after a reinstall, is connected again with
// the actor skill's "Connect a folder again" command. It reads and changes nothing in OKB.
import { readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { readActor } from "./actor-file.mjs";
import { accountEmail, PROJECT_REF } from "./session.mjs";

const real = path => { try { return realpathSync.native(path); } catch { return null; } };
const samePath = (one, other) => process.platform === "win32" ? one.toLowerCase() === other.toLowerCase() : one === other;
const isDir = path => { try { return statSync(path).isDirectory(); } catch { return false; } };
const configFolder = () => process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude");
// The marketplace every client's plugins are installed from.
const MARKETPLACE = "real-agent";
// A session copy, as session-copy.mjs names it: <date>-<title>-<first 8 of the session id>.md.
const SESSION_COPY = /^(\d{4}-\d{2}-\d{2}|undated)-.+-[0-9a-f]{8}\.md$/;
// The newest transcripts read for the folder's earlier agent and account, and the largest read.
const TRANSCRIPTS = 20, MAX_TRANSCRIPT = 50 * 1024 * 1024, LOG_LINES = 5;

/** The agent the folder's `.claude/settings.json` names, or null. */
export function agentSetting(folder) {
  try {
    const agent = JSON.parse(readFileSync(join(folder, ".claude", "settings.json"), "utf-8"))?.agent;
    return typeof agent === "string" && agent.trim() ? agent.trim() : null;
  } catch { return null; }
}

/** True for a folder `okb setup` made: a sessions folder with `.uploaded.json` or a session copy in it, or an uploads
 * folder, which setup made before the folder was the only folder, in a folder directly inside the home folder. A web
 * project's own uploads folder elsewhere is not taken for one. */
export function madeBySetup(folder, home = homedir()) {
  let names = [];
  try { names = readdirSync(join(folder, "sessions")); } catch { /* no sessions folder */ }
  if (names.some(name => name === ".uploaded.json" || SESSION_COPY.test(name))) return true;
  const parent = real(dirname(folder)), root = real(home);
  return isDir(join(folder, "uploads")) && Boolean(parent && root && samePath(parent, root));
}

/** The time of the newest upload `.uploaded.json` notes, or 0. */
function lastUpload(folder) {
  try { return Math.max(0, ...Object.values(JSON.parse(readFileSync(join(folder, "sessions", ".uploaded.json"), "utf-8"))).filter(Number.isFinite)); }
  catch { return 0; }
}

/** The last lines of `sessions/upload-problems.log` written after the newest upload, oldest first, or an empty list.
 * session-upload.mjs only adds to the log, so a line from before an upload that worked is a problem since fixed. */
export function uploadProblems(folder, lines = LOG_LINES) {
  let text;
  try { text = readFileSync(join(folder, "sessions", "upload-problems.log"), "utf-8"); } catch { return []; }
  const since = lastUpload(folder);
  return text.replaceAll("\r\n", "\n").split("\n").filter(line => line.trim())
    .filter(line => { const at = Date.parse(line.split(" ")[0]); return !Number.isFinite(at) || at > since; }).slice(-lines);
}

// The agents a folder can name, when installed_plugins.json cannot be read.
const KNOWN_AGENTS = ["real-agent:database-operator", "real-agent:database-admin", "business-analyst:business-analyst"];

/** The agents installed on this computer from the real-agent marketplace, as `<plugin>:<agent>`, from each plugin's
 * agents folder. A transcript's agentSetting can name a skill, which setup refuses as an agent. */
export function installedAgents(configDir = configFolder()) {
  let plugins;
  try { plugins = JSON.parse(readFileSync(join(configDir, "plugins", "installed_plugins.json"), "utf-8"))?.plugins ?? {}; } catch { return KNOWN_AGENTS; }
  const agents = new Set();
  for (const [id, entries] of Object.entries(plugins)) {
    const [plugin, marketplace] = id.split("@");
    if (marketplace !== MARKETPLACE || !Array.isArray(entries)) continue;
    for (const entry of entries) {
      let files = [];
      try { files = readdirSync(join(entry?.installPath ?? "", "agents")).filter(f => f.endsWith(".md")); } catch { continue; }
      for (const file of files) {
        let name = file.slice(0, -3);
        try { name = /^---\r?\n[\s\S]*?^name:\s*(\S+)\s*$/m.exec(readFileSync(join(entry.installPath, "agents", file), "utf-8"))?.[1] ?? name; } catch { /* the file name */ }
        agents.add(`${plugin}:${name}`);
      }
    }
  }
  return agents.size ? [...agents] : KNOWN_AGENTS;
}

/** Claude Code's project folder for sessions opened on `folder`: the path with each character other than a letter
 * or digit made a hyphen. */
export const projectFolder = (folder, configDir = configFolder()) =>
  join(configDir, "projects", folder.replace(/[^a-zA-Z0-9]/g, "-"));

/** Each text a tool gave in one transcript line. */
function toolTexts(entry) {
  const content = entry?.message?.content;
  if (!Array.isArray(content)) return [];
  const texts = [];
  for (const block of content) {
    if (block?.type !== "tool_result") continue;
    if (typeof block.content === "string") texts.push(block.content);
    else if (Array.isArray(block.content)) for (const part of block.content) if (typeof part?.text === "string") texts.push(part.text);
  }
  return texts;
}

/**
 * The agent and the account the folder's earlier sessions had, from Claude Code's transcripts of them: the installed
 * agent they named most often, and the account `whoami` gave most often, with its project. Each is null when none is found.
 */
export function earlierSessions(folder, configDir = configFolder()) {
  const dir = projectFolder(folder, configDir);
  let files;
  try {
    files = readdirSync(dir).filter(name => name.endsWith(".jsonl"))
      .map(name => { const path = join(dir, name); try { const s = statSync(path); return { path, at: s.mtimeMs, size: s.size }; } catch { return null; } })
      .filter(f => f && f.size <= MAX_TRANSCRIPT).sort((a, b) => b.at - a.at).slice(0, TRANSCRIPTS);
  } catch { return { agent: null, email: null, projectRef: null }; }
  const valid = new Set(installedAgents(configDir));
  const agentsSeen = new Map();
  const accounts = new Map();
  for (const file of files) {
    let text;
    try { text = readFileSync(file.path, "utf-8"); } catch { continue; }
    for (const line of text.split("\n")) {
      if (!line.trim()) continue;
      let entry;
      try { entry = JSON.parse(line); } catch { continue; }
      const named = typeof entry?.agentSetting === "string" ? entry.agentSetting.trim() : "";
      if (valid.has(named)) agentsSeen.set(named, (agentsSeen.get(named) ?? 0) + 1);
      for (const t of toolTexts(entry)) {
        let answer;
        try { answer = JSON.parse(t); } catch { continue; }
        const r = answer?.result;
        if (answer?.ok !== true || typeof r?.email !== "string" || typeof r?.projectRef !== "string") continue;
        // A transcript is read, not trusted: only a well-formed account and project reference count.
        const email = accountEmail(r.email);
        if (!email || !PROJECT_REF.test(r.projectRef)) continue;
        const key = `${email} ${r.projectRef}`;
        accounts.set(key, (accounts.get(key) ?? 0) + 1);
      }
    }
  }
  const ranked = [...accounts].map(([key, count]) => [...key.split(" "), count]).sort((a, b) => b[2] - a[2]);
  const [email = null, projectRef = null] = ranked[0] ?? [];
  const agent = [...agentsSeen].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
  return { agent, email, projectRef };
}

/** The person's own account, as the okb plugin's settings name it, or null. */
export function ownEmail(configDir = configFolder()) {
  try {
    const email = JSON.parse(readFileSync(join(configDir, "settings.json"), "utf-8"))?.pluginConfigs?.[`okb@${MARKETPLACE}`]?.options?.auth_email;
    return typeof email === "string" ? accountEmail(email) : null;
  } catch { return null; }
}

/** The agent a folder's name points to: the database admin for a folder named for an administrator. */
export const agentByName = folder => {
  const name = folder.split(/[\\/]/).filter(Boolean).pop()?.toLowerCase() ?? "";
  return name.includes("admin") ? "real-agent:database-admin" : "real-agent:database-operator";
};

/**
 * The actor skill's command that connects the folder again, for this computer's system, with each value found filled
 * in, and where each one came from. A value not found is null, and the command is then null too.
 */
const AGENT_NAME = /^[a-z0-9-]+:[a-z0-9-]+$/;
// Each value is quoted for the shell it is pasted into, so no value can end the argument and run a command.
const posixQuote = v => `'${String(v).replaceAll("'", "'\\''")}'`;
const powershellQuote = v => `'${String(v).replaceAll("'", "''")}'`;

export function reconnectCommand(folder, { setting = null, earlier, configDir, platform = process.platform }) {
  const own = ownEmail(configDir);
  const email = accountEmail(earlier?.email) ?? own;
  const emailFrom = !email ? null : email === earlier?.email ? "the folder's earlier sessions" : "the okb plugin's settings";
  const named = [setting, earlier?.agent].find(a => typeof a === "string" && AGENT_NAME.test(a));
  const agent = named ?? agentByName(folder);
  const agentFrom = named === setting && setting ? "the folder's agent setting" : named ? "the folder's earlier sessions" : "the folder's name";
  const q = platform === "win32" ? powershellQuote : posixQuote;
  const options = `--email ${q(email)} --agent ${q(agent)}`;
  const command = !email ? null : platform === "win32"
    ? `node "$env:USERPROFILE\\.claude\\plugins\\marketplaces\\real-agent\\plugins\\okb\\cli\\okb.mjs" setup --folder ${q(folder)} ${options}`
    : `node ~/.claude/plugins/marketplaces/real-agent/plugins/okb/cli/okb.mjs setup --folder ${q(folder)} ${options}`;
  return { folder, email, emailFrom, agent, agentFrom, shell: platform === "win32" ? "PowerShell" : "Terminal", command };
}

/**
 * The session's folder: its full path, whether it holds a usable actor file and an agent setting, whether setup made
 * it, whether it is the agent folder the okb plugin's settings name, and so whether it is connected. A disconnected
 * folder setup made also gives the agent and account its earlier sessions had, and the command that connects it
 * again. Null with no session folder.
 */
export function sessionFolderStatus(session, { agentFolders = [], configDir = configFolder(), platform = process.platform } = {}) {
  const path = session && real(session);
  if (!path || !isDir(path)) return null;
  const actor = readActor(path);
  const agent = agentSetting(path);
  const isAgentFolder = agentFolders.some(f => { const r = f && real(f); return r && samePath(r, path); });
  const status = {
    path,
    hasActorFile: Boolean(actor?.ok),
    ...(actor && !actor.ok ? { actorFileProblem: actor.problem } : {}),
    hasAgentSetting: Boolean(agent),
    agent,
    madeBySetup: madeBySetup(path),
    isAgentFolder,
  };
  // The agent folder the settings name signs in with the settings, so it holds no actor file.
  status.connected = (status.hasActorFile || isAgentFolder) && status.hasAgentSetting;
  if (!status.connected && status.madeBySetup) {
    status.earlier = earlierSessions(path, configDir);
    status.reconnect = reconnectCommand(path, { setting: agent, earlier: status.earlier, configDir, platform });
  }
  status.uploadProblems = uploadProblems(path);
  return status;
}
