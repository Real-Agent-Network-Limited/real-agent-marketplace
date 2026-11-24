// The oldest operating systems okb setup runs on. okb.mjs setup stops on an older one, and names the update.
// A Mac needs macOS 15, the oldest macOS Homebrew ships a ready-built Poppler for. Windows needs Windows 10 version
// 1809, build 17763, winget's oldest. Linux is not checked. install/install.sh and install/install.ps1 hold the same.
import process from "node:process";
import { spawnSync } from "node:child_process";
import { release } from "node:os";

/** The oldest macOS major version. */
export const MIN_MACOS = 15;
/** The build of Windows 10 version 1809. */
export const MIN_WINDOWS_BUILD = 17763;

/** This computer's version: sw_vers -productVersion on a Mac, os.release() on Windows. */
function readVersion(platform) {
  if (platform === "darwin") {
    const ran = spawnSync("sw_vers", ["-productVersion"], { encoding: "utf8" });
    return ran.status === 0 ? ran.stdout : "";
  }
  return release();
}

/**
 * Null when the system is new enough, or isn't checked. Otherwise the one line that stops setup. `read` stands in for
 * sw_vers and os.release() in the tests.
 */
export function osMismatch(platform = process.platform, read = () => readVersion(platform)) {
  if (platform === "darwin") {
    let version;
    try { version = String(read() ?? "").trim(); } catch { version = ""; }
    const major = version.split(".")[0];
    if (!/^\d+$/.test(major)) return `okb setup could not read this Mac's macOS version with sw_vers. Check that this Mac runs macOS ${MIN_MACOS} or later, in the Apple menu, About This Mac, then run okb setup again.`;
    if (Number(major) < MIN_MACOS) return `This Mac runs macOS ${version}, and Real Agent needs macOS ${MIN_MACOS} or later. Update macOS in System Settings, General, Software Update, then run okb setup again.`;
    return null;
  }
  if (platform === "win32") {
    let build;
    try { build = String(read() ?? "").trim().split(".")[2] ?? ""; } catch { build = ""; }
    if (!/^\d+$/.test(build)) return "okb setup could not read this computer's Windows build. Check that it runs Windows 10 version 1809 or later, in Settings, System, About, then run okb setup again.";
    if (Number(build) < MIN_WINDOWS_BUILD) return `This computer runs Windows build ${build}, and Real Agent needs Windows 10 version 1809 or later. Update Windows in Settings, Windows Update, then run okb setup again.`;
  }
  return null;
}
