---
name: check
description: Use when a person asks to check this computer, or whether their agent's own tools work on it. The check makes a record payload from a sample page and draws a board. It reads a PDF, a picture, a recording and a video, from the okb plugin's sample files. It reports each program as working or missing. It runs in one of three modes: human only, AI guided or human directed.
---

# Checking the computer

The agent's own tools, such as the database operator's, `@real-agent:database-operator`, run on the person's computer, with these programs:

| Tool | Program |
|---|---|
| Drawing a graph page, a board or a state machine page, or making the record payload of one | Python 3 |
| A picture of a drawn page or board, for the agent to check it, and each PDF it prints | Google Chrome, Chromium or Microsoft Edge |
| Reading a PDF | Poppler |
| Reading a scanned PDF page | Tesseract |
| Reading a picture | ImageMagick |
| Reading a recording or a video | FFmpeg and whisper.cpp |

The check uses each tool on a sample file, and reports each program as working or missing. The samples are in this skill's `samples` folder. Its `make.mjs` makes the PDF, the picture, the recording and the video:

- `check.html`, a made-up state machine page titled "Valuation booking";
- `check.progress.json`, the progress of a plan titled "First release";
- `check.pdf`, page 1 with the text "OKB check page one, from its text layer", and page 2 a scan holding "Order total 4250 GBP";
- `check.jpg`, a picture 3000 by 2000 pixels;
- `check.wav`, a recording saying "This is the check recording.";
- `check.mp4`, a video of 6 seconds in two scenes, with the same speech.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They do each step with the `okb` command, and open each sample in its own program.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and a line for the agent.

With the agent, the person's own instruction replaces a rule of this skill, such as which programs to check. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead.

## 1. Copy the samples

- **Responsible:** the agent.
- **Person:** copies the samples into their folder. For the folder `~/real-agent`, on macOS and Linux, in Terminal:

  ```sh
  cp ~/.claude/plugins/marketplaces/real-agent/plugins/okb/skills/check/samples/check.* ~/real-agent/
  ```

  On Windows, in PowerShell:

  ```powershell
  Copy-Item "$env:USERPROFILE\.claude\plugins\marketplaces\real-agent\plugins\okb\skills\check\samples\check.*" "$env:USERPROFILE\real-agent"
  ```

- **The agent:** calls `copy_samples`, which copies each sample into the agent folder and leaves a file already there as it is. Takes the agent folder from its `agentFolder`. Each file in `differs` is not this release's sample. The agent names it, and skips the step that reads it. Step 3 reports each program that step checks as "checked once <file> is moved out of the agent folder".
- **Evidence:** the result's `copied`, `already` and `differs`.

**AI guided:** the agent names the samples copied and any that differ, and waits for the person's approval.

## 2. Use each tool on its sample

- **Responsible:** the person.
- **Person:** in a Code session on their folder, types `check this computer`. Without the agent, runs these in the folder:
  - `okb whoami`
  - `okb state_machine_payload page_file=check.html payload_file=check-1.json`
  - `okb draw_board progress_files=check.progress.json purpose="Check the board" page_file=check-1.board.html`
  - opens the PDF, the picture, the recording and the video in their own programs.
- **The agent:**
  1. Calls `whoami`.
  2. Calls `state_machine_payload` with `page_file` set to `check.html` in the agent folder, and `payload_file` set to a new file there, `check-1.json`. When that name is taken, it uses the next number. Python 3 works when the result gives the title "Valuation booking".
  3. Calls `draw_board` with `progress_files` set to `check.progress.json` in the agent folder, `purpose` set to "Check the board", and `page_file` set to a new file there, `check-1.board.html`. When that name is taken, it uses the next number. The browser works when the result gives a `picture_file`. Without one, its `picture_problem` says why.
  4. Calls `read_file` on `check.pdf`. Poppler works when page 1 comes back as "OKB check page one, from its text layer". Tesseract works when page 2 comes back "read by character recognition", holding "Order total 4250 GBP".
  5. Calls `read_file` on `check.jpg`. ImageMagick works when an image comes back, cut to 2000 by 1333 pixels.
  6. Calls `read_file` on `check.wav`. FFmpeg and whisper.cpp work when the transcript holds "check recording".
  7. Calls `read_file` on `check.mp4`. FFmpeg and whisper.cpp work when 3 frames come back, with speech holding "check recording".
- **Evidence:** each tool's result.

**AI guided:** the agent says what each tool gave, one line per tool, and waits for the person's approval.

## 3. Report

- **Responsible:** the agent.
- **Person:** writes down, for each program, whether its sample opened.
- **The agent:** reports one line per program: Python 3, the browser, Poppler, Tesseract, ImageMagick, FFmpeg and whisper.cpp. Each is working, missing, or checked only once another is installed.
- **Evidence:** the report.

**AI guided:** the agent gives the person the report, one line per program, and waits for their approval.

## Each refusal, and what the person does

- **"needs <program>, which is not on this computer. It is added with: …":** the program is missing. The report gives the install command from the refusal, which is the line for the person's system. The person installs it, quits and reopens Claude desktop, and asks for the check again. A refusal names the first missing program for its file only, so Tesseract is checked once Poppler works.
- **"Python 3 is not on this computer":** Python 3 is missing. The refusal gives its install command.
- **"no Chrome, Chromium or Edge on this computer":** the browser is missing. The agent checks its pages from their outlines alone, and prints no PDF. The person installs one with the line for their system:

| Program | macOS | Windows | Debian and Ubuntu |
|---|---|---|---|
| A Chromium browser, Google Chrome or, on Windows, Microsoft Edge | `brew install --cask google-chrome` | `winget install Microsoft.Edge` | `sudo apt install chromium` on Debian, `sudo snap install chromium` on Ubuntu |

- **A sign-in command in place of `whoami`'s answer:** no one is signed in for this folder, so `read_file` is not served. The person signs in, as the `okb:actor` skill gives it, and asks for the check again.
- **"No such file":** a sample is missing from the agent folder. The agent calls `copy_samples` again. Without the agent, the person copies them, as step 1 says.
- **"already exists":** the payload file's name is taken. The agent uses the next number.
- **"whisper_cli is set to …, which is not a file":** the whisper.cpp setting names a missing file. The person saves the right full path in the okb plugin's settings.
