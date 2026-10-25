---
name: plugins
description: Use when a person asks to update their plugins. Runs okb sync, which installs the newest release of the firm's plugins from the firm's OKB. Shows each plugin's old and new version. It runs in one of three modes: human only, AI guided or human directed.
---

# Plugins

The firm's plugins come from its own organisational knowledge base (OKB), the firm's own Supabase project. Real Agent publishes each release of them to the Plugins scope: the `real-agent` and `okb` plugins, and each workflow plugin the firm has bought. A release counts only once every file in it matches its list, the release's `MANIFEST`.

`okb sync` brings this computer up to date, signed in as the person. It downloads the newest release and checks every file. A release that fails the check is passed over for the next older one. It keeps the release as a copy on this computer, and Claude Code installs from that copy as the `real-agent` marketplace. Then it updates each plugin installed from it. The person's first `okb sync` replaces the copy installed from Real Agent's public marketplace.

This skill sets the order, the wording and the checks. It belongs to no one agent: any agent can run it. The okb plugin's `check_plugins` tool compares the installed plugins with the newest release, and changes nothing. Its `update_plugins` tool runs `okb sync` as the person signed in. It uses the `okb:writing` skill for what it tells the person.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They run `okb sync` in Terminal or PowerShell.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and a line for the agent.

With the agent, the person's own instruction replaces a rule of this skill, such as reading the versions first. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead.

## 1. Update the plugins

1. **See what is behind.**
   - **Person:** in Terminal or PowerShell, runs `claude plugin list`, and notes each plugin's version.
   - **The agent:** calls `check_plugins`. Its `behind` gives each plugin installed from the `real-agent` marketplace whose version is lower than the newest release's, with both versions, and `release` names that release. The agent gives one line for each plugin behind, such as "okb 0.3.0 is installed, and 0.4.0 is released." With `behind` empty, it says only that no plugin is behind, since the person asked. A problem in its result is given in one line.
2. **Run okb sync.**
   - **Person:** in their folder, runs `okb sync`. On macOS and Linux, that is `node ~/.claude/plugins/marketplaces/real-agent/plugins/okb/cli/okb.mjs sync`. On Windows, in PowerShell, it is `node "$env:USERPROFILE\.claude\plugins\marketplaces\real-agent\plugins\okb\cli\okb.mjs" sync`.
   - **The agent:** calls `update_plugins` with no arguments, once the person has asked for the update. It never runs it unasked. The result's `output` is what `okb sync` printed. When the tool is refused, the agent gives the person the Person line to run, and asks for what it printed.
3. **Read what it did.** `okb sync` prints one line for each step:
   - "Your copy in ... is now release ..., from ...": the release it installed, and the one before it.
   - "Your copy ... is up to date": there is no newer release.
   - "Release ... is incomplete in OKB, and was passed over": a release failed its check, and an older one was used. The lines under it name each missing or changed file.
   - "<plugin>: updated from <old> to <new>": the plugin's old and new version.
   - "<plugin>: already up to date, at <version>".
   - "<plugin>: in the release, and not installed": a plugin the firm has, which this computer does not have yet. The line gives the command that installs it.
   - "OKB's Plugins scope shows ... no release yet": Real Agent has not published the firm's plugins yet, or the person cannot read the Plugins scope.
   - "Your agent no longer reads ... Move any file you want uploaded into ...": a folder an earlier setup made for uploads holds files. The line comes once for each such folder.
   - **Person:** reads the lines.
   - **The agent:** gives the person each plugin's name with its old and new version, in a short list. It names any release passed over, and any plugin not installed with its install command. It names any folder `okb sync` named, with the folder to move its files into.

**AI guided:** the agent gives the person each plugin's old and new version, and waits for their approval.

## 2. Start using the new versions

1. **Start a new session.**
   - **Person:** starts a new Code session on their folder. The new versions load in a new session, not in the one already open.
   - **The agent:** tells the person to start a new Code session on their folder, and to type the agent's name with `@` as before.

**AI guided:** the agent gives the person the new session's first step, and waits for their approval.

## Problems

- **"is not signed in" or "ended ...'s sign-in":** the person signs in again in their folder with `okb sign-in`, as the `okb:actor` skill describes, and runs this skill again.
- **"No release in OKB's Plugins scope has all its files in place":** every release failed its check. The person asks Real Agent with the `real-agent:support` skill, quoting the lines.
- **"Another okb sync is still copying":** another run is under way. The person waits a minute and runs it again.
- **"Git was not found" or "The claude command was not found":** the line gives the command that installs it. The person installs it, opens a new terminal and runs `okb sync` again.
- **"the update failed. Claude Code said: ...":** the person quotes the line to Real Agent with the `real-agent:support` skill.
