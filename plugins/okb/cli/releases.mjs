// A client's plugins in their own OKB: the Plugins scope's bucket, `plugins`, holds one folder per
// release, laid out as Real Agent's marketplace is, with its MANIFEST, and holds Real Agent's own plugins
// alone. Each workflow plugin's releases are in a scope of its own, plugins_<workflow>, the plugin's name with
// each hyphen an underscore: each release folder there holds plugins/<name> and its MANIFEST, and only a person
// whose grants reach that scope sees it. A release counts only once its MANIFEST is there, and only when every
// file it lists matches. okb sync downloads releases from them, and Real Agent's publish-plugin.mjs uploads them.
//
// It needs Node alone. Each call takes `access`, `{ url, key, token }`: the project's address, its
// publishable key and a signed-in person's access token. Storage's rules, from the person's grants in
// the Plugins scope, decide what that person may list, download, upload and delete.
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

/** A release folder's name: the second it was made, in UTC, and the start of a hash of its files. */
export const RELEASE_NAME = /^\d{8}-\d{6}-[0-9a-f]{7,40}$/;
export const RELEASES_BUCKET = "plugins";
/** Real Agent's own plugins, which okb sync takes only from the Plugins scope, never from a workflow plugin's scope. */
export const OWN_PLUGIN_NAMES = ["real-agent", "okb", "business-analyst", "real-agent-project"];
/** The start of the code of each workflow plugin's own scope. */
export const PLUGIN_SCOPE_PREFIX = "plugins_";
/** A workflow plugin's own scope: plugins_ and its name, each hyphen an underscore. */
export const pluginScope = name => `${PLUGIN_SCOPE_PREFIX}${String(name).replaceAll("-", "_")}`;
/** True for a workflow plugin's own scope's code. */
export const isPluginScope = code => typeof code === "string" && code.startsWith(PLUGIN_SCOPE_PREFIX) && code.length > PLUGIN_SCOPE_PREFIX.length;
/** The marketplace's name, which every release's marketplace.json carries, and every plugin id ends with. */
export const MARKETPLACE_NAME = "real-agent";
const PAGE = 1000;
// Storage refuses a burst of requests on a small project, with "Too many connections issued to the database".
// A few at a time, and each failure that is not a refusal or a missing file tried again after a wait.
const AT_ONCE = 4;
const TRIES = 5;
const WAIT_MS = () => Number(process.env.OKB_RETRY_MS ?? 500);

export const sha256 = bytes => createHash("sha256").update(bytes).digest("hex");

/** The paths a MANIFEST lists, each with its hash. Throws on an unreadable line. */
export function manifestEntries(text) {
  const entries = [];
  for (const line of String(text).split("\n")) {
    if (!line.trim()) continue;
    const match = /^([0-9a-f]{64}) {2}\.\/(.+)$/.exec(line);
    const path = match?.[2];
    if (!match || path.split("/").some(part => part === ".." || part === "." || part === "")) throw new Error(`MANIFEST line unreadable: ${line}`);
    entries.push({ hash: match[1], path });
  }
  return entries;
}

/** The one plugin a workflow release's MANIFEST lists files of, or null when it lists none or more than one. */
export function workflowPlugin(text) {
  let entries;
  try { entries = manifestEntries(text); } catch { return null; }
  const names = new Set(entries.map(e => /^plugins\/([a-z0-9]+(?:-[a-z0-9]+)*)\//.exec(e.path)?.[1] ?? ""));
  const [name] = names;
  return names.size === 1 && name ? name : null;
}

/**
 * Each manifest line that does not match the copy in folder, as "<path> missing" or "<path> changed". A release
 * in the Plugins scope must name the real-agent marketplace; one in a workflow plugin's scope, bucket, must hold
 * that one plugin alone, with its plugin.json.
 */
export function check(folder, bucket = RELEASES_BUCKET) {
  const manifest = join(folder, "MANIFEST");
  if (!existsSync(manifest)) return ["MANIFEST missing"];
  const problems = [];
  for (const line of readFileSync(manifest, "utf8").split("\n")) {
    if (!line.trim()) continue;
    let entry;
    try { [entry] = manifestEntries(line); } catch (err) { problems.push(err.message); continue; }
    const file = join(folder, ...entry.path.split("/"));
    if (!existsSync(file)) { problems.push(`./${entry.path} missing`); continue; }
    if (sha256(readFileSync(file)) !== entry.hash) problems.push(`./${entry.path} changed`);
  }
  if (!problems.length && bucket === RELEASES_BUCKET) {
    let name;
    try { name = JSON.parse(readFileSync(join(folder, ".claude-plugin", "marketplace.json"), "utf8")).name; } catch { name = undefined; }
    if (name !== MARKETPLACE_NAME) problems.push(`./.claude-plugin/marketplace.json names the marketplace ${JSON.stringify(name)}, not ${MARKETPLACE_NAME}`);
  } else if (!problems.length) {
    const plugin = workflowPlugin(readFileSync(manifest, "utf8"));
    if (!plugin || pluginScope(plugin) !== bucket) problems.push(`it holds files outside plugins/<name>, for the one plugin the ${bucket} scope keeps`);
    else if (!existsSync(join(folder, "plugins", plugin, ".claude-plugin", "plugin.json"))) problems.push(`./plugins/${plugin}/.claude-plugin/plugin.json missing`);
  }
  return problems;
}

/** Supabase's own sentence, or the status when it gave none. Storage answers a missing file with 400 and statusCode 404. */
async function answer(response) {
  const text = await response.text();
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  if (response.ok) return { ok: true, body };
  const said = body?.msg ?? body?.message ?? body?.error_description ?? body?.error;
  const missing = response.status === 404 || String(body?.statusCode) === "404";
  return { ok: false, status: response.status, missing, problem: typeof said === "string" ? said : `HTTP ${response.status}` };
}

/** A fetch whose failure to connect is an answer, naming the address. */
async function call(url, options) {
  try { return await fetch(url, options); }
  catch (err) { return { failed: `OKB at ${new URL(url).origin} could not be reached: ${err?.cause?.code ?? err?.message ?? err}` }; }
}
/** True for an answer worth asking again: not a success, a missing file, or a refusal. */
const passing = got => !got.ok && !got.missing && ![400, 401, 403, 409].includes(got.status)
  && !/row-level security|already exists|Invalid API key|JWT/i.test(String(got.problem));

/** Runs attempt until its answer is not passing, or TRIES times, waiting longer before each try. */
async function again(attempt) {
  let got;
  for (let i = 0; i < TRIES; i++) {
    if (i) await new Promise(done => setTimeout(done, WAIT_MS() * 2 ** (i - 1)));
    got = await attempt();
    if (!passing(got)) return got;
  }
  return got;
}

const ask = (url, options) => again(async () => {
  const response = await call(url, options);
  return response.failed ? { ok: false, problem: response.failed } : answer(response);
});

const encode = path => path.split("/").map(encodeURIComponent).join("/");
const auth = access => ({ apikey: access.key, Authorization: `Bearer ${access.token}` });

/** The entries directly inside one folder of a bucket, as { name, folder }, every page of them. */
export async function listFolder(access, bucket, prefix = "") {
  const entries = [];
  for (let offset = 0; ; offset += PAGE) {
    const got = await ask(`${access.url}/storage/v1/object/list/${bucket}`, {
      method: "POST",
      headers: { ...auth(access), "Content-Type": "application/json" },
      body: JSON.stringify({ prefix, limit: PAGE, offset, sortBy: { column: "name", order: "asc" } }),
    });
    if (!got.ok) return got;
    if (!Array.isArray(got.body)) return { ok: false, problem: `Storage's list of ${bucket} was not a list.` };
    // Storage lists a subfolder as an entry with no id.
    entries.push(...got.body.filter(one => one.name !== ".emptyFolderPlaceholder").map(one => ({ name: one.name, folder: one.id === null })));
    if (got.body.length < PAGE) return { ok: true, entries };
  }
}

/** Every file under a folder of a bucket, at any depth, as paths from the bucket's root. */
export async function listFiles(access, bucket, prefix) {
  const listed = await listFolder(access, bucket, prefix);
  if (!listed.ok) return listed;
  const paths = [];
  for (const entry of listed.entries) {
    const path = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (!entry.folder) { paths.push(path); continue; }
    const under = await listFiles(access, bucket, path);
    if (!under.ok) return under;
    paths.push(...under.paths);
  }
  return { ok: true, paths };
}

/** The release folders in the Plugins scope, or in the bucket given, newest first, whether or not each has its MANIFEST. */
export async function listReleases(access, bucket = RELEASES_BUCKET) {
  const listed = await listFolder(access, bucket, "");
  if (!listed.ok) return listed;
  return { ok: true, names: listed.entries.filter(e => e.folder && RELEASE_NAME.test(e.name)).map(e => e.name).sort().reverse() };
}

/** One file's bytes. A missing file is { ok: false, missing: true }. */
export function downloadFile(access, bucket, path) {
  return again(() => downloadOnce(access, bucket, path));
}

async function downloadOnce(access, bucket, path) {
  const response = await call(`${access.url}/storage/v1/object/authenticated/${bucket}/${encode(path)}`, { headers: auth(access) });
  if (response.failed) return { ok: false, problem: response.failed };
  if (!response.ok) return answer(response);
  try { return { ok: true, body: Buffer.from(await response.arrayBuffer()) }; }
  catch (err) { return { ok: false, problem: `the download stopped: ${err?.cause?.code ?? err?.message ?? err}` }; }
}

/** Runs work on each item, a few at a time, and returns the results in order. */
async function each(items, work) {
  const results = new Array(items.length);
  let next = 0;
  const worker = async () => { while (next < items.length) { const i = next++; results[i] = await work(items[i], i); } };
  await Promise.all(Array.from({ length: Math.min(AT_ONCE, items.length) }, worker));
  return results;
}

/**
 * Downloads one release, from the Plugins scope or the bucket given, into folder: its MANIFEST, then each file
 * the MANIFEST lists. Returns the problems found, as check() words them, and [] when every file is there and matches.
 */
export async function downloadRelease(access, name, folder, bucket = RELEASES_BUCKET) {
  const manifest = await downloadFile(access, bucket, `${name}/MANIFEST`);
  if (!manifest.ok) return [manifest.missing ? "MANIFEST missing" : `MANIFEST could not be downloaded: ${manifest.problem}`];
  let entries;
  try { entries = manifestEntries(manifest.body.toString("utf8")); } catch (err) { return [err.message]; }
  mkdirSync(folder, { recursive: true });
  writeFileSync(join(folder, "MANIFEST"), manifest.body);
  const problems = await each(entries, async ({ path }) => {
    const got = await downloadFile(access, bucket, `${name}/${path}`);
    if (!got.ok) return got.missing ? `./${path} missing` : `./${path} could not be downloaded: ${got.problem}`;
    const file = join(folder, ...path.split("/"));
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, got.body);
    return null;
  });
  const failed = problems.filter(Boolean);
  return failed.length ? failed : check(folder, bucket);
}

const CONTENT_TYPES = { ".mjs": "text/javascript", ".js": "text/javascript", ".json": "application/json", ".md": "text/markdown" };
const contentType = path => CONTENT_TYPES[/\.[^./]+$/.exec(path)?.[0] ?? ""] ?? "application/octet-stream";

/** Uploads one file, replacing one already there when upsert is true. */
export function uploadFile(access, bucket, path, body, { upsert = false } = {}) {
  return ask(`${access.url}/storage/v1/object/${bucket}/${encode(path)}`, {
    method: "POST",
    headers: { ...auth(access), "Content-Type": contentType(path), "x-upsert": upsert ? "true" : "false" },
    body,
  });
}

/** Uploads many files, a few at a time. Returns the first failure, with its path, or { ok: true }. */
export async function uploadFiles(access, bucket, files, options) {
  const results = await each(files, ([path, body]) => uploadFile(access, bucket, path, body, options).then(r => (r.ok ? r : { ...r, path })));
  return results.find(r => !r.ok) ?? { ok: true };
}

/** Deletes the files named, by their paths from the bucket's root. Returns how many Storage deleted. */
export async function deleteFiles(access, bucket, paths) {
  let deleted = 0;
  for (let i = 0; i < paths.length; i += PAGE) {
    const got = await ask(`${access.url}/storage/v1/object/${bucket}`, {
      method: "DELETE",
      headers: { ...auth(access), "Content-Type": "application/json" },
      body: JSON.stringify({ prefixes: paths.slice(i, i + PAGE) }),
    });
    if (!got.ok) return got;
    deleted += Array.isArray(got.body) ? got.body.length : 0;
  }
  return { ok: true, deleted };
}

/** Deletes a release folder and every file in it, in the Plugins scope or the bucket given. Returns { ok, deleted, of }:
 * how many Storage deleted, of how many listed. */
export async function deleteRelease(access, name, bucket = RELEASES_BUCKET) {
  const listed = await listFiles(access, bucket, name);
  if (!listed.ok) return listed;
  const gone = await deleteFiles(access, bucket, listed.paths);
  return gone.ok ? { ...gone, of: listed.paths.length } : gone;
}
