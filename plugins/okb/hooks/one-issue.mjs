// Keeps the database operator and the business analyst to one issue in each reply. Runs as a
// Stop hook, with the hook's input on stdin as Claude Code gives it. For those agents, it counts the sentences
// ending in a question mark in the reply's own prose: outside fenced code, block quotes and table rows, so a quoted
// reply, a drafted message or a table of records is not counted. More than one, with `stop_hook_active` false, sends
// the reply back once to be rewritten with the first question only. A second try stands, and every other session's
// reply goes ahead. The reply is `last_assistant_message`, or the last agent turn of `transcript_path` on a Claude
// Code that gives none.
import { realpathSync } from "node:fs";
import { argv, stdin, stdout } from "node:process";
import { fileURLToPath } from "node:url";
import { AGENTS } from "./agent-tools.mjs";
import { readSession } from "./session-copy.mjs";

// The business analyst's agent_type, which agent-tools.mjs holds once setup has finished in its folder.
export const ANALYST = "business-analyst:business-analyst";

/** The agents the hook keeps to one issue. */
export const KEPT = [...new Set([...Object.keys(AGENTS), ANALYST])];

export const REASON = "Your reply asks more than one question. Ask the first one only, and stop.";

/** The questions a reply asks in its own prose: each sentence ending in a question mark, outside fenced
 * code, block quotes and table rows. A fence closes only on the marker that opened it. */
export function questions(reply) {
  let fence = null, count = 0;
  for (const line of String(reply ?? "").split("\n")) {
    const opens = line.match(/^\s*(```|~~~)/)?.[1];
    if (fence) { if (opens === fence) fence = null; continue; }
    if (opens) { fence = opens; continue; }
    if (/^\s*(>|\|)/.test(line)) continue;
    count += (line.replace(/`[^`]*`/g, "").match(/\?(?=\s|$|["')\]*_])/g) ?? []).length;
  }
  return count;
}

/** The reply the hook judges: `last_assistant_message`, or the transcript's last agent turn without it. */
export function reply(input) {
  if (typeof input?.last_assistant_message === "string") return input.last_assistant_message;
  if (!input?.transcript_path) return "";
  return readSession(input.transcript_path).turns.filter(turn => turn.who === "Agent").at(-1)?.text ?? "";
}

/** The hook's answer for one input: the block with its reason, or null when the reply goes ahead. */
export function decide(input) {
  if (!KEPT.includes(input?.agent_type) || input?.stop_hook_active) return null;
  return questions(reply(input)) > 1 ? { decision: "block", reason: REASON } : null;
}

const real = file => { try { return realpathSync(file); } catch { return file; } };
// Any failure here lets the reply go ahead: the hook guards the reply's shape, and nothing else.
if (argv[1] && real(fileURLToPath(import.meta.url)) === real(argv[1])) {
  try {
    let text = "";
    for await (const chunk of stdin) text += chunk;
    const block = decide(JSON.parse(text));
    if (block) stdout.write(JSON.stringify(block));
  } catch {}
  process.exit(0);
}
