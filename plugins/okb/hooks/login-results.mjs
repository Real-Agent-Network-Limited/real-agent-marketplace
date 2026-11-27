// Withholds from every agent and session a tool's result that holds a shared login's password: a "password" or
// "previous_password" field with a value, as okb_open_login gives one. agent-tools.mjs refuses each call it sees that
// would open one. This catches a call it could not see, such as a function name built in the shell. Claude Code runs it
// as a PostToolUse hook, with the call and its tool_response on stdin. An MCP tool's result is replaced with
// LOGIN_WITHHELD. A Bash or PowerShell result cannot be replaced, so the hook blocks it, and Claude Code gives the agent
// LOGIN_WITHHELD as the reason.
import { realpathSync } from "node:fs";
import { argv, stdin, stdout } from "node:process";
import { fileURLToPath } from "node:url";

export const LOGIN_WITHHELD = "This result held a shared login's password, so it is withheld. A password is opened on the Login card alone: show it with Real Agent's connector's show_logins. Do not repeat or use any password from this result.";

// A password field with a value, in JSON as it is or as text inside a JSON string, with its quotes escaped.
const PASSWORD_FIELD = /\\*"(previous_)?password\\*"\s*:\s*\\*"(?!\\*")/;

/** Whether a tool's result holds a shared login's password. */
export const holdsPassword = response => PASSWORD_FIELD.test(typeof response === "string" ? response : JSON.stringify(response ?? null));

/** What the hook writes for a call and its result: nothing, the MCP tool's replaced output, or a block. */
export function verdict(call) {
  const tool = String(call?.tool_name ?? "");
  const shell = ["Bash", "PowerShell"].includes(tool);
  if (!shell && !tool.startsWith("mcp__")) return null;
  if (!holdsPassword(call?.tool_response)) return null;
  if (shell) return { decision: "block", reason: LOGIN_WITHHELD };
  return { hookSpecificOutput: { hookEventName: "PostToolUse", updatedMCPToolOutput: LOGIN_WITHHELD } };
}

const real = file => { try { return realpathSync(file); } catch { return file; } };
if (argv[1] && real(fileURLToPath(import.meta.url)) === real(argv[1])) {
  let text = "";
  for await (const chunk of stdin) text += chunk;
  let call = null;
  try { call = JSON.parse(text); } catch { process.exit(0); }
  const out = verdict(call);
  if (out) stdout.write(JSON.stringify(out));
  process.exit(0);
}
