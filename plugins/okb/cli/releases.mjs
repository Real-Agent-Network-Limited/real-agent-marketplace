// A client's plugins in their own OKB: the Plugins scope's bucket, `plugins`, holds one folder per
// release, with three files: release.zip, the archive of its files laid out as Real Agent's marketplace is, its MANIFEST
// and MANIFEST.sig. An older release holds each file in its folder, and no release.zip. The Plugins scope holds Real
// Agent's own plugins alone. Each workflow plugin's releases are in a scope of its own, plugins_<workflow>, the plugin's
// name with each hyphen an underscore: each release folder there holds release.zip with plugins/<name> alone, its
// MANIFEST and MANIFEST.sig, and only a person
// whose grants reach that scope sees it. A release counts only once its MANIFEST and MANIFEST.sig are there, when
// MANIFEST.sig is Real Agent's signature of the release's scope, name and MANIFEST by a key in RELEASE_KEYS, and when
// every file the MANIFEST lists matches. okb sync downloads releases from them, and Real Agent's publish-plugin.mjs
// uploads and signs them. Nobody at the client holds Real Agent's key, so nobody there can make a release that counts.
//
// It needs Node alone. Each call takes `access`, `{ url, key, token }`: the project's address, its
// publishable key and a signed-in person's access token. Storage's rules, from the person's grants in
// the Plugins scope, decide what that person may list, download, upload and delete.
import { createHash, createPublicKey, verify } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { deflateRawSync, inflateRawSync } from "node:zlib";

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

/** A release's files in one ZIP archive, beside its MANIFEST and MANIFEST.sig. A release without it holds each file in its folder. */
export const ARCHIVE = "release.zip";
/** The most a release's archive unpacks to, and the most files it holds. zipFiles and every reader keep to both. */
export const ARCHIVE_BYTES = 256 * 1024 * 1024;
export const ARCHIVE_ENTRIES = 0xfffe;

const ZIP_END = 0x06054b50, ZIP_CENTRAL = 0x02014b50, ZIP_LOCAL = 0x04034b50;
// CRC-32, as ZIP uses it. Node's own zlib.crc32 is missing before Node 20.15, and the bootstrap runs on any Node.
const CRC = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc32 = bytes => { let c = 0xffffffff; for (const b of bytes) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };

/**
 * A ZIP archive's bytes, from [path, bytes] pairs: each file deflated, with its checksum, and the index after. Throws when
 * the files unpack to more than limits.bytes, ARCHIVE_BYTES unless given, or number more than ARCHIVE_ENTRIES, as no
 * copy reads such an archive.
 */
export function zipFiles(files, { bytes = ARCHIVE_BYTES } = {}) {
  const list = [...files];
  if (list.length > ARCHIVE_ENTRIES) throw new Error(`The release holds ${list.length} files, more than the ${ARCHIVE_ENTRIES} a copy reads from one archive.`);
  const total = list.reduce((n, [, body]) => n + Buffer.byteLength(body), 0);
  if (total > bytes) throw new Error(`The release's files come to ${total} bytes, more than the ${bytes} a copy unpacks from one archive.`);
  const locals = [], centrals = [];
  let offset = 0;
  for (const [name, body] of list) {
    const data = Buffer.from(body), packed = deflateRawSync(data), path = Buffer.from(name, "utf8"), crc = crc32(data);
    const head = Buffer.alloc(30);
    head.writeUInt32LE(ZIP_LOCAL, 0); head.writeUInt16LE(20, 4); head.writeUInt16LE(0x800, 6); head.writeUInt16LE(8, 8);
    head.writeUInt32LE(crc, 14); head.writeUInt32LE(packed.length, 18); head.writeUInt32LE(data.length, 22); head.writeUInt16LE(path.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(ZIP_CENTRAL, 0); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6); central.writeUInt16LE(0x800, 8); central.writeUInt16LE(8, 10);
    central.writeUInt32LE(crc, 16); central.writeUInt32LE(packed.length, 20); central.writeUInt32LE(data.length, 24); central.writeUInt16LE(path.length, 28); central.writeUInt32LE(offset, 42);
    locals.push(head, path, packed);
    centrals.push(central, path);
    offset += head.length + path.length + packed.length;
  }
  if (centrals.length / 2 >= 0xffff || offset >= 0xffffffff) throw new Error("The release is too large for one archive.");
  const index = Buffer.concat(centrals), end = Buffer.alloc(22);
  end.writeUInt32LE(ZIP_END, 0); end.writeUInt16LE(centrals.length / 2, 8); end.writeUInt16LE(centrals.length / 2, 10); end.writeUInt32LE(index.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, index, end]);
}

class Refused extends Error {}

/**
 * A ZIP archive's files, as { files }, a map from each file's path to its bytes, or { refused } with the reason. A bad
 * archive is a reason, never a throw. limits, { entries, bytes }, caps the number of files and the bytes they unpack to.
 */
export function unzipFiles(bytes, limits) {
  try { return { files: readZip(Buffer.from(bytes), limits) }; }
  catch (err) { return { refused: err instanceof Refused ? err.message : "the archive is damaged" }; }
}

function readZip(bytes, limits) {
  let end = -1;
  for (let at = bytes.length - 22; at >= Math.max(0, bytes.length - 22 - 0xffff); at -= 1) if (bytes.readUInt32LE(at) === ZIP_END) { end = at; break; }
  if (end < 0) throw new Refused("the archive is damaged");
  const count = bytes.readUInt16LE(end + 10), size = bytes.readUInt32LE(end + 12), offset = bytes.readUInt32LE(end + 16);
  if (count === 0xffff || size === 0xffffffff || offset === 0xffffffff) throw new Refused("it is a ZIP64 archive");
  if (offset + size > end) throw new Refused("the archive is damaged");
  const files = new Map();
  let total = 0, at = offset;
  for (let n = 0; n < count; n += 1) {
    if (bytes.readUInt32LE(at) !== ZIP_CENTRAL) throw new Refused("the archive is damaged");
    const flags = bytes.readUInt16LE(at + 8), method = bytes.readUInt16LE(at + 10), crc = bytes.readUInt32LE(at + 16);
    const packed = bytes.readUInt32LE(at + 20), unpacked = bytes.readUInt32LE(at + 24), nameLength = bytes.readUInt16LE(at + 28);
    const local = bytes.readUInt32LE(at + 42);
    const name = bytes.subarray(at + 46, at + 46 + nameLength).toString("utf8");
    at += 46 + nameLength + bytes.readUInt16LE(at + 30) + bytes.readUInt16LE(at + 32);
    if (name.endsWith("/")) continue;
    if (name.startsWith("/") || name.includes("\\") || /^[A-Za-z]:/.test(name) || name.split("/").some(part => part === "" || part === "." || part === "..")) throw new Refused(`it holds ${name}, a path outside the release`);
    if (packed === 0xffffffff || unpacked === 0xffffffff || local === 0xffffffff) throw new Refused("it is a ZIP64 archive");
    if (flags & 1) throw new Refused(`${name} is encrypted`);
    if (method !== 0 && method !== 8) throw new Refused(`${name} uses compression method ${method}`);
    if (files.size + 1 > limits.entries) throw new Refused(`it holds more than ${limits.entries} files`);
    total += unpacked;
    if (total > limits.bytes) throw new Refused(`it unpacks to more than ${limits.bytes} bytes`);
    if (bytes.readUInt32LE(local) !== ZIP_LOCAL) throw new Refused("the archive is damaged");
    const start = local + 30 + bytes.readUInt16LE(local + 26) + bytes.readUInt16LE(local + 28);
    if (start + packed > bytes.length) throw new Refused("the archive is damaged");
    const data = bytes.subarray(start, start + packed);
    const out = method === 0 ? Buffer.from(data) : inflateRawSync(data, { maxOutputLength: Math.max(1, unpacked) });
    if (out.length !== unpacked || crc32(out) !== crc) throw new Refused(`${name} fails its checksum`);
    if (files.has(name)) throw new Refused(`it holds ${name} twice`);
    files.set(name, out);
  }
  return files;
}

/** A release's signature, beside its MANIFEST: the Ed25519 signature of signedBytes(), in base64. */
export const SIGNATURE = "MANIFEST.sig";
/**
 * Real Agent's release signing keys: each public key, its 32 raw bytes in base64, as scripts/sign-upgrade.mjs --new-key
 * prints it. The private key is kept by Real Agent's staff outside the repository, ~/.config/real-agent/release-signing.key.
 * A release counts when its signature verifies against one of these. A new key goes in beside the old one, and the old
 * one leaves once every client's newest release is signed with the new one.
 */
export const RELEASE_KEYS = ["K+gcmzobK/jLl6mH5MI4vUxgO+P40kNGOOahCwFseuM="];

/**
 * The keys a release from the project at url is checked against: RELEASE_KEYS, for every client's project. An address
 * on this computer, where the tests' stand-in for a project runs, takes its keys from OKB_STAND_IN_RELEASE_KEYS,
 * separated by commas.
 */
export function releaseKeysFor(url) {
  let at;
  try { at = new URL(url); } catch { return []; }
  if (at.protocol === "http:" && (at.hostname === "127.0.0.1" || at.hostname === "localhost")) {
    return String(process.env.OKB_STAND_IN_RELEASE_KEYS ?? "").split(",").map(k => k.trim()).filter(Boolean);
  }
  return at.protocol === "https:" ? RELEASE_KEYS : [];
}

/**
 * What a release's signature covers: the line "real-agent-release", the release's scope, its name, and its MANIFEST's
 * bytes, in that order. A signature holds for one release in one scope: the same MANIFEST under another name, or in
 * another scope, fails.
 */
export const signedBytes = (scope, release, manifest) => Buffer.concat([Buffer.from(`${SIGNED_LINE}\n${scope}\n${release}\n`), Buffer.from(manifest)]);
/** The first line of what a release's signature covers. */
export const SIGNED_LINE = "real-agent-release";

/** True when signature, in base64, is the Ed25519 signature of the release named, in its scope, with the MANIFEST bytes, by one of keys. */
export function verifyManifest(bytes, signature, scope, release, keys = []) {
  const covered = signedBytes(scope, release, bytes);
  const text = Buffer.isBuffer(signature) ? signature.toString("utf8").trim() : String(signature ?? "").trim();
  if (!/^[A-Za-z0-9+/]{86}==$/.test(text)) return false;
  const made = Buffer.from(text, "base64");
  return keys.some(key => {
    try { return verify(null, covered, createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x: Buffer.from(key, "base64").toString("base64url") }, format: "jwk" }), made); }
    catch { return false; }
  });
}

/** How long a publish takes at most, in minutes, from the time in its release's name to its signature. */
export const PUBLISH_MINUTES = 30;
/** True when the time in a release's name, which is UTC, is more than PUBLISH_MINUTES before now. */
export function pastPublish(name, now = Date.now()) {
  const m = /^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-/.exec(String(name));
  return !!m && now - Date.UTC(+m[1], m[2] - 1, +m[3], +m[4], +m[5], +m[6]) > PUBLISH_MINUTES * 60_000;
}
/** What a release with no signature gives as its one problem, while its publish may still be under way. */
export const UNSIGNED = `${SIGNATURE} missing`;
/** What a release gives as its one problem when it has had no signature for longer than a publish takes. */
export const NEVER_SIGNED = `${SIGNATURE} missing, more than ${PUBLISH_MINUTES} minutes after its publish began. Real Agent publishes again, or deletes the release`;
/** What a release with no MANIFEST gives as its one problem, while its publish may still be under way. */
export const NO_MANIFEST = "MANIFEST missing";
/** What a release gives as its one problem when it has had no MANIFEST for longer than a publish takes. */
export const NEVER_MANIFEST = `MANIFEST missing, more than ${PUBLISH_MINUTES} minutes after its publish began. Real Agent publishes again, or deletes the release`;
/** What a release whose signature fails gives as its one problem. */
export const BAD_SIGNATURE = `${SIGNATURE} is not Real Agent's signature of this release`;
/** True for the problems of a folder that is not a release yet: a publish under way, with no MANIFEST or no signature. */
export const unfinished = problems => problems.length === 1 && (problems[0] === NO_MANIFEST || problems[0] === UNSIGNED);

/**
 * The paths a MANIFEST lists, each with its hash. Throws on an unreadable line, and on a path that could reach outside
 * the release on any system: one holding a backslash or a colon, or a part that is "..", "." or empty.
 */
export function manifestEntries(text) {
  const entries = [];
  for (const line of String(text).split("\n")) {
    if (!line.trim()) continue;
    const match = /^([0-9a-f]{64}) {2}\.\/(.+)$/.exec(line);
    const path = match?.[2];
    if (!match || /[\\:]/.test(path) || path.split("/").some(part => part === ".." || part === "." || part === "")) throw new Error(`MANIFEST line unreadable: ${line}`);
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
  if (!existsSync(manifest)) return [NO_MANIFEST];
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

/** A release archive's files, as unzipFiles gives them, refused when it holds a file the MANIFEST's entries leave out. */
function unpackRelease(bytes, entries) {
  const unpacked = unzipFiles(bytes, { entries: ARCHIVE_ENTRIES, bytes: ARCHIVE_BYTES });
  if (unpacked.refused) return unpacked;
  const listed = new Set(entries.map(e => e.path));
  const extra = [...unpacked.files.keys()].find(path => !listed.has(path));
  return extra === undefined ? unpacked : { refused: `it holds ${extra}, which the MANIFEST does not list` };
}

/**
 * Some of a release's files, as downloadFile answers for each path, in the order given: from its release.zip, downloaded
 * once, or one at a time for a release without one. A file the archive lacks, or every file of an archive that cannot be
 * read, is missing. The caller checks each file against the MANIFEST.
 */
export async function releaseFiles(access, bucket, name, paths) {
  const archive = await downloadFile(access, bucket, `${name}/${ARCHIVE}`);
  if (!archive.ok && !archive.missing) return paths.map(() => archive);
  if (!archive.ok) return each(paths, path => downloadFile(access, bucket, `${name}/${path}`));
  const unpacked = unzipFiles(archive.body, { entries: ARCHIVE_ENTRIES, bytes: ARCHIVE_BYTES });
  return paths.map(path => (unpacked.files?.has(path) ? { ok: true, body: unpacked.files.get(path) } : { ok: false, missing: true, problem: `${path} is not in ${ARCHIVE}` }));
}

/**
 * Downloads one release, from the Plugins scope or the bucket given, into folder: its MANIFEST and MANIFEST.sig, then its
 * files. The signature is checked against Real Agent's keys before any file is downloaded. A release with release.zip has
 * its files unpacked from it; one without has each file the MANIFEST lists downloaded. Returns the problems found, as
 * check() words them, and [] when the signature verifies and every file is there and matches. An archive that cannot be
 * read, or holds a file the MANIFEST does not list, is one problem.
 */
export async function downloadRelease(access, name, folder, bucket = RELEASES_BUCKET) {
  const manifest = await downloadFile(access, bucket, `${name}/MANIFEST`);
  if (!manifest.ok) return [manifest.missing ? (pastPublish(name) ? NEVER_MANIFEST : NO_MANIFEST) : `MANIFEST could not be downloaded: ${manifest.problem}`];
  const signature = await downloadFile(access, bucket, `${name}/${SIGNATURE}`);
  if (!signature.ok && !signature.missing) return [`${SIGNATURE} could not be downloaded: ${signature.problem}`];
  if (!signature.ok) return [pastPublish(name) ? NEVER_SIGNED : UNSIGNED];
  if (!verifyManifest(manifest.body, signature.body, bucket, name, releaseKeysFor(access.url))) return [BAD_SIGNATURE];
  let entries;
  try { entries = manifestEntries(manifest.body.toString("utf8")); } catch (err) { return [err.message]; }
  mkdirSync(folder, { recursive: true });
  writeFileSync(join(folder, "MANIFEST"), manifest.body);
  writeFileSync(join(folder, SIGNATURE), signature.body);
  const archive = await downloadFile(access, bucket, `${name}/${ARCHIVE}`);
  if (!archive.ok && !archive.missing) return [`${ARCHIVE} could not be downloaded: ${archive.problem}`];
  if (archive.ok) {
    const unpacked = unpackRelease(archive.body, entries);
    if (unpacked.refused) return [`${ARCHIVE} could not be read: ${unpacked.refused}`];
    for (const [path, body] of unpacked.files) {
      const file = join(folder, ...path.split("/"));
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, body);
    }
    return check(folder, bucket);
  }
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

const CONTENT_TYPES = { ".zip": "application/zip", ".mjs": "text/javascript", ".js": "text/javascript", ".json": "application/json", ".md": "text/markdown" };
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
