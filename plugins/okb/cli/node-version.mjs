// The one Node.js version the okb plugin runs on, held as node_major in the okb plugin's project.json.
// okb.mjs setup stops on another version, and names the command that installs it.
import process from "node:process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));

/** The Node.js major version the plugins need, from project.json. */
export const NODE_MAJOR = JSON.parse(readFileSync(resolve(HERE, "../project.json"), "utf8")).node_major;

/** The command that installs the needed Node.js line on a system, as the user guide gives it. */
export function installCommand(platform = process.platform, major = NODE_MAJOR, linux = platform === "linux" ? linuxName() : null) {
  // nodejs.org's signed installer for the newest release of the line, in a folder of the person's own, checked against
  // nodejs.org's checksums before it runs as root. Homebrew builds Node from source on some Macs.
  if (platform === "darwin") return `cd "$(mktemp -d)" && curl -fsSLO https://nodejs.org/dist/latest-v${major}.x/SHASUMS256.txt && f=$(awk '/\\.pkg$/{print $2}' SHASUMS256.txt) && curl -fsSLO "https://nodejs.org/dist/latest-v${major}.x/$f" && grep " $f$" SHASUMS256.txt | shasum -a 256 -c && sudo installer -pkg "$f" -target /`;
  if (platform === "win32") return "winget install OpenJS.NodeJS";
  if (platform === "linux" && linux === "ubuntu") return `sudo snap install node --channel=${major}/stable --classic`;
  if (platform === "linux" && linux === "debian") return `curl -fsSL https://deb.nodesource.com/setup_${major}.x | sudo -E bash - && sudo apt-get install -y nodejs`;
  return `Install Node.js ${major} from https://nodejs.org.`;
}

/** "ubuntu" or "debian" from /etc/os-release, for the Linux install command, or null. */
export function linuxName(file = "/etc/os-release") {
  let text;
  try { text = readFileSync(file, "utf8"); } catch { return null; }
  const field = name => (new RegExp(`^${name}="?([^"\\n]*)"?$`, "m").exec(text)?.[1] ?? "").toLowerCase().split(/\s+/);
  const names = [...field("ID"), ...field("ID_LIKE")];
  return names.includes("ubuntu") ? "ubuntu" : names.includes("debian") ? "debian" : null;
}

/**
 * Null when version is in the needed major line. Otherwise the message naming the version found and the
 * install command. OKB_NODE_VERSION stands in for this computer's version, for the tests.
 */
export function nodeMismatch(version = process.env.OKB_NODE_VERSION || process.versions.node, platform = process.platform) {
  if (Number(String(version).replace(/^v/, "").split(".")[0]) === NODE_MAJOR) return null;
  return `Node is not version ${NODE_MAJOR}. This computer has Node.js ${String(version).replace(/^v/, "")}, and OKB needs Node.js ${NODE_MAJOR}. Install it with:\n  ${installCommand(platform)}\nThen open a new terminal, and check it with: node -v`;
}
