---
name: writing
description: Use before writing anything a person will read in OKB. That covers a reply, a record's text, a purpose statement, a report, a design, a spec and a page. Gives the plain-English rules, and checks a text with the okb plugin's `check_text` tool.
---

# Writing

These are the rules for every word a person reads: a reply, a record's text, a document, a page and a heading. A tool's arguments follow the tool's own form.

The rules are the humanizer plugin's `translate` skill, version 0.2.2, by Agent Bench, under the MIT licence. The okb plugin's `check_text` tool runs the same version's checks. It checks the rules marked "`check_text` checks this". The person and the agent check the others by reading.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They write with a text editor, and check with the `okb` command.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of the stage.
- **Human directed:** the person tells the agent what to do. The agent follows its lines for each step the person directs, and writes the words the person gives.

Each step below gives a **Person** line and an **Agent** line.

With the agent, the person's own instruction replaces a rule of this skill. The agent names the rule once and does as told.

## 1. Check a text

1. **Write the text in the agent folder,** as a Markdown or plain text file.
   - **Person:** saves the text as `<name>.md` in the agent folder, with a text editor.
   - **Agent:** writes `<name>.md` in the agent folder with `Write`.
2. **Run the checks.** Clear each finding, and check again until there is none.
   - **Person:** runs `okb check_text text_file=<full path>/<name>.md` in the agent folder.
   - **Agent:** calls `check_text` with `text_file`, and clears each finding with `Edit`.
3. **Read for the other rules.** Read each paragraph's first sentence on its own, and the last clause of each paragraph.
   - **Person:** reads the text from the top, against the rules below.
   - **Agent:** reads the text with `read_file`, and gives the person each sentence it changed, with the rule.

**AI guided:** the agent gives the person the findings it cleared and the sentences it changed, and waits for their approval.

## Lead with the answer

The first sentence is the answer. Paths, numbers, dates and record ids go underneath, and are given when asked. State the answer plainly, with no "likely", "appears to" or "this looks like".

## One issue at a time

A reply is precise and concise. It holds what the person needs to act or decide, and nothing else. The okb plugin's one-issue hook checks each reply of the database operator, the database admin and the business analyst. It sends a reply back once when its own prose asks more than one question.

- A reply that needs the person's answer, agreement or action holds one such issue, and stops. The next issue comes after their reply.
- A reply that needs nothing from the person is a summary. It gives one line per item, or one table row per record, all in one reply.
- A list of records gives one row per record, with only the fields that let the person prioritise, soonest first. A row holds no sentence.
- A question with a yes or no answer gets the answer as its first word, in one line, such as "Yes, the valuation at 1 Example Road is completed." Add a second line only for something the person must do.
- A quoted message, and a draft shown for approval, go in a block quote. A command goes in fenced code.

## Say what is true

- Say the whole truth, and give the common case only when it is the whole truth.
- Use the lasting word, such as "the computer", and state a current limit once, where it applies.
- Give the number when it is known, and the name when the thing has one.
- State the condition a statement depends on.

## Look a term up before defining it

- Look up each term used as a heading or a definition, in Wikipedia or Merriam-Webster. Open the definition with the standard one.
- A heading names the thing. Put its description in the text under it.
- A caption under a name says what the thing is and what it does. When, how often and from where come after it.
- A term with no standard definition is new. Ask the person before using it.
- Use the standard word, even when it is longer.

## Use the exact verb for software

Software stores, calls, checks, reads and holds. Use the field's own verb for what software does.

| Written | Correct |
|---|---|
| talks to, speaks to | communicates with, calls, integrates with, exchanges data with |
| sees, watches, looks at | monitors, observes, reads, records |
| knows, understands, thinks | determines, resolves, holds, is configured with |
| remembers, forgets | stores, retains, discards |
| wants, hopes, tries to | attempts, is configured to |
| lives, sits, stands, wanders | runs, is located in, is stored in |
| hands it to, gives it to | passes it to, provides it to |
| wakes up | starts |

A verb that the field already uses stays: a server listens on a port, a process sleeps, a lock is held, a parser reads.

## Name the trigger, the action and the result

A description of what something does names three things:

- **The trigger:** what causes it to happen.
- **The action:** what it does, in verbs.
- **The result:** what is different afterwards, and where that shows.

"When the person runs the install command, it installs the application and writes the results in the terminal." Three fragments in a row with no main verb, such as "Small, fast, and local", assert nothing. Write a sentence with a verb.

## Let the text speak for itself

Delete each sentence that tells the reader what they are looking at, or vouches for how the text was made. Delete each one that repeats a number already on the page, explains a legend, signs the work or apologises for its scope. `check_text` checks a legend such as "lettered A to G".

## Give facts, not a pitch

State what the thing is, what it does and what follows in practice. Delete each reason the design is good. Keep each reason the reader needs, such as what goes wrong if they skip a step: "Give the name and description in the same request, or the agent will have to invent them."

## End each paragraph on its last fact

- Delete a closing sentence that says the point again with feeling.
- Delete a general truth added at the end, such as "A silent skip is the failure that looks like success".
- Keep "X rather than Y" when both halves are things this system could do: "marks a record deleted instead of removing it". Delete it when the second half is an opinion.
- A title is the name of the thing, such as "Ledger". `check_text` checks a title with a tag after a comma, such as "Ledger, read end to end".
- `check_text` checks a list of inflated words, and a correction used as a move, such as "not this, but that".

Read the last clause of each paragraph, and ask what a reader loses without it. Delete it when the answer is nothing.

## Give each count a subject

Write a count inside a sentence that says what is counted. `check_text` checks a count standing alone, such as "There are three.", and a sentence opening "None of them", "All of them" or "Both of them".

## One idea in each sentence

Give each sentence a subject and one idea. `check_text` checks a sentence over 25 words. Most sentences are well under that. A quotation counts as one word.

## Use a comma, a colon or two sentences in place of a dash

`check_text` checks each em-dash.

## Explain each term in plain words

A plain explanation uses plain words throughout. Give each abbreviation, function name and piece of jargon an ordinary English word in its place. Where a term stays, define it in the same sentence, in the words a person would say aloud. Read the sentence aloud; it parses in conversation.

## Stop after the fact

A sentence opening "That makes it", "Which means" or "This is what makes", after a fact, adds no fact. Delete it, and the instruction after it that nobody asked for. `check_text` checks "That makes it" and "This is what makes". The person and the agent check "Which means" by reading.

## Six sentences at most in a paragraph

Split a longer paragraph where its subject changes. `check_text` checks the count. Headings, list items, table rows and code are not paragraphs.

## Name the actor

Where something acts, make it the subject: "The installer writes the file". Keep the passive where it holds the topic of the passage as the subject: "What an agent can do is decided by its tool list".

## One name for each thing

Use one name for each thing, for the whole text. `check_text` checks these sets, with quotations left out:

- agent, assistant, bot, worker
- folder, directory
- machine, computer, box
- repo, repository
- config, configuration
- start, launch, boot

## Write each sentence in full

The rules above cut words. Each sentence still answers three questions aloud: who does it, in what situation, and what goes wrong if they skip it. Put back the words that answer them.

- **Advice:** write it as a step a person takes, with the person and the situation.

  | Written | Correct |
  |---|---|
  | Mark work done when it is done. | As tasks finish, tell the agent so it can mark them complete. |
  | Test any connector before you design around it. | Before you design around a connector, test that it works. |

- **Joints:** keep the articles, the connecting words and the second half of each construction. Say a line to a colleague across a desk, and write the words you would add.

  | Written | Correct |
  |---|---|
  | Describe the problem as it costs the business. | Describe the problem in terms of what it is costing the business. |
  | Then check the dates follow the links. | Then check that no task is due to finish before the tasks it waits on. |

- **Whose example:** say whose case an example is: "In this project", "For the project owner". `check_text` checks "Here" used for it three times in one text.
- **Who acts:** name the person or program that acts. An interview, a meeting, a routine or a document does nothing by itself. "The agent saves each statement as evidence, while the interview runs."
- **What a reference means:** name the thing a number or record stands for. State what is being corrected before the correction. Read each prompt as a person who has seen only the page.
- **The method as it works now:** describe the tools and the method as they are at the end. A past mistake stays only as advice to the reader: "Give all three in one request, or the agent will have to invent them." Name only where a piece of work ended up. Delete each sentence about where the text's own material came from.
- **Sweep by name:** search the text for each person's name, and read each sentence that has one. Keep it when it describes the method. Rewrite it as advice or a fact when it tells the story of the project.

## Commands run as pasted

A person pastes each command into Terminal or PowerShell as it stands. Give one command at a time, in a code block, for their system.

- Fill in each value you know, such as a folder, a file path or an email. Write each path out in full, in quotes.
- Ask for each value you do not know. Give the whole command after the answer.
- Give a path as `whoami`'s `agentFolderPath` or `check_plugins`'s `sessionFolder` gives it, and leave out wildcards such as `*`.
- Use the angle brackets of a usage line, such as `<folder>`, only in a line that says what the command's form is. The command the person pastes holds none.

## Length

The rules stay the same at every length. The length comes from what was asked for.

| Asked for | At most |
|---|---|
| A recap of what was just said | Three sentences |
| "What is this thing?" | Three sentences: what it is, why it exists, what follows |
| A definition of one concept | Two to four sentences |
| A list of records | One row per record, the fields that set its priority |
| An explanation, a document, a page | As long as the content needs |

A recap restates the last reply, and adds nothing to it. After an investigation, it gives the cause, then the proposed fix, or says no fix was found.

## End on the last thing worth saying

End on the last fact. Leave out "want me to…", "let me know if…" and "hope this helps".
