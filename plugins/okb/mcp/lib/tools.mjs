// The Supabase Auth user's tools: `whoami`, `rpc`, `call_function`, `invite_person`, which calls the okb-invite
// hosted function, `upload_file`, `list_files`, `download_file` and `read_file`, under that user's own rights; `update_plugins`, which runs okb sync
// as that user; `check_plugins`, which compares the plugins installed from the real-agent marketplace with
// the newest release in the Plugins scope, with cli/releases.mjs, changes nothing, and gives what the
// session's folder holds, as session-folder.mjs reads it; and `copy_to_agent_folder`, which copies a file
// into the agent folder: the okb plugin's agent-tools hook keeps the agents' copies to the folders added to
// their session. The MCP server and the okb plugin's terminal command both make them with createTools, from
// the same settings.
import { lstatSync, readFileSync, realpathSync } from "node:fs";
import { execFile } from "node:child_process";
import { homedir, tmpdir } from "node:os";
import { isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";
import { READ_LIMIT, readAgentFile } from "./read.mjs";
import { createHash } from "node:crypto";
import { accountEmail, agentFiles, agentJson, callFunction, callRpc, currentUser, downloadObject, listObjects, placeAt, readSession, refreshSession, uploadObject, uploadSource, writeAgentFile, writeSession, PROJECT_REF, ROW_LIMIT } from "./session.mjs";
import { sessionFolderStatus } from "./session-folder.mjs";

// The marketplace every client's plugins are installed from, as cli/releases.mjs names it.
const MARKETPLACE_NAME = "real-agent";
// check_plugins reads the releases with the okb plugin's cli/releases.mjs, loaded when it runs, so the other tools
// need nothing outside this folder.
const RELEASES = new URL("../../cli/releases.mjs", import.meta.url);

const SIGN_IN = fileURLToPath(new URL("../sign-in.mjs", import.meta.url));
const OKB_COMMAND = fileURLToPath(new URL("../../cli/okb.mjs", import.meta.url));
// The agent folder with links and a trailing slash resolved, so two plugins' settings can be compared.
const folderPath = folder => { if (!folder) return null; try { return realpathSync.native(folder); } catch { return null; } };
// The largest file copy_to_agent_folder copies.
const MAX_COPY_BYTES = 50 * 1024 * 1024;


export const TOOLS = [
  {
    name: "whoami",
    description: "The Supabase Auth user this agent is signed in as: its id and email address, the project's reference as projectRef, the agent folder, as set and as agentFolderPath, resolved, the files directly inside it, as agentFiles, the newest 50 names, newest first, with agentFileCount, how many there are, and the schema rpc uses when a call names none, as defaultSchema. upload_file reads a file directly inside the agent folder, rpc reads and writes JSON there, and download_file writes there.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "rpc",
    description: `Call one database function through Supabase's REST API, as the signed-in user. Returns at most ${ROW_LIMIT} rows.`,
    inputSchema: {
      type: "object",
      properties: {
        function: { type: "string", description: "The function's name." },
        schema: { type: "string", description: "The exposed schema it is in. Omit for the default schema whoami shows." },
        args: { type: "object", description: "Named arguments.", additionalProperties: true },
        file_args: {
          type: "object",
          description: "JSON from files, placed into args before the call. Each key is a JSON pointer into args, such as /p_request/payload, and each value the full path of a JSON file directly inside the agent folder whoami shows. The empty pointer takes the whole of args from the file.",
          additionalProperties: { type: "string" },
        },
        result_file: { type: "string", description: "The full path of a new file directly inside the agent folder, which the result is written to as JSON. A file already there is never replaced. The reply then says where the result went, not what it is." },
      },
      required: ["function"],
      additionalProperties: false,
    },
  },
  {
    name: "call_function",
    description: "Call one of the project's hosted functions (Supabase Edge Functions) with a JSON body, as the signed-in user. The function decides what the user may do.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "The hosted function's name." },
        body: { type: "object", description: "The JSON body to send. Omit to send an empty object.", additionalProperties: true },
        result_file: { type: "string", description: "The full path of a new file directly inside the agent folder, which the reply is written to as JSON. A file already there is never replaced. The reply then says where the result went, not what it is." },
      },
      required: ["name"],
      additionalProperties: false,
    },
  },
  {
    name: "invite_person",
    description: "Add one person to the firm's OKB in one call, as the signed-in administrator, through the okb-invite hosted function: it invites their email through Supabase Auth, which emails them a link to choose their password, or reuses the sign-in they already have; makes their actor, named \"<name> (Real Agent)\" for the real_agent template, with their sessions scope; gives the access template's grants, or a workflow role's grants from its access.json with the basic template's; saves the access record in the Administration scope; and, for Real Agent, completes setup's open \"Add Real Agent\" tasks. Give template, or workflow and role. Only an administrator's call goes on. Returns the person's name, email, actor_id, sign_in (invited or existing), the grants given by scope name, access_record_id and completed_tasks; never a password or a link.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "The person's name, as the firm calls them, such as Sam Lee, or Support for Real Agent's staff." },
        email: { type: "string", description: "The person's work email address." },
        template: { type: "string", description: "An access template's code, such as basic or real_agent, as okb_get_access_templates lists them. Omit for a workflow role." },
        workflow: { type: "string", description: "A workflow plugin's name, such as appraisal, for a role in it. Give role with it." },
        role: { type: "string", description: "One role in the workflow's access.json, such as negotiator." },
      },
      required: ["name", "email"],
      additionalProperties: false,
    },
  },
  {
    name: "upload_file",
    description: "Upload one local file, up to 6 MB, from this agent's agent folder into a Supabase Storage bucket, as the signed-in user. The project's storage policies decide where it may go.",
    inputSchema: {
      type: "object",
      properties: {
        bucket: { type: "string", description: "The bucket's name." },
        path: { type: "string", description: "Where the file goes inside the bucket, such as name.pdf or a folder like reports/name.pdf. The project's policies decide which buckets the signed-in user may write to; in buckets set up by the storage-access skill, that is the user's permission in the bucket's scope, whatever the path." },
        file: { type: "string", description: "The file's full path, directly inside the agent folder whoami shows, not in a folder within it. A hidden file or a link is refused." },
        content_type: { type: "string", description: "The file's type. Omit to take it from the file's extension." },
        overwrite: { type: "boolean", description: "Replace a file already at that path. Off unless asked for." },
      },
      required: ["bucket", "path", "file"],
      additionalProperties: false,
    },
  },
  {
    name: "read_file",
    description: "Read one file inside the agent folder whoami shows, directly inside it or in a folder within it: text, a notebook, an image, a PDF, a Word document, spreadsheet or slide deck, a recording, or a video. Text comes back as text, up to 2,000 lines a call; an image as an image; a PDF as its pages' text, up to 20 pages a call; Office files as their text; a recording as a timed transcript; a video as frames and the speech at their times. Files up to 50 MB; videos up to 5 minutes. Given a folder, or the agent folder itself, it lists the files and folders in it. Hidden files and folders, and links, are not read.",
    inputSchema: {
      type: "object",
      properties: {
        file: { type: "string", description: "The full path of a file or folder inside the agent folder whoami shows, at any depth." },
        pages: { type: "string", description: "For a PDF, the pages to read, such as 3 or 1-5; at most 20. Omit for the first 20." },
        offset: { type: "integer", minimum: 1, description: "The line to start from, for text longer than one call returns. Omit to start at line 1." },
        limit: { type: "integer", minimum: 1, description: "The most lines to return. Omit for 2,000." },
        from: { type: "integer", minimum: 1, description: "The character of line offset to start from, for a line longer than one call returns. Omit to start at its first character." },
      },
      required: ["file"],
      additionalProperties: false,
    },
    _meta: { "anthropic/maxResultSizeChars": 200000 },
  },
  {
    name: "list_files",
    description: `List the files in one folder of a Supabase Storage bucket that the signed-in user may see. Returns at most ${ROW_LIMIT} entries.`,
    inputSchema: {
      type: "object",
      properties: {
        bucket: { type: "string", description: "The bucket's name." },
        prefix: { type: "string", description: "The folder inside the bucket. Omit for the top." },
      },
      required: ["bucket"],
      additionalProperties: false,
    },
  },
  {
    name: "download_file",
    description: "Download one file, up to 50 MB, from a Supabase Storage bucket into a new file directly inside the agent folder whoami shows, as the signed-in user. The project's storage policies decide what the user may download. Returns the file's full path, its size, its type and its SHA-256.",
    inputSchema: {
      type: "object",
      properties: {
        bucket: { type: "string", description: "The bucket's name." },
        path: { type: "string", description: "The file's path inside the bucket, such as name.pdf or reports/name.pdf." },
        file: { type: "string", description: "The full path of a new file directly inside the agent folder, which the download is written to. A file already there is never replaced." },
      },
      required: ["bucket", "path", "file"],
      additionalProperties: false,
    },
  },
  {
    name: "update_plugins",
    description: "Update this computer's plugins from the firm's own OKB, only when the person asks to update. It runs okb sync signed in as the person: it downloads the newest release from the Plugins scope, checks every file against the release's MANIFEST, passes over a release that fails for the next older one, keeps the release as a Git copy, registers it in Claude Code as the real-agent marketplace, and runs claude plugin update for each plugin installed from it. Returns what okb sync printed: the release the copy is at, each plugin's old and new version, and each plugin of the release not installed. The new versions take effect in the next Code session.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "check_plugins",
    description: "Compare the plugins installed on this computer from the real-agent marketplace with the newest release in the firm's Plugins scope in OKB, signed in as the person. It reads the newest release with a MANIFEST whose plugin.json files match it, and changes nothing in OKB or on the computer. Returns the release, and behind: each installed plugin whose version is lower than the release's, with both versions. With behind empty, or no release in the scope, the reply says nothing about plugins. Also returns sessionFolder, the session's folder: its full path, hasActorFile, hasAgentSetting and agent, madeBySetup, isAgentFolder and connected. A disconnected folder setup made also gives earlier: the agent, the email and the project its earlier sessions had, and reconnect: the command that connects it again. uploadProblems holds the last lines of the folder's sessions/upload-problems.log written since its last upload.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "copy_to_agent_folder",
    description: "Copy a file from a folder added to this session into the agent folder, as a new file, for an upload or a tool that works on the agent folder's files. The okb plugin's hook allows the agents only a file in a folder added to the session when it started. The source is a file, not a link or a folder, of 50 MB at most. The new file is directly inside the agent folder; nothing is replaced. Returns the new file's path, size and SHA-256.",
    inputSchema: {
      type: "object",
      properties: {
        source_file: { type: "string", description: "The file to copy, as a full path in a folder added to the session." },
        new_file: { type: "string", description: "The new file, as a full path directly inside the agent folder." },
      },
      required: ["source_file", "new_file"],
      additionalProperties: false,
    },
  },
];

/** The plugins installed from the real-agent marketplace, as { name: version }, from installed_plugins.json in the
 * Claude config folder. A plugin installed at more than one scope gives its user scope's version. Null where the
 * file cannot be read. */
export function installedPlugins(configDir = process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude")) {
  let plugins;
  try { plugins = JSON.parse(readFileSync(join(configDir, "plugins", "installed_plugins.json"), "utf8"))?.plugins ?? {}; } catch { return null; }
  const installed = {};
  for (const [id, entries] of Object.entries(plugins)) {
    const [name, marketplace] = id.split("@");
    if (marketplace !== MARKETPLACE_NAME || !Array.isArray(entries) || !entries.length) continue;
    const entry = entries.find(e => e?.scope === "user") ?? entries[0];
    if (typeof entry?.version === "string") installed[name] = entry.version;
  }
  return installed;
}

/** -1, 0 or 1 as version a is lower than, the same as, or higher than b, by each dotted number in turn. */
export function compareVersions(a, b) {
  const one = String(a).split(/[.+-]/).map(Number), other = String(b).split(/[.+-]/).map(Number);
  for (let i = 0; i < Math.max(one.length, other.length); i++) {
    const x = Number.isFinite(one[i]) ? one[i] : 0, y = Number.isFinite(other[i]) ? other[i] : 0;
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}

/**
 * The plain values of a result written to a file, so the agent can report it without reading it.
 * Each object gives its strings, numbers, booleans and nulls, down to four objects deep. Each list
 * gives its length, and an object deeper than that gives how many fields it has. A string over 200
 * characters is left out.
 */
function summarise(body, depth = 0) {
  const plain = value => value === null || ["string", "number", "boolean"].includes(typeof value);
  if (plain(body)) return body;
  if (Array.isArray(body)) return { items: body.length };
  if (depth >= 4) return { fields: Object.keys(body).length };
  return Object.fromEntries(Object.entries(body)
    .filter(([, value]) => !(typeof value === "string" && value.length > 200))
    .map(([key, value]) => [key, summarise(value, depth + 1)]));
}

const asContent = payload => ({ content: [{ type: "text", text: JSON.stringify(payload, null, 2) }] });

/**
 * The tools for one Auth user of one project: `ref`, `email`, the agent folder, whisper.cpp's settings,
 * the session's folder and the agent folders the settings name, for check_plugins, and the Claude config
 * folder. Returns the tools' list and `callTool`, which answers as MCP content.
 */
export function createTools({ ref, email, agentFolder = null, defaultSchema = null, whisperSettings = {}, sessionFolder = null, agentFolders = [],
  configDir = process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude") }) {
  /** One argument, quoted for the user's shell. Windows paths and checked addresses hold no `"`. */
  const quote = value => process.platform === "win32" ? `"${value}"` : `'${String(value).replaceAll("'", `'\\''`)}'`;
  const signInCommand = saved => ["node", quote(SIGN_IN), ...(saved ? ["--project", quote(ref), "--email", quote(email)] : [])].join(" ");
  const signedOut = (why, saved) =>
    `${why} The user signs in at a terminal with: ${signInCommand(saved)}. Never ask for the password in chat.`;

  let cached = null;
  let refreshing = null;

  /** A current access token, refreshed a minute before it expires. Concurrent calls share one refresh. */
  async function access() {
    if (cached && cached.expiresAt - 60_000 > Date.now()) return { ok: true, ...cached };
    refreshing ??= refresh().finally(() => { refreshing = null; });
    return refreshing;
  }

  async function refresh() {
    cached = null;
    let saved;
    try { saved = readSession(ref, email); }
    catch (err) { return { ok: false, problem: err instanceof Error ? err.message : String(err) }; }
    if (!saved) return { ok: false, problem: signedOut(`No Supabase session is saved for ${email} on project ${ref}.`, false) };

    const renewed = await refreshSession(saved.url, saved.publishableKey, saved.refreshToken);
    if (!renewed.ok) return { ok: false, problem: signedOut(`Supabase ended the session: ${renewed.problem}.`, true) };

    const signedIn = accountEmail(renewed.body.user?.email);
    if (signedIn !== email)
      return { ok: false, problem: signedOut(`The saved session is for ${renewed.body.user?.email}, but this agent is set up for ${email}.`, false) };

    // Each refresh token is good once, so the new one is saved before it is used.
    const { version: _version, ...kept } = saved;
    writeSession(ref, email, { ...kept, refreshToken: renewed.body.refresh_token });
    const expiresAt = renewed.body.expires_at ? renewed.body.expires_at * 1000 : Date.now() + renewed.body.expires_in * 1000;
    cached = { url: saved.url, key: saved.publishableKey, token: renewed.body.access_token, expiresAt };
    return { ok: true, ...cached };
  }

  async function whoami() {
    const session = await access();
    if (!session.ok) return session;
    const user = await currentUser(session.url, session.key, session.token);
    if (!user.ok) return user;
    const files = agentFiles(agentFolder);
    return { ok: true, result: { id: user.body.id, email: user.body.email, projectRef: ref, agentFolder, agentFolderPath: folderPath(agentFolder),
      agentFiles: files?.names ?? null, agentFileCount: files?.count ?? null, ...(files && files.count > files.names.length ? { agentFilesTruncated: `newest ${files.names.length} of ${files.count}` } : {}),
      defaultSchema: defaultSchema ?? "public" } };
  }

  async function callHostedFunction(args) {
    if (args.result_file !== undefined) {
      // Asked before the call, so a reply with nowhere to go is never asked for.
      const free = writeAgentFile(agentFolder, args.result_file, "", { check: true });
      if (!free.ok) return free;
    }
    const session = await access();
    if (!session.ok) return session;
    const out = await callFunction(session.url, session.key, session.token, args.name, args.body ?? {});
    if (!out.ok) return out;
    if (args.result_file === undefined) return { ok: true, result: out.body };
    const written = writeAgentFile(agentFolder, args.result_file, JSON.stringify(out.body, null, 1) + "\n");
    if (!written.ok) return { ...written, problem: `The call succeeded, but its reply was not saved: ${written.problem}` };
    return { ok: true, resultFile: written.file, bytes: written.bytes, summary: summarise(out.body) };
  }

  /** okb-invite, as the signed-in person, with only the fields it reads. Its own answer comes back, refusal or not. */
  async function invitePerson(args) {
    const body = Object.fromEntries(["name", "email", "template", "workflow", "role"].filter(k => args[k] !== undefined).map(k => [k, args[k]]));
    const session = await access();
    if (!session.ok) return session;
    const out = await callFunction(session.url, session.key, session.token, "okb-invite", body);
    if (out.ok) return out.body;
    return out.body && typeof out.body === "object" && out.body.ok === false ? out.body : { ok: false, problem: out.problem };
  }

  async function uploadFile(args) {
    const source = uploadSource(agentFolder, args.file, args.content_type);
    if (!source.ok) return source;
    const session = await access();
    if (!session.ok) return session;
    const out = await uploadObject(session.url, session.key, session.token, args.bucket, args.path, source.body, source.contentType, args.overwrite === true);
    if (!out.ok) return out;
    return { ok: true, result: { key: out.body?.Key, id: out.body?.Id, bytes: source.body.length, contentType: source.contentType } };
  }

  async function listFiles(args) {
    const session = await access();
    if (!session.ok) return session;
    const out = await listObjects(session.url, session.key, session.token, args.bucket, args.prefix);
    if (!out.ok) return out;
    return { ok: true, result: out.body, ...(out.truncated ? { truncated: out.truncated } : {}) };
  }

  async function downloadFile(args) {
    // Asked before the download, so a file with nowhere to go is never fetched.
    const free = writeAgentFile(agentFolder, args.file, "", { check: true });
    if (!free.ok) return free;
    const session = await access();
    if (!session.ok) return session;
    const out = await downloadObject(session.url, session.key, session.token, args.bucket, args.path, READ_LIMIT);
    if (!out.ok) return out;
    const written = writeAgentFile(agentFolder, args.file, out.body);
    if (!written.ok) return { ...written, problem: `The download succeeded, but it was not saved: ${written.problem}` };
    return { ok: true, result: { file: written.file, bytes: written.bytes, contentType: out.contentType, sha256: createHash("sha256").update(out.body).digest("hex") } };
  }

  async function readFile(args) {
    const read = await readAgentFile(agentFolder, args, whisperSettings);
    return read.ok ? { content: read.content } : asContent(read);
  }

  async function rpc(args) {
    let callArgs = args.args ?? {};
    // Files are read, and placed, before anything is sent, so a bad file sends nothing.
    for (const [pointer, file] of Object.entries(args.file_args ?? {})) {
      const read = agentJson(agentFolder, file);
      if (!read.ok) return read;
      const placed = placeAt(callArgs, pointer, read.value);
      if (!placed.ok) return placed;
      callArgs = placed.value;
    }
    if (args.result_file !== undefined) {
      const free = writeAgentFile(agentFolder, args.result_file, "", { check: true });
      if (!free.ok) return free;
    }
    const session = await access();
    if (!session.ok) return session;
    const out = await callRpc(session.url, session.key, session.token, args.function, args.schema ?? defaultSchema ?? undefined, callArgs);
    if (!out.ok) return out;
    const reply = { ok: true, result: out.body, ...(out.truncated ? { truncated: out.truncated } : {}) };
    if (args.result_file === undefined) return reply;
    const written = writeAgentFile(agentFolder, args.result_file, JSON.stringify(out.body, null, 1) + "\n");
    if (!written.ok) return { ...written, problem: `The call succeeded, but its result was not saved: ${written.problem}` };
    return { ok: true, resultFile: written.file, bytes: written.bytes, summary: summarise(out.body), ...(out.truncated ? { truncated: out.truncated } : {}) };
  }

  /** okb sync, as this server's person, in a folder of its own so no folder's actor file names another. */
  function updatePlugins() {
    const command = `node "${OKB_COMMAND}" sync --project ${ref} --email ${email}`;
    return new Promise(done => {
      execFile(process.execPath, [OKB_COMMAND, "sync", "--project", ref, "--email", email], { cwd: tmpdir(), timeout: 900_000, maxBuffer: 4 * 1024 * 1024 }, (err, stdout, stderr) => {
        const output = `${stdout}${stderr}`.replaceAll("\r\n", "\n").trim();
        if (err) return done({ ok: false, output, problem: `okb sync stopped. The person can run it in a terminal: ${command}` });
        done({ ok: true, output });
      });
    });
  }

  /**
   * Each installed plugin behind the newest release in the Plugins scope: the newest with a MANIFEST whose plugin.json
   * files match it, as okb sync passes over a release that fails its check. A scope with no release, or none the person
   * may read, leaves every plugin as installed from Real Agent's public marketplace, and none is behind.
   */
  async function checkPlugins() {
    const installed = installedPlugins(configDir);
    if (!installed) return { ok: false, problem: "This computer's list of installed plugins, installed_plugins.json in the Claude config folder, could not be read." };
    const session = await access();
    if (!session.ok) return session;
    const { downloadFile: downloadReleaseFile, listReleases, manifestEntries, sha256, RELEASES_BUCKET } = await import(RELEASES.href);
    const releaseAccess = { url: session.url, key: session.key, token: session.token };
    const listed = await listReleases(releaseAccess);
    if (!listed.ok) return { ok: false, problem: `The releases in OKB could not be listed: ${listed.problem}` };
    const plugins = Object.keys(installed).sort();
    const none = "No plugin is behind. The reply says nothing about plugins or versions.";
    for (const name of listed.names) {
      const manifest = await downloadReleaseFile(releaseAccess, RELEASES_BUCKET, `${name}/MANIFEST`);
      if (!manifest.ok) {
        if (manifest.missing) continue;
        return { ok: false, problem: `The MANIFEST of release ${name} could not be read: ${manifest.problem}` };
      }
      let hashes;
      try { hashes = new Map(manifestEntries(manifest.body.toString("utf8")).map(e => [e.path, e.hash])); } catch { continue; }
      const files = [];
      for (const plugin of plugins) {
        const path = `plugins/${plugin}/.claude-plugin/plugin.json`;
        files.push(hashes.has(path) ? { plugin, path, got: await downloadReleaseFile(releaseAccess, RELEASES_BUCKET, `${name}/${path}`) } : null);
      }
      const failed = files.find(f => f && !f.got.ok && !f.got.missing);
      if (failed) return { ok: false, problem: `${failed.plugin}'s plugin.json in release ${name} could not be read: ${failed.got.problem}` };
      // A plugin.json the MANIFEST lists that is missing or changed: okb sync passes this release over too.
      if (files.some(f => f && (!f.got.ok || sha256(f.got.body) !== hashes.get(f.path)))) continue;
      const behind = [];
      for (const f of files) {
        if (!f) continue;
        let released;
        try { released = JSON.parse(f.got.body.toString("utf8")).version; } catch { released = undefined; }
        if (typeof released !== "string") return { ok: false, problem: `${f.plugin}'s plugin.json in release ${name} names no version.` };
        if (compareVersions(installed[f.plugin], released) < 0) behind.push({ plugin: f.plugin, installed: installed[f.plugin], released });
      }
      return behind.length ? { ok: true, release: name, behind } : { ok: true, release: name, behind, reply: none };
    }
    return { ok: true, release: null, behind: [], reply: `The Plugins scope shows ${email} no release, so the plugins stay as installed from Real Agent's public marketplace. ${none}` };
  }

  /** Copies a file, not a link or a folder, from a full path into a new file directly inside the agent folder. */
  function copyIn(source, newFile) {
    if (!isAbsolute(String(source ?? ""))) return { ok: false, problem: "source_file must be a full path." };
    const free = writeAgentFile(agentFolder, newFile, "", { check: true });
    if (!free.ok) return free;
    let stat;
    try { stat = lstatSync(source); } catch { return { ok: false, problem: `No such file: ${source}` }; }
    if (stat.isSymbolicLink()) return { ok: false, problem: `${source} is a link. Copy the file it points to.` };
    if (!stat.isFile()) return { ok: false, problem: `${source} is not a file.` };
    if (stat.size > MAX_COPY_BYTES) return { ok: false, problem: `${source} is ${stat.size} bytes, over the ${MAX_COPY_BYTES}-byte limit.` };
    const body = readFileSync(source);
    const written = writeAgentFile(agentFolder, newFile, body);
    if (!written.ok) return written;
    return { ok: true, file: written.file, bytes: written.bytes, sha256: createHash("sha256").update(body).digest("hex") };
  }

  async function callTool(name, args) {
    if (!ref || !PROJECT_REF.test(ref))
      return asContent({ ok: false, problem: "SUPABASE_PROJECT_REF is not set to a project reference in this server's settings." });
    if (!email)
      return asContent({ ok: false, problem: "SUPABASE_AUTH_EMAIL is not set to the Auth user's email address in this server's settings." });
    try {
      if (name === "whoami") return asContent(await whoami());
      if (name === "rpc") return asContent(await rpc(args ?? {}));
      if (name === "call_function") return asContent(await callHostedFunction(args ?? {}));
      if (name === "invite_person") return asContent(await invitePerson(args ?? {}));
      if (name === "upload_file") return asContent(await uploadFile(args ?? {}));
      if (name === "list_files") return asContent(await listFiles(args ?? {}));
      if (name === "download_file") return asContent(await downloadFile(args ?? {}));
      if (name === "read_file") return await readFile(args ?? {});
      if (name === "update_plugins") return asContent(await updatePlugins());
      if (name === "check_plugins") {
        const folder = sessionFolderStatus(sessionFolder, { agentFolders, configDir });
        return asContent({ ...await checkPlugins(), ...(folder ? { sessionFolder: folder } : {}) });
      }
      if (name === "copy_to_agent_folder") return asContent(copyIn(args?.source_file, args?.new_file));
      return asContent({ ok: false, problem: `No such tool: ${name}` });
    } catch (err) {
      return asContent({ ok: false, problem: `${name} failed: ${err instanceof Error ? err.message : String(err)}` });
    }
  }

  return { TOOLS, callTool };
}
