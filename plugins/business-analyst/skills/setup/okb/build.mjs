#!/usr/bin/env node
// The business analyst's helper for setup, run with Bash on the owner's computer, from this folder's files. It needs
// Node alone: no Supabase command-line tool, and no password, key or token beyond the project's publishable key,
// which is public.
//
//   node build.mjs approve --ref <project reference> --folder <setup folder> [--reset]
//   node build.mjs run --url <project URL> [--key <publishable key>] [--ref <project reference>] <file> [<file> ...]
//   node build.mjs functions
//
// approve prints one SQL statement for the Supabase connector's execute_sql. It makes the okb_setup schema, which
// the okb-setup hosted function reads, and approves this folder's setup files by their SHA-256, each to run once:
// setup.sql, file-search.sql, file-search-scopes.sql, schedule.sql with the project reference filled in, and
// first-administrator.sql, with reset.sql too for --reset. It also writes a new sign-in code to the setup folder's
// .okb-owner-code, readable by the owner alone, for the owner's first sign-in, and approves the code by its SHA-256
// for a day. The code itself is never printed.
//
// run sends each file, in order, to the okb-setup hosted function, which runs it as postgres. It prints one line
// per file, and stops at the first that fails, with the database's message. Exit code 1 then.
//
// functions prints, as JSON, each hosted function to deploy with the connector's deploy_edge_function, in order:
// its name, its verify_jwt setting, its entrypoint and the full path of each of its files, with the name each file
// is deployed under.
import process from "node:process";
import { createHash, randomBytes } from "node:crypto";
import { chmodSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const HERE = dirname(fileURLToPath(import.meta.url));
export const PROJECT_REF = /^[a-z0-9]{20}$/;
/** The files setup runs through okb-setup, in order. */
export const BUILD_FILES = ["setup.sql", "file-search.sql", "file-search-scopes.sql", "schedule.sql", "first-administrator.sql"];
/** The file in the setup folder that holds the owner's sign-in code. */
export const OWNER_CODE_FILE = ".okb-owner-code";

/**
 * The hosted functions, in the order setup deploys them. okb-setup runs the setup files; the file search
 * functions follow, each with every file it imports.
 */
export const FUNCTIONS = [
  { name: "okb-setup", verify_jwt: false, files: ["index.ts", "real-agent.ts"] },
  { name: "file-search-worker", verify_jwt: false, files: ["index.ts", "text.ts"] },
  { name: "file-search", verify_jwt: true, files: ["index.ts"] },
  { name: "file-search-purge", verify_jwt: true, files: ["index.ts"] },
];

export const USAGE = `Usage: node build.mjs approve --ref <project reference> --folder <setup folder> [--reset]
       node build.mjs run --url <project URL> [--key <publishable key>] [--ref <project reference>] <file> [<file> ...]
       node build.mjs functions`;

const sha256 = text => createHash("sha256").update(text, "utf8").digest("hex");
const literal = text => `'${String(text).replaceAll("'", "''")}'`;

/** A setup file's text as okb-setup runs it: schedule.sql with the project reference filled in. */
export function fileText(name, ref, folder = HERE) {
  if (!BUILD_FILES.includes(name) && name !== "reset.sql") throw new Error(`${name} is not one of setup's files: ${[...BUILD_FILES, "reset.sql"].join(", ")}.`);
  const text = readFileSync(join(folder, name), "utf8");
  if (name !== "schedule.sql") return text;
  if (!PROJECT_REF.test(ref ?? "")) throw new Error("schedule.sql needs the project reference.");
  return text.replaceAll("<project reference>", ref);
}

/** The statement that makes okb_setup and approves the files and the owner's code, and the code file it wrote. */
export function approve({ ref, folder, reset = false }, { here = HERE, code = randomBytes(32).toString("hex") } = {}) {
  if (!PROJECT_REF.test(ref ?? "")) throw new Error(`${ref ?? "--ref"} is not a project reference.`);
  if (!folder || !existsSync(folder)) throw new Error(`${folder ?? "--folder"} is not a folder.`);
  const codeFile = join(resolve(folder), OWNER_CODE_FILE);
  writeFileSync(codeFile, `${code}\n`, { mode: 0o600 });
  try { chmodSync(codeFile, 0o600); } catch {}
  const files = [...(reset ? ["reset.sql"] : []), ...BUILD_FILES];
  const rows = files.map(name => `(${literal(sha256(fileText(name, ref, here)))}, ${literal(name)})`).join(",\n ");
  const sql = `create schema if not exists okb_setup;
revoke all on schema okb_setup from public, anon, authenticated;
create table if not exists okb_setup.approved (sha256 text primary key, name text not null, approved_at timestamptz not null default now());
create table if not exists okb_setup.owner_code (sha256 text primary key, expires_at timestamptz not null);
create table if not exists okb_setup.person (auth_user_id uuid primary key, name text not null, email text not null, role text not null check (role in ('owner', 'real_agent')));
revoke all on all tables in schema okb_setup from public, anon, authenticated;
delete from okb_setup.approved;
insert into okb_setup.approved (sha256, name) values
 ${rows};
delete from okb_setup.owner_code;
insert into okb_setup.owner_code (sha256, expires_at) values (${literal(sha256(code))}, now() + interval '1 day');
select name from okb_setup.approved order by approved_at, name;`;
  return { sql, codeFile };
}

/** Sends one file to okb-setup. Returns { ok, problem }. */
export async function runFile(url, key, name, text) {
  const headers = { "Content-Type": "text/plain; charset=utf-8", ...(key ? { apikey: key } : {}) };
  let res;
  try { res = await fetch(`${url.replace(/\/+$/, "")}/functions/v1/okb-setup/sql`, { method: "POST", headers, body: text }); }
  catch (err) { return { ok: false, problem: `the project could not be reached: ${err?.cause?.code ?? err?.message ?? err}` }; }
  const body = await res.json().catch(() => null);
  if (res.ok && body?.ok) return { ok: true };
  return { ok: false, problem: body?.problem ?? `okb-setup answered HTTP ${res.status}` };
}

/** Each function to deploy, with the full path of each file. */
export function functions(here = HERE) {
  return FUNCTIONS.map(f => ({
    name: f.name, verify_jwt: f.verify_jwt, entrypoint_path: "index.ts",
    files: f.files.map(name => ({ name, path: join(here, "functions", f.name, name) })),
  }));
}

function options(argv) {
  const out = { files: [] };
  for (let i = 0; i < argv.length; i++) {
    const word = argv[i];
    if (word === "--reset") out.reset = true;
    else if (["--ref", "--folder", "--url", "--key"].includes(word)) {
      if (argv[i + 1] === undefined) throw new Error(`${word} needs a value.`);
      out[word.slice(2)] = argv[++i];
    } else if (word.startsWith("--")) throw new Error(`${word} is not an option.`);
    else out.files.push(word);
  }
  return out;
}

export async function main(argv, { say = line => process.stdout.write(`${line}\n`), fail = line => process.stderr.write(`${line}\n`) } = {}) {
  const [command, ...rest] = argv;
  let o;
  try { o = options(rest); } catch (err) { fail(`${err.message}\n${USAGE}`); return 2; }
  try {
    if (command === "approve") {
      const { sql, codeFile } = approve(o);
      say(sql);
      fail(`The owner's sign-in code is in ${codeFile}.`);
      return 0;
    }
    if (command === "functions") { say(JSON.stringify(functions(), null, 2)); return 0; }
    if (command === "run") {
      const ref = o.ref ?? /^https:\/\/([a-z0-9]{20})\.supabase\.co\/?$/.exec(o.url ?? "")?.[1];
      if (!o.url || !o.files.length) throw new Error(`run needs --url and at least one file.\n${USAGE}`);
      for (const name of o.files) {
        const ran = await runFile(o.url, o.key, name, fileText(name, ref));
        if (!ran.ok) { fail(`${name}: failed: ${ran.problem}`); return 1; }
        say(`${name}: done`);
      }
      return 0;
    }
    fail(USAGE);
    return 2;
  } catch (err) {
    fail(err instanceof Error ? err.message : String(err));
    return 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
