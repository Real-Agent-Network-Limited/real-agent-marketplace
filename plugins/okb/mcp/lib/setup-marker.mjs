// Whether setup is under way in a folder, for the okb plugin's hooks. The business analyst sets Real Agent up through
// the Supabase connector and Bash, and once setup has finished it keeps the firm as the administrator's agent with the
// okb plugin's tools alone. The owner's first okb setup --owner, and the owner's sign-in, mark the folder with
// SETUP_MARKER; the okb setup that ends setup, signed in, removes it. Only the mark opens setup: a folder with no actor
// file is not open, and no agent may write the mark (agent-folder-edit.mjs refuses it), so once setup has ended the
// business analyst cannot open it again.
import { existsSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export const SETUP_MARKER = ".okb-setup-in-progress";

/** Marks the folder as one whose setup is under way. */
export function markSetup(folder) {
  writeFileSync(join(folder, SETUP_MARKER), "Real Agent's setup is under way in this folder. The okb setup that ends it removes this file.\n");
}

/** Removes the folder's mark, once setup has finished in it. */
export function endSetup(folder) {
  rmSync(join(folder, SETUP_MARKER), { force: true });
}

/** True while setup is under way in the folder: it holds the mark okb setup --owner or the owner's sign-in wrote. */
export function setupOpen(folder) {
  if (typeof folder !== "string" || !folder) return false;
  return existsSync(join(folder, SETUP_MARKER));
}
