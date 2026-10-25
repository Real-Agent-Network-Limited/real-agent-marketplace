// A Supabase Auth user's session: the settings file, and the Auth and REST calls made with it.
import { chmodSync, closeSync, constants, existsSync, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync, readdirSync, readFileSync, readSync, realpathSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { basename, dirname, extname, isAbsolute, join, resolve, sep } from "node:path";

export const PROJECT_REF = /^[a-z0-9]{20}$/;
const NAME = /^[A-Za-z_][A-Za-z0-9_]*$/;

/** Rows `rpc` returns at most, so one call cannot flood the agent's context. */
export const ROW_LIMIT = 500;

/** Supabase advises a resumable upload above this size, which these tools do not make. */
export const UPLOAD_LIMIT = 6 * 1024 * 1024;

const BUCKET = /^[a-z0-9][a-z0-9_.-]{0,62}$/;
const CONTENT_TYPES = {
  ".pdf": "application/pdf", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
  ".csv": "text/csv", ".json": "application/json", ".txt": "text/plain", ".md": "text/markdown",
  ".zip": "application/zip",
  ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
};

/** An address that is safe as a file name, compared in lower case. */
const EMAIL = /^[^\s@/\\:*?"<>|]+@[^\s@/\\:*?"<>|]+$/;
export const accountEmail = value => {
  const email = String(value ?? "").trim().toLowerCase();
  return EMAIL.test(email) ? email : null;
};

/** One file per project and Auth user, so two users of a project never share a session. */
export const sessionDir = ref => join(homedir(), ".config", "supabase-auth", ref);
export const sessionPath = (ref, email) => join(sessionDir(ref), `${email}.json`);

/** Plain http only for this computer, where the tests' stand-in for Supabase runs. */
export function projectUrl(value) {
  let url;
  try { url = new URL(String(value).trim()); } catch { return null; }
  const local = url.hostname === "127.0.0.1" || url.hostname === "localhost";
  if (url.protocol !== "https:" && !(local && url.protocol === "http:")) return null;
  return url.origin;
}

/** The reference is the first part of `https://<ref>.supabase.co`. */
export function refFromUrl(url) {
  const [first, ...rest] = new URL(url).hostname.split(".");
  return PROJECT_REF.test(first) && rest.join(".") === "supabase.co" ? first : null;
}

export function readSession(ref, email) {
  const path = sessionPath(ref, email);
  if (!existsSync(path)) return null;
  const stat = lstatSync(path);
  if (stat.isSymbolicLink() || (process.platform !== "win32" && (stat.mode & 0o077) !== 0))
    throw new Error(`${path} is readable by other users or is a link. Delete it and sign in again.`);
  const value = JSON.parse(readFileSync(path, "utf-8"));
  const fields = ["url", "publishableKey", "email", "refreshToken"];
  if (value?.version !== 1 || !fields.every(one => typeof value[one] === "string" && value[one]) || !projectUrl(value.url))
    throw new Error(`${path} is not a valid session file. Delete it and sign in again.`);
  if (accountEmail(value.email) !== email) throw new Error(`${path} holds a session for ${value.email}. Delete it and sign in again.`);
  return value;
}

/** Written to a private temporary file, then renamed, so a reader never sees half a file. */
export function writeSession(ref, email, session) {
  const dir = sessionDir(ref);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  chmodSync(dirname(dir), 0o700);
  chmodSync(dir, 0o700);
  const target = sessionPath(ref, email);
  if (existsSync(target) && lstatSync(target).isSymbolicLink()) throw new Error(`${target} is a link. Delete it and sign in again.`);
  const temporary = join(dir, `.${process.pid}.${randomUUID()}.tmp`);
  const fd = openSync(temporary, "wx", 0o600);
  try {
    writeFileSync(fd, JSON.stringify({ version: 1, ...session }, null, 2) + "\n");
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  try { renameSync(temporary, target); }
  catch (err) { rmSync(temporary, { force: true }); throw err; }
  return target;
}

/** Supabase's own sentence, a hosted function's problem, or the status when it gave none. With keepBody, a
 * refusal also carries its parsed reply whole, as body. */
async function answer(response, { keepBody = false } = {}) {
  const text = await response.text();
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  if (response.ok) return { ok: true, body };
  const said = body?.msg ?? body?.message ?? body?.error_description ?? body?.error ?? body?.problem;
  const failed = { ok: false, status: response.status, code: body?.error_code ?? body?.code, problem: typeof said === "string" ? said : `HTTP ${response.status}` };
  return keepBody && body !== null ? { ...failed, body } : failed;
}

const headers = (key, token) => ({
  apikey: key,
  "Content-Type": "application/json",
  ...(token ? { Authorization: `Bearer ${token}` } : {}),
});

export async function passwordSignIn(url, key, email, password) {
  return answer(await fetch(`${url}/auth/v1/token?grant_type=password`, { method: "POST", headers: headers(key), body: JSON.stringify({ email, password }) }));
}

export async function refreshSession(url, key, refreshToken) {
  return answer(await fetch(`${url}/auth/v1/token?grant_type=refresh_token`, { method: "POST", headers: headers(key), body: JSON.stringify({ refresh_token: refreshToken }) }));
}

export async function setPassword(url, key, accessToken, password) {
  return answer(await fetch(`${url}/auth/v1/user`, { method: "PUT", headers: headers(key, accessToken), body: JSON.stringify({ password }) }));
}

export async function currentUser(url, key, accessToken) {
  return answer(await fetch(`${url}/auth/v1/user`, { headers: headers(key, accessToken) }));
}

/** One function in one exposed schema, with named arguments, under the signed-in user's rights. OKB answers a
 * permission refusal, which it logs as change_refused, as { refused: true, problem }: that is the refusal it
 * raised before, with its 403, code and sentence. A move preview's own refused list is a result. */
export async function callRpc(url, key, accessToken, fn, schema, args = {}) {
  if (!NAME.test(String(fn))) return { ok: false, problem: `Not a function name: ${fn}` };
  if (schema !== undefined && !NAME.test(String(schema))) return { ok: false, problem: `Not a schema name: ${schema}` };
  if (args === null || typeof args !== "object" || Array.isArray(args)) return { ok: false, problem: "args must be an object of named arguments." };
  const profile = schema ? { "Content-Profile": schema, "Accept-Profile": schema } : {};
  const result = await answer(await fetch(`${url}/rest/v1/rpc/${fn}`, { method: "POST", headers: { ...headers(key, accessToken), ...profile }, body: JSON.stringify(args) }));
  if (result.ok && result.body?.refused === true)
    return { ok: false, status: 403, code: "42501", problem: typeof result.body.problem === "string" ? result.body.problem : "Refused" };
  if (result.ok && Array.isArray(result.body) && result.body.length > ROW_LIMIT)
    return { ok: true, body: result.body.slice(0, ROW_LIMIT), truncated: `first ${ROW_LIMIT} of ${result.body.length} rows` };
  return result;
}

const FUNCTION = /^[a-z0-9][a-z0-9_-]{0,62}$/;

/** One of the project's hosted functions, with a JSON body, as the signed-in user. */
export async function callFunction(url, key, accessToken, name, body = {}) {
  if (!FUNCTION.test(String(name))) return { ok: false, problem: `Not a hosted function name: ${name}` };
  if (body === null || typeof body !== "object" || Array.isArray(body)) return { ok: false, problem: "body must be a JSON object." };
  return answer(await fetch(`${url}/functions/v1/${name}`, { method: "POST", headers: headers(key, accessToken), body: JSON.stringify(body) }), { keepBody: true });
}

/** A path inside a bucket, each part encoded, or null when a part could climb out or is empty. */
function objectPath(path, { folder = false } = {}) {
  const value = String(path ?? "");
  if (value.length > 1024 || value.startsWith("/")) return null;
  const parts = (folder ? value.replace(/\/$/, "") : value).split("/");
  if (folder && value === "") return "";
  if (parts.some(part => part === "" || part === "." || part === "..")) return null;
  return parts.map(encodeURIComponent).join("/");
}

/** The most file names whoami gives, so a full agent folder keeps its reply short. */
export const AGENT_FILES_LIMIT = 50;

/** The files directly inside the agent folder, which upload_file may send: no folders, links or hidden
 * files. `names` holds the newest `limit` of them, newest first, and `count` how many there are. Null
 * with no folder set, or one that cannot be read. */
export function agentFiles(folder, limit = AGENT_FILES_LIMIT) {
  if (!folder) return null;
  let files;
  try {
    files = readdirSync(folder, { withFileTypes: true }).filter(entry => entry.isFile() && !entry.name.startsWith("."));
  } catch {
    return null;
  }
  const changed = name => { try { return lstatSync(join(folder, name)).mtimeMs; } catch { return 0; } };
  const names = files.map(entry => ({ name: entry.name, at: changed(entry.name) }))
    .sort((a, b) => b.at - a.at || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
    .slice(0, limit)
    .map(one => one.name);
  return { names, count: files.length };
}

// Windows paths ignore letter case, so there a folder typed in any case is the same folder.
const samePath = (one, other) => process.platform === "win32" ? one.toLowerCase() === other.toLowerCase() : one === other;

/**
 * The bytes of one file directly inside the agent folder, as folderFile reads it, with its content
 * type. A hidden file is refused.
 */
export function uploadSource(folder, file, contentType) {
  if (folder && basename(String(file ?? "")).startsWith(".")) return { ok: false, problem: `${file} is hidden. Only files directly inside ${folder} that are not hidden can be uploaded.` };
  const source = folderFile(folder, file, { kind: "agent", limit: UPLOAD_LIMIT, action: "uploaded" });
  if (!source.ok) return source;
  const type = contentType ?? CONTENT_TYPES[extname(source.name).toLowerCase()] ?? "application/octet-stream";
  return { ...source, contentType: type };
}

/**
 * Where one path inside the agent folder is: `{ ok: true, root, name, path, parts }`,
 * with `path` under the folder's resolved path. Directly inside the folder only, unless `nested`,
 * which also takes a path in a folder within it, at any depth, and the folder itself (`parts` is
 * empty). With `nested`, each folder on the way is checked not to be a link and not to be hidden;
 * accepted as a best effort, as for the folder itself. `kind` names the folder in each refusal.
 */
export function folderPath(folder, file, { kind, nested = false, action = "read" }) {
  const where = `${kind} folder`;
  const only = nested ? `Only files and folders inside ${folder}` : "Only files directly inside it";
  if (!folder) return { ok: false, problem: `No ${where} is set for this agent. The person sets ${kind}_folder in the okb plugin's settings.` };
  if (!isAbsolute(String(file ?? ""))) return { ok: false, problem: `The file must be given as a full path inside ${folder}.` };
  let root;
  // Accepted: whoever can replace this folder or its parents can copy any file in anyway.
  try { root = realpathSync.native(folder); } catch { return { ok: false, problem: `The ${where} ${folder} does not exist.` }; }
  const target = resolve(file);
  const base = [resolve(folder), root].find(one => samePath(target, one) || samePath(target.slice(0, one.length + 1), one + sep));
  if (base === undefined) return { ok: false, problem: `${file} is outside the ${where}, ${folder}. ${only} can be ${action}.` };
  const parts = target.slice(base.length + 1).split(sep).filter(Boolean);
  if (!nested && parts.length !== 1) {
    return { ok: false, problem: `${file} is ${parts.length ? "in a folder within" : "outside"} the ${where}, ${folder}. ${only} can be ${action}.` };
  }
  if (nested && parts.some(part => part.startsWith("."))) return { ok: false, problem: `${file} is hidden, or in a hidden folder. Only files and folders inside ${folder} that are not hidden can be ${action}.` };
  for (let depth = 1; depth < parts.length; depth++) {
    const on = join(root, ...parts.slice(0, depth));
    let named;
    try { named = lstatSync(on); } catch { return { ok: false, problem: `No such folder: ${join(base, ...parts.slice(0, depth))}` }; }
    if (named.isSymbolicLink()) return { ok: false, problem: `${join(base, ...parts.slice(0, depth))} is a link. ${only} can be ${action}.` };
    if (!named.isDirectory()) return { ok: false, problem: `${join(base, ...parts.slice(0, depth))} is not a folder.` };
  }
  const linked = nested ? only : `Only files directly inside ${folder}`;
  return { ok: true, root, name: parts.at(-1) ?? basename(root), path: join(root, ...parts), parts, linked, action };
}

/**
 * The bytes of one regular file directly inside the agent folder, with its name,
 * or with `nested`, anywhere inside the folder, as folderPath finds it. The file is opened by the
 * folder's resolved path and its own name, never following a link; the read goes only through that
 * handle. Refuses a link, a folder, anything but a regular file, and a file over `limit`. Opening
 * does not wait, so a named pipe is refused rather than hanging the server.
 */
export function folderFile(folder, file, { kind, limit, nested = false, action: verb }) {
  const found = folderPath(folder, file, { kind, nested, action: verb });
  if (!found.ok) return found;
  const { name, path, linked, action } = found;
  if (!found.parts.length) return { ok: false, problem: `${file} is not a file.` };
  // Where the open cannot refuse a link itself (Windows has no O_NOFOLLOW), refuse one by name first, as a best effort.
  if (constants.O_NOFOLLOW === undefined) {
    let named;
    try { named = lstatSync(path); } catch { return { ok: false, problem: `No such file: ${file}` }; }
    if (named.isSymbolicLink()) return { ok: false, problem: `${file} is a link. ${linked} can be ${action}.` };
  }
  let fd;
  // O_NONBLOCK, so opening a pipe cannot block the server; it has no effect on a regular file.
  try { fd = openSync(path, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0) | (constants.O_NONBLOCK ?? 0)); }
  catch (err) {
    if (err?.code === "ELOOP" || err?.code === "EMLINK") return { ok: false, problem: `${file} is a link. ${linked} can be ${action}.` };
    if (err?.code === "EACCES" || err?.code === "EPERM") return { ok: false, problem: `${file} cannot be read by this agent.` };
    if (err?.code === "ENOENT") return { ok: false, problem: `No such file: ${file}` };
    return { ok: false, problem: `${file} could not be opened: ${err?.message ?? err}` };
  }
  try {
    const opened = fstatSync(fd);
    if (!opened.isFile()) return { ok: false, problem: `${file} is not a file.` };
    const most = `${limit / (1024 * 1024)} MB`;
    if (opened.size > limit) return { ok: false, problem: `${file} is over ${most}, the largest file these tools ${found.action === "uploaded" ? "upload" : "read"}.` };
    // Read one byte past the checked size, so a file that grew after the check is refused.
    const buffer = Buffer.allocUnsafe(opened.size + 1);
    let length = 0, read;
    while (length < buffer.length && (read = readSync(fd, buffer, length, buffer.length - length, null)) > 0) length += read;
    if (length !== opened.size) return { ok: false, problem: `${file} changed while it was being read. Try again.` };
    return { ok: true, name, body: buffer.subarray(0, length) };
  } finally {
    closeSync(fd);
  }
}

/** The JSON in one file directly inside the agent folder, read as folderFile reads it. */
export function agentJson(folder, file) {
  if (!folder) return { ok: false, problem: "No agent folder is set for this agent. The person sets agent_folder in the okb plugin's settings." };
  const source = folderFile(folder, file, { kind: "agent", limit: UPLOAD_LIMIT });
  if (!source.ok) return source;
  try {
    return { ok: true, value: JSON.parse(source.body.toString("utf-8")) };
  } catch (err) {
    return { ok: false, problem: `${file} is not JSON: ${err instanceof Error ? err.message : String(err)}` };
  }
}

/**
 * Writes text, or bytes, to a new file directly inside the agent folder. Refuses a file that already
 * exists, a link, and any place outside the folder, as uploadSource does; the file is created in
 * the same step as the check that it did not exist, so nothing already there is replaced.
 */
export function writeAgentFile(folder, file, text, { check = false } = {}) {
  if (!folder) return { ok: false, problem: "No agent folder is set for this agent. The person sets agent_folder in the okb plugin's settings." };
  if (!isAbsolute(String(file ?? ""))) return { ok: false, problem: `The file must be given as a full path inside ${folder}.` };
  let root;
  try { root = realpathSync.native(folder); } catch { return { ok: false, problem: `The agent folder ${folder} does not exist.` }; }
  const name = basename(file);
  const parent = resolve(dirname(file));
  if (!samePath(parent, resolve(folder)) && !samePath(parent, root) || name === "" || name === "." || name === ".." || name.startsWith(".")) {
    return { ok: false, problem: `${file} is not a file name directly inside the agent folder, ${folder}.` };
  }
  if (check) {
    // Asked before a call, so a result with nowhere to go is refused before anything is sent.
    try { lstatSync(join(root, name)); return { ok: false, problem: `${file} already exists. Name a new file; nothing is replaced.` }; }
    catch (err) { if (err?.code !== "ENOENT") return { ok: false, problem: `${file} could not be checked: ${err?.message ?? err}` }; }
    return { ok: true };
  }
  let fd;
  try { fd = openSync(join(root, name), constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0), 0o600); }
  catch (err) {
    if (err?.code === "EEXIST") return { ok: false, problem: `${file} already exists. Name a new file; nothing is replaced.` };
    return { ok: false, problem: `${file} could not be written: ${err?.message ?? err}` };
  }
  try {
    writeFileSync(fd, text);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  return { ok: true, file: join(parent, name), bytes: Buffer.byteLength(text) };
}

/**
 * Puts a value into an object at a JSON pointer (RFC 6901), such as `/p_request/payload`. The
 * pointer's parent must already be an object in it; the empty pointer replaces the whole object.
 */
export function placeAt(target, pointer, value) {
  if (pointer === "") {
    if (value === null || typeof value !== "object" || Array.isArray(value)) return { ok: false, problem: "A file placed at the empty pointer must hold a JSON object." };
    return { ok: true, value };
  }
  if (!String(pointer).startsWith("/")) return { ok: false, problem: `Not a JSON pointer: ${pointer}` };
  const keys = pointer.slice(1).split("/").map(part => part.replaceAll("~1", "/").replaceAll("~0", "~"));
  const copy = structuredClone(target);
  let place = copy;
  for (const key of keys.slice(0, -1)) {
    if (place === null || typeof place !== "object" || Array.isArray(place) || !(key in place)) return { ok: false, problem: `${pointer} does not lead to a place in args.` };
    place = place[key];
  }
  if (place === null || typeof place !== "object" || Array.isArray(place)) return { ok: false, problem: `${pointer} does not lead to a place in args.` };
  place[keys.at(-1)] = value;
  return { ok: true, value: copy };
}

/** One file into one bucket, under the signed-in user's storage policies. */
export async function uploadObject(url, key, accessToken, bucket, path, body, contentType, overwrite = false) {
  if (!BUCKET.test(String(bucket))) return { ok: false, problem: `Not a bucket name: ${bucket}` };
  const encoded = objectPath(path);
  if (!encoded) return { ok: false, problem: `Not a path inside a bucket: ${path}` };
  return answer(await fetch(`${url}/storage/v1/object/${bucket}/${encoded}`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${accessToken}`, "Content-Type": contentType, "x-upsert": overwrite ? "true" : "false" },
    body,
  }));
}

/** The files under one folder of a bucket that the signed-in user may see. A missing bucket lists nothing. */
export async function listObjects(url, key, accessToken, bucket, prefix = "") {
  if (!BUCKET.test(String(bucket))) return { ok: false, problem: `Not a bucket name: ${bucket}` };
  if (objectPath(prefix, { folder: true }) === null) return { ok: false, problem: `Not a folder inside a bucket: ${prefix}` };
  const result = await answer(await fetch(`${url}/storage/v1/object/list/${bucket}`, {
    method: "POST",
    headers: headers(key, accessToken),
    body: JSON.stringify({ prefix: String(prefix ?? "").replace(/\/$/, ""), limit: ROW_LIMIT + 1 }),
  }));
  if (!result.ok || !Array.isArray(result.body)) return result;
  // Supabase lists a subfolder as an entry with no id.
  const files = result.body.map(one => ({ name: one.name, folder: one.id === null, size: one.metadata?.size ?? null, updated: one.updated_at ?? null }));
  if (files.length > ROW_LIMIT) return { ok: true, body: files.slice(0, ROW_LIMIT), truncated: `first ${ROW_LIMIT} entries` };
  return { ok: true, body: files };
}

/**
 * One file from one bucket, under the signed-in user's storage policies. An answer over the limit
 * is refused, by its stated length or once its body passes the limit, and nothing of it is kept.
 */
export async function downloadObject(url, key, accessToken, bucket, path, limit) {
  if (!BUCKET.test(String(bucket))) return { ok: false, problem: `Not a bucket name: ${bucket}` };
  const encoded = objectPath(path);
  if (!encoded) return { ok: false, problem: `Not a path inside a bucket: ${path}` };
  const response = await fetch(`${url}/storage/v1/object/authenticated/${bucket}/${encoded}`, {
    headers: { apikey: key, Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) return answer(response);
  const most = `${limit / (1024 * 1024)} MB`;
  const tooLarge = { ok: false, problem: `${bucket}/${path} is over ${most}, the largest file download_file downloads.` };
  if (Number(response.headers.get("content-length")) > limit) { await response.body?.cancel(); return tooLarge; }
  const parts = [];
  let length = 0;
  for await (const part of response.body ?? []) {
    length += part.length;
    if (length > limit) return tooLarge;
    parts.push(part);
  }
  return { ok: true, body: Buffer.concat(parts, length), contentType: response.headers.get("content-type") };
}
