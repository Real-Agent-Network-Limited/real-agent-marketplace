// A ZIP archive's files, read from the archive's own index with Node alone, so an Office file's XML
// parts can be read without npm packages. An archive written with data descriptors reads the same.
import { inflateRawSync } from "node:zlib";

const END = 0x06054b50;
const CENTRAL = 0x02014b50;
const LOCAL = 0x04034b50;
/** The end record is 22 bytes and its comment at most 65,535. */
const END_SEARCH = 22 + 0xffff;

class Refused extends Error {}

/** CRC-32, as ZIP uses it. Node's own `zlib.crc32` is missing before Node 20.15. */
const TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(bytes) {
  let c = 0xffffffff;
  for (const byte of bytes) c = TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/**
 * The archive's files as a map from each file's path to its bytes, or `{ refused }` with the reason.
 * A bad archive is a reason, never a throw. `limits` caps the number of files and the unpacked bytes.
 */
export function unzip(bytes, limits) {
  try {
    return { files: read(bytes, limits) };
  } catch (err) {
    return { refused: err instanceof Refused ? err.message : "the archive is damaged" };
  }
}

function read(bytes, limits) {
  const end = findEnd(bytes);
  const count = bytes.readUInt16LE(end + 10);
  const size = bytes.readUInt32LE(end + 12);
  const offset = bytes.readUInt32LE(end + 16);
  if (count === 0xffff || size === 0xffffffff || offset === 0xffffffff) throw new Refused("it is a ZIP64 archive");
  if (offset + size > end) throw new Refused("the archive is damaged");

  const files = new Map();
  let total = 0;
  let at = offset;
  for (let n = 0; n < count; n += 1) {
    if (bytes.readUInt32LE(at) !== CENTRAL) throw new Refused("the archive is damaged");
    const flags = bytes.readUInt16LE(at + 8);
    const method = bytes.readUInt16LE(at + 10);
    const crc = bytes.readUInt32LE(at + 16);
    const packed = bytes.readUInt32LE(at + 20);
    const unpacked = bytes.readUInt32LE(at + 24);
    const nameLength = bytes.readUInt16LE(at + 28);
    const next = at + 46 + nameLength + bytes.readUInt16LE(at + 30) + bytes.readUInt16LE(at + 32);
    const local = bytes.readUInt32LE(at + 42);
    const name = bytes.subarray(at + 46, at + 46 + nameLength).toString("utf8");
    at = next;

    if (name.endsWith("/")) continue;
    if (packed === 0xffffffff || unpacked === 0xffffffff || local === 0xffffffff) throw new Refused("it is a ZIP64 archive");
    if (flags & 1) throw new Refused(`${name} is encrypted`);
    if (method !== 0 && method !== 8) throw new Refused(`${name} uses compression method ${method}`);
    if (files.size + 1 > limits.entries) throw new Refused(`it holds more than ${limits.entries} files`);
    total += unpacked;
    if (total > limits.bytes) throw new Refused(`it unpacks to more than ${limits.bytes} bytes`);

    if (bytes.readUInt32LE(local) !== LOCAL) throw new Refused("the archive is damaged");
    const start = local + 30 + bytes.readUInt16LE(local + 26) + bytes.readUInt16LE(local + 28);
    if (start + packed > bytes.length) throw new Refused("the archive is damaged");
    const data = bytes.subarray(start, start + packed);
    const out = method === 0 ? Buffer.from(data) : inflateRawSync(data, { maxOutputLength: Math.max(1, unpacked) });
    if (out.length !== unpacked || crc32(out) !== crc) throw new Refused(`${name} fails its checksum`);

    const path = name.split(/[\\/]/).filter(part => part !== "" && part !== "." && part !== "..");
    if (path.length > 0) files.set(path.join("/"), out);
  }
  return files;
}

function findEnd(bytes) {
  for (let at = bytes.length - 22; at >= Math.max(0, bytes.length - END_SEARCH); at -= 1) {
    if (bytes.readUInt32LE(at) === END) return at;
  }
  throw new Refused("the archive is damaged");
}
