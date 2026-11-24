// Keeps each Claude in Chrome tab's last seen address for the database operator and the business analyst. Runs after each
// Claude in Chrome tool, as Claude Code's PostToolUse hooks receive it on stdin. The result's tool_response holds a Tab
// Context block:
//   Tab Context:
//   - Executed on tabId: 729764785
//   - Available tabs:
//     • tabId 729764785: "Example Domain" ("https://example.com/")
// Each tab's id and address go into the session's tab note, which agent-tools.mjs reads before the next Chrome call: it
// refuses a tab last seen at a Supabase address, and one never seen. A tab noted at a Supabase address keeps it until
// tabs_context_mcp shows it elsewhere. After a call that can change a page the note is stale, and every call but
// tabs_context_mcp is refused until its result, since a page can move after the call returns. Another agent's result passes through, and the result is never changed.
import { stdin } from "node:process";
import { AGENTS, changeChromeTabs, chromeTabsAfter, chromeTabsSeen } from "./agent-tools.mjs";

let text = "";
for await (const chunk of stdin) text += chunk;
let call;
try { call = JSON.parse(text); } catch { process.exit(0); }
if (!Object.hasOwn(AGENTS, call?.agent_type ?? "")) process.exit(0);
// A result with no Tab Context still marks the note stale after a call that can change a page.
const seen = chromeTabsSeen(call?.tool_response);
// Under the note's lock, as the agent-tools hook changes it. A note it cannot lock stays as it was: stale where a call
// that can change a page marked it.
try { changeChromeTabs(call?.session_id ?? "none", tabs => chromeTabsAfter(tabs, seen, String(call?.tool_name ?? "").split("__")[2], call?.tool_input, call?.tool_use_id)); } catch {}
process.exit(0);
