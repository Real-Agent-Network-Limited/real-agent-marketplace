#!/usr/bin/env node
// Signs a Supabase Auth user in, at a terminal, and keeps only the session's refresh token.
//
//   node sign-in.mjs [--project <ref> --email <email>] [--url <project URL> --key <publishable key>] [--new-password]
//                    [--folder <session folder>]
//
// --project reuses a saved project's URL, key and email. --url and --key answer those two questions,
// for a plugin that knows its project, and --email alone answers the email question. --new-password replaces the password.
// --folder also writes the folder's actor file, .okb-actor.json, naming the project and the email, so a
// session opened on that folder works as this user, with the folder as its agent folder.
import process, { stdin, stdout, stderr, argv } from "node:process";
import { options, signIn } from "./lib/sign-in-flow.mjs";

// Typed past the end of one answer, kept for the next question. Leaving a `for await` over stdin
// destroys it, so a listener reads instead.
let ahead = "";

/** One line from the terminal; a hidden one is never echoed. */
function ask(prompt, hidden = false) {
  if (!stdin.isTTY || typeof stdin.setRawMode !== "function") throw new Error("sign-in needs an interactive terminal.");
  // Raw before the prompt shows, so nothing typed at it is echoed by the terminal itself.
  stdin.setEncoding("utf-8");
  stdin.setRawMode(true);
  stdout.write(prompt);
  return new Promise((resolve, reject) => {
    let value = "";
    const finish = (error, answer) => {
      stdin.off("data", take);
      stdin.off("end", closed);
      stdin.setRawMode(false);
      stdin.pause();
      error ? reject(error) : resolve(answer);
    };
    const take = chunk => {
      const text = ahead + chunk;
      ahead = "";
      for (let i = 0; i < text.length; i++) {
        const char = text[i];
        if (char === "\r" || char === "\n") {
          ahead = text.slice(text[i + 1] === "\n" && char === "\r" ? i + 2 : i + 1);
          stdout.write("\n");
          return finish(null, value.trim());
        }
        if (char === "\u0003") return finish(new Error("cancelled."));
        if (char === "\u007f" || char === "\b") {
          if (value && !hidden) stdout.write("\b \b");
          value = value.slice(0, -1);
        } else {
          value += char;
          if (!hidden) stdout.write(char);
        }
      }
    };
    const closed = () => finish(new Error("input closed."));
    stdin.on("data", take);
    stdin.on("end", closed);
    stdin.resume();
    if (ahead) take("");
  });
}

// The exit code is set, and Node ends once its connections close. Calling exit() with an HTTPS
// connection still open crashes Node on Windows, in libuv's async.c.
try {
  await signIn(options(argv.slice(2)), ask, line => stdout.write(`${line}\n`));
  process.exitCode = 0;
} catch (err) {
  stderr.write(`Sign-in stopped: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exitCode = 1;
}
