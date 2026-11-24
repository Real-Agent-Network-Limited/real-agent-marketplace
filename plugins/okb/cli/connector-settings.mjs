// Makes the five settings Real Agent's connector needs in a firm's Supabase project, through Supabase's
// Management API, with a personal access token the owner pastes at a hidden prompt. The token is used for
// this run only: it never goes on a command line, into an environment variable, a file or a log, and is
// never printed.
//
//   node okb.mjs connector-settings --url <project URL> --slug <slug>
//
// The five settings: the project signs its tokens with an asymmetric key, ES256 or RS256. The OAuth server is
// on, with dynamic OAuth apps. Its authorization path is /oauth/consent. The Site URL is
// https://mcp.realagent.network/<slug>/sign-in/. Public sign-up is off.
//
// The signing key is switched in two runs, as Supabase's guide "JWT Signing Keys" gives a safe rotation.
// Supabase throttles a key's state changes for about 5 minutes, and caches a project's published keys for up
// to about 20 minutes. So the first run imports the legacy JWT secret as the key in use, if it is not yet,
// and creates an ES256 key on standby. It exits 3, "run again later". A run 20 minutes later puts the standby
// key in use. The legacy secret becomes a previously used key, so tokens it signed stay valid until they
// expire. When Supabase answers that the change is throttled, the run exits 3 too. Exit 0 means all five
// settings hold, and 1 that one failed.
//
// It calls Supabase through management.mjs, which also says when OKB_TEST_MANAGEMENT_API names a stand-in.
import { stdout, stderr } from "node:process";
import { API, apiBase, askHidden, managementClient, Refused } from "./management.mjs";

export { API, apiBase };

export const CONNECTOR_SETTINGS_USAGE = `Usage: node okb.mjs connector-settings --url <project URL> --slug <slug>

connector-settings makes the five settings Real Agent's connector needs in your firm's Supabase project.
It asks for a Supabase access token, which you make at https://supabase.com/dashboard/account/tokens.
Name it, choose the shortest expiry, choose Organization under Resource access, and keep Full access. Delete it
on that page once every line says done.

The signing key takes two runs, 20 minutes apart. The first run says when to run it again, and exits 3.

--url is your project's address, https://<project reference>.supabase.co.
--slug is your firm's short name in Real Agent's connector's address, https://mcp.realagent.network/<slug>.`;

export const TOKEN_PAGE = "https://supabase.com/dashboard/account/tokens";
/** The options every prompt for the token gives: the token is made for one run, in the organisation that holds the project. */
export const TOKEN_OPTIONS = "Name it, choose the shortest expiry, choose Organization under Resource access, and keep Full access.";
const PROJECT_URL = /^https:\/\/([a-z]{20})\.supabase\.co\/?$/;
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const ASYMMETRIC = ["ES256", "RS256"];
export const AUTHORIZATION_PATH = "/oauth/consent";
export const siteUrl = slug => `https://mcp.realagent.network/${slug}/sign-in/`;

/** The command line's --url and --slug, checked. Throws a plain sentence for anything else. */
export function options(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const word = argv[i];
    if (word !== "--url" && word !== "--slug") throw new Error(`${word} is not an option of connector-settings.`);
    if (argv[i + 1] === undefined) throw new Error(`${word} needs a value.`);
    out[word.slice(2)] = argv[++i];
  }
  if (out.url === undefined || out.slug === undefined) throw new Error("connector-settings needs --url and --slug.");
  const ref = PROJECT_URL.exec(out.url)?.[1];
  if (!ref) throw new Error(`${out.url} is not a Supabase project's address, such as https://abcdefghijklmnopqrst.supabase.co.`);
  if (!SLUG.test(out.slug) || out.slug.length < 2 || out.slug.length > 40)
    throw new Error(`${out.slug} is not a short name. It is lower-case words and numbers joined by hyphens, from 2 to 40 characters.`);
  return { ref, slug: out.slug };
}

/** Calls the Management API for one project, at a path under /v1/projects/{ref}, with a client from management.mjs. */
function client(api, ref) {
  return (method, path, body, options) => api.call(method, `/v1/projects/${encodeURIComponent(ref)}${path}`, body, options);
}

const inUseAsymmetric = keys => keys.find(k => k.status === "in_use" && ASYMMETRIC.includes(k.algorithm));
const standbyAsymmetric = keys => keys.find(k => k.status === "standby" && ASYMMETRIC.includes(k.algorithm));
/** Supabase turns a key's state change down for about 5 minutes after the last one, with 429 or a message. */
// Only Supabase's documented throttling answer, 429, means wait. Any other refusal is a failure.
const throttled = err => err instanceof Refused && err.status === 429;

/**
 * One step of the switch to an asymmetric signing key, as Supabase's guide gives a safe rotation. Returns
 * { state, before }: "already" when one is in use, "created" when a standby key was made this run,
 * "switched" when a standby key was put in use, and "throttled" when Supabase asks to wait.
 */
async function signingKey(call) {
  let { keys = [] } = await call("GET", "/config/auth/signing-keys");
  if (inUseAsymmetric(keys)) return { state: "already", before: keys };
  try {
    // The dashboard's first step: the legacy JWT secret becomes a signing key in use, so it is kept, and
    // trusted, when another key is rotated in. Supabase says this endpoint will go, so a 404 means there is
    // nothing to import.
    if (!keys.some(k => k.status === "in_use")) {
      const legacy = await call("GET", "/config/auth/signing-keys/legacy", undefined, { allow404: true });
      if (!legacy) await call("POST", "/config/auth/signing-keys/legacy", undefined, { allow404: true });
      keys = (await call("GET", "/config/auth/signing-keys")).keys ?? [];
    }
    // A standby key, made by an earlier run or the dashboard, is put in use. Otherwise one is made on
    // standby, and put in use by the next run, once Supabase's caches hold it.
    const standby = standbyAsymmetric(keys);
    if (standby) {
      await call("PATCH", `/config/auth/signing-keys/${standby.id}`, { status: "in_use" });
      return { state: "switched", before: keys };
    }
    await call("POST", "/config/auth/signing-keys", { algorithm: "ES256", status: "standby" });
    return { state: "created", before: keys };
  } catch (err) {
    if (throttled(err)) return { state: "throttled", before: keys };
    throw err;
  }
}

/** The settings each line names, as Supabase's auth config holds them. */
const LINES = slug => [
  { name: "OAuth server, with dynamic OAuth apps", holds: c => c.oauth_server_enabled === true && c.oauth_server_allow_dynamic_registration === true,
    change: { oauth_server_enabled: true, oauth_server_allow_dynamic_registration: true } },
  { name: `Authorization path ${AUTHORIZATION_PATH}`, holds: c => c.oauth_server_authorization_path === AUTHORIZATION_PATH,
    change: { oauth_server_authorization_path: AUTHORIZATION_PATH } },
  { name: `Site URL ${siteUrl(slug)}`, holds: c => c.site_url === siteUrl(slug), change: { site_url: siteUrl(slug) } },
  // Supabase leaves sign-up open, and the sign-in page publishes the key a stranger needs to sign up. The owner's
  // account is made through the admin API, which works with it off.
  { name: "Public sign-up off", holds: c => c.disable_signup === true, change: { disable_signup: true } },
];
const KEY_LINE = "Asymmetric signing key";

/** The exit code that means the signing key needs another run later. */
export const AGAIN = 3;

/**
 * Makes the five settings with token, and returns { code, lines }: one line per setting, or the line of the
 * call that failed. Code 0 only when all five hold when read back, 3 when the signing key needs another run.
 * okb setup --owner passes its own client as api, which already holds the token.
 */
export async function makeSettings({ ref, slug }, token, base = apiBase(), api = managementClient(token, base)) {
  const call = client(api, ref);
  const lines = [];
  let doing = KEY_LINE;
  try {
    const key = await signingKey(call);
    doing = "OAuth server and Site URL";
    const config = await call("GET", "/config/auth");
    const settings = LINES(slug);
    const missing = settings.filter(s => !s.holds(config));
    if (missing.length) {
      await call("PATCH", "/config/auth", Object.assign({}, ...missing.map(s => s.change)));
    }
    // Each setting read back, as Supabase now holds it.
    doing = "Reading the settings back";
    const { keys = [] } = await call("GET", "/config/auth/signing-keys");
    const after = await call("GET", "/config/auth");
    let ok = true;
    if (key.state === "throttled") lines.push(`${KEY_LINE}: Supabase asks to wait. Run this command again in 5 minutes.`);
    else if (key.state === "created") {
      if (standbyAsymmetric(keys) || inUseAsymmetric(keys)) lines.push(`${KEY_LINE}: created. Run this command again in 20 minutes to start using it.`);
      else { ok = false; lines.push(`${KEY_LINE}: failed. Supabase shows no ES256 or RS256 key on standby.`); }
    } else {
      const previous = key.before.find(k => k.status === "in_use");
      const kept = key.state === "already" || !previous || keys.some(k => k.id === previous.id && k.status === "previously_used");
      const signing = inUseAsymmetric(keys);
      if (signing && kept) lines.push(`${KEY_LINE}: ${key.state === "switched" ? "done" : "already done"}.`);
      else {
        ok = false;
        lines.push(signing
          ? `${KEY_LINE}: failed. The old key was not kept as previously used, so tokens it signed may be refused.`
          : `${KEY_LINE}: failed. Supabase still shows no ES256 or RS256 key in use.`);
      }
    }
    for (const s of settings) {
      if (s.holds(after)) lines.push(`${s.name}: ${missing.includes(s) ? "done" : "already done"}.`);
      else { ok = false; lines.push(`${s.name}: failed. Supabase did not keep it.`); }
    }
    const later = key.state === "created" || key.state === "throttled";
    return { code: ok ? (later ? AGAIN : 0) : 1, lines };
  } catch (err) {
    if (err instanceof Refused && (err.status === 401 || err.status === 403)) {
      lines.push(`Supabase refused the token: ${err.message}. Make a new one at ${TOKEN_PAGE}, and run this again.`);
    } else {
      lines.push(`${doing}: failed. Supabase said: ${err instanceof Error ? err.message : String(err)}`);
    }
    return { code: 1, lines };
  }
}

/** The command: checks its options, asks for the token, makes the settings and prints a line for each. Returns the exit code. */
export async function connectorSettings(argv) {
  let given;
  try { given = options(argv); }
  catch (err) { stderr.write(`${err instanceof Error ? err.message : err}\n${CONNECTOR_SETTINGS_USAGE}\n`); return 2; }
  // A stand-in named by OKB_TEST_MANAGEMENT_API is said before the prompt, so a token is never pasted for it unseen.
  const base = apiBase();
  if (base !== API) stdout.write(`This run talks to a test stand-in at ${base}, not to Supabase. Paste no real token.\n`);
  stdout.write(`Make a Supabase access token at ${TOKEN_PAGE}. ${TOKEN_OPTIONS} Paste it here, and delete it on that page once every line says done.\n`);
  let token;
  try { token = await askHidden("Supabase access token: "); }
  catch (err) { stderr.write(`Stopped: ${err instanceof Error ? err.message : err}\n`); return 1; }
  if (!token) { stderr.write("No token was pasted. Run this again, and paste the token at the prompt.\n"); return 1; }
  const { code, lines } = await makeSettings(given, token, base);
  token = undefined;
  stdout.write(lines.map(line => `${line}\n`).join(""));
  return code;
}
