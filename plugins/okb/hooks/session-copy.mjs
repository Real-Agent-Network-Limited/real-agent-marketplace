// Turns one Claude Code session, a JSONL file under ~/.claude/projects, into Markdown that holds what
// the person and the agent wrote. Tool calls, tool results, thinking, attachments, subagent turns,
// shell commands and their output are left out. A turn's text loses its <system-reminder> blocks.
import { readFileSync } from "node:fs";
import { join } from "node:path";

// A person's line that is a shell command, its output, or a slash command, rather than what they wrote.
const COMMAND = /^\s*<(bash-input|bash-stdout|bash-stderr|local-command-stdout|local-command-stderr|local-command-caveat|command-name|command-message|command-args)>/;
const REMINDER = /<system-reminder>[\s\S]*?<\/system-reminder>/g;

/** The file in the sessions folder that notes each copy uploaded, with the time its file had then. */
export const UPLOADED = ".uploaded.json";

/** The copies uploaded, each name with the time its file had when it went up. */
export function uploaded(sessionsFolder) {
  try { return JSON.parse(readFileSync(join(sessionsFolder, UPLOADED), "utf-8")) ?? {}; } catch { return {}; }
}

const pad = n => String(n).padStart(2, "0");
/** A time as the person's computer shows it: 2026-10-05 14:20. */
export const localTime = iso => {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "" : `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

/** The text a person or the agent wrote in one line of the session, or "" when the line holds none. */
function written(line) {
  const content = line.message?.content;
  let parts = [];
  if (typeof content === "string") parts = [content];
  else if (Array.isArray(content)) {
    for (const block of content) {
      if (block?.type === "text" && typeof block.text === "string") parts.push(block.text);
      else if (block?.type === "image" && line.type === "user") parts.push("(a picture)");
    }
  }
  const text = parts.filter(p => !COMMAND.test(p)).join("\n\n").replace(REMINDER, "").trim();
  return text === "(a picture)" ? "" : text;
}

/** The session's title, its first time, its id and its turns, each { who, time, text }. */
export function readSession(jsonlPath) {
  const turns = [];
  let title = "", id = "", first = "";
  for (const raw of readFileSync(jsonlPath, "utf8").split("\n")) {
    if (!raw.trim()) continue;
    let line;
    try { line = JSON.parse(raw); } catch { continue; }
    if (line.type === "custom-title" && line.customTitle) title = line.customTitle;
    if (!id && line.sessionId) id = line.sessionId;
    if (line.type !== "user" && line.type !== "assistant") continue;
    if (line.isSidechain || line.isMeta || line.isCompactSummary) continue;
    if (!first && line.timestamp) first = line.timestamp;
    const text = written(line);
    if (!text) continue;
    const who = line.type === "user" ? "Person" : "Agent";
    const last = turns.at(-1);
    // One reply comes in several lines, one per block, and the agent's text between tool calls is one turn.
    if (last && last.who === who) last.text += `\n\n${text}`;
    else turns.push({ who, time: line.timestamp ?? "", text });
  }
  return { title, id, first, turns };
}

/** The file name for a session's copy: <date>-<title>-<first 8 characters of its id>.md. */
export function copyName({ title, id, first }) {
  const slug = (title || "session").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60) || "session";
  return `${localTime(first).slice(0, 10) || "undated"}-${slug}-${id.slice(0, 8)}.md`;
}

/** The session as Markdown, or null when it holds no turn. */
export function copySession(jsonlPath) {
  const session = readSession(jsonlPath);
  if (session.turns.length === 0) return null;
  const lines = [`# ${session.title || "Session"}`, "", `Session ${session.id}, from ${localTime(session.first)}.`];
  for (const turn of session.turns) lines.push("", `## ${turn.who} · ${localTime(turn.time)}`, "", turn.text);
  return { name: copyName(session), text: lines.join("\n") + "\n" };
}
