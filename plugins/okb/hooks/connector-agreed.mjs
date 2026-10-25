// Records, for the session, each Google or Microsoft 365 connector the person agreed the database operator may use. Claude Code runs it as a PostToolUse hook, only once a call has run: agent-tools.mjs put a connector's
// first call in a session to the person with permissionDecision "ask", so a call that ran is one the person allowed.
// Reads the call from stdin; any other agent's calls, and any other tool, are left alone. It never refuses anything.
import { realpathSync } from "node:fs";
import { argv, stdin } from "node:process";
import { fileURLToPath } from "node:url";
import { AGENTS, connectorOf, connectorState } from "./agent-tools.mjs";

/** Records the call's connector as agreed for its session, when the call is an agent's call to one. Returns the connector, or null. */
export function record(call, dir) {
  if (!AGENTS[call?.agent_type]?.connectors) return null;
  const [mcp, server = "", ...rest] = String(call?.tool_name ?? "").split("__");
  if (mcp !== "mcp") return null;
  const state = connectorState(call?.session_id ?? "none", dir);
  const connector = connectorOf(server, rest.join("__"), state.marked);
  if (connector && !state.agreed.includes(connector)) state.save({ agreed: [...state.agreed, connector] });
  return connector;
}

const real = file => { try { return realpathSync(file); } catch { return file; } };
if (argv[1] && real(fileURLToPath(import.meta.url)) === real(argv[1])) {
  try {
    let text = "";
    for await (const chunk of stdin) text += chunk;
    record(JSON.parse(text));
  } catch { /* a call that cannot be read records nothing, and the next call is asked again */ }
  process.exit(0);
}
