// The Python runner for the okb plugin's run_code. code.mjs copies it into a new folder with code.py and run.json, and starts it there
// with Node.js's permission model, which lets it read that folder, the runtime, the agent folder and each added folder,
// and write the agent folder alone. It loads Pyodide from the runtime, mounts the agent folder at /work and each added
// folder at /added/<name>, loads the packages the code imports, and runs the code in /work, with matplotlib drawing to files.
//
// Node.js refuses process.binding under the permission model, and Pyodide reads its file flags from it, so it is
// replaced by one that gives them from node:fs, as measured on 23 October 2026. Each refusal is given to Pyodide as
// EACCES, so Python raises PermissionError and goes on, and fsync, which the permission model refuses on every file,
// does nothing.
import fs, { constants, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const { runtime, work, added, wheels } = JSON.parse(readFileSync(join(here, "run.json"), "utf8"));
const code = readFileSync(join(here, "code.py"), "utf8");

for (const [name, call] of Object.entries(fs)) {
  if (typeof call !== "function" || !name.endsWith("Sync")) continue;
  fs[name] = function (...args) {
    try { return call.apply(this, args); }
    catch (err) {
      if (err?.code !== "ERR_ACCESS_DENIED") throw err;
      if (name === "fsyncSync") return undefined;
      const refused = new Error(err.message);
      refused.code = "EACCES";
      throw refused;
    }
  };
}
// Node.js's permission model leaves signals to other processes open, so process.kill is replaced, for good, before the
// code loads: as observed on 23 October 2026, the code then cannot reach it again.
const refuse = () => { const err = new Error("Access to this API has been restricted. A run sends no signal to another process."); err.code = "ERR_ACCESS_DENIED"; throw err; };
for (const name of ["kill", "_kill"]) Object.defineProperty(process, name, { value: refuse, writable: false, configurable: false });
const binding = process.binding;
process.binding = name => (name === "constants" ? { fs: constants } : binding.call(process, name));

const { loadPyodide } = await import(pathToFileURL(join(runtime, "pyodide.mjs")).href);
const py = await loadPyodide({ indexURL: `${runtime}/`, stdout: line => process.stdout.write(`${line}\n`), stderr: line => process.stderr.write(`${line}\n`) });
py.FS.mkdir("/work");
py.FS.mount(py.FS.filesystems.NODEFS, { root: work }, "/work");
for (const { name, path } of added) {
  py.FS.mkdirTree(`/added/${name}`);
  py.FS.mount(py.FS.filesystems.NODEFS, { root: path }, `/added/${name}`);
}
const quiet = { messageCallback: () => {} };
await py.loadPackage(wheels.map(file => join(runtime, file)), quiet);
await py.loadPackagesFromImports(code, quiet);
py.runPython("import os; os.environ['MPLBACKEND'] = 'Agg'; os.umask(0o022); os.chdir('/work')");
try {
  await py.runPythonAsync(code, { filename: "code.py" });
} catch (err) {
  // The traceback starts at the code's own lines, without Pyodide's frames above them.
  const text = String(err?.message ?? err).trim(), own = text.indexOf('  File "code.py"');
  process.stderr.write(`${own > 0 && text.startsWith("Traceback") ? `Traceback (most recent call last):\n${text.slice(own)}` : text}\n`);
  process.exitCode = 1;
}
