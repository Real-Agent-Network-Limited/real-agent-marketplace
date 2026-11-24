---
name: ingest
description: Use when a person asks to add their email, files, chat or other connectors to their knowledge base. Also use at a session's start when a source has something new. It saves only what the person agrees to, as evidence records and files in OKB. It runs in one of three modes: human only, AI guided or human directed.
---

# Ingest

The firm's knowledge is spread across the person's email, calendar, files, chat and other systems. Ingest brings what is worth keeping into the firm's Real Agent knowledge base, its organisational knowledge base (OKB). It runs only when the person asks, or says yes to the offer at a session's start. It never saves anything the person has not agreed to.

The sources are the connectors and plugins the person has in Claude, such as Gmail, Google Drive, Slack, Microsoft 365 or a CRM. The person can point a source at one part of it, such as a Gmail label, a Drive folder or a Slack channel. Each source remembers where it got to, so each run reads only what is new.

This skill belongs to the database operator, `@real-agent:database-operator`. It saves records as the `okb:records` skill's section 3 describes, and uploads files as the `okb:actor` skill describes. It uses the `okb:writing` skill for what it tells the person.

## Choose the mode

The person chooses the mode.

- **Human only:** the person follows the Person lines below, without the agent. They read their own sources, and save each item with the `okb` command.
- **AI guided:** the person asks the agent to guide them. Before each step, the agent says what the step does and shows the Person line. It follows its own line with the person watching, or asks the person to follow theirs. It stops for the person's approval at the end of each stage.
- **Human directed:** the person tells the agent what to do, such as "add this week's supplier emails". The agent follows its lines for each step the person directs.

Each step below gives a **Person** line and a line for the agent.

With the agent, the person's own instruction replaces a rule of this skill, such as which items are worth keeping. The agent names the rule once and does as told. A refusal from OKB or a tool still stands, and the agent gives it to the person with what they can do instead.

## The sources file

The agent keeps the sources in `ingest-sources.json`, directly in the agent folder. It is the agent's own note of where each source got to. It holds nothing from the sources themselves. One entry per source:

```json
{
  "sources": [
    {
      "source": "Gmail",
      "part": "label Suppliers",
      "scope": "general",
      "status": "on",
      "last_item_at": "the newest item's time, as an ISO 8601 date and time",
      "last_run_at": "the last run's time, as an ISO 8601 date and time"
    }
  ]
}
```

- "source" is what the person calls the connector or plugin.
- "part" is the part of it the person pointed to, or "all".
- "scope" is the code of the scope the person chose for its items.
- "status" is "on", or "off" once the person said no to it. The agent never offers a source that is off, until the person asks for it.
- "last_item_at" is when the newest item read in the last run arrived, saved or not. The next run reads only items after it.

The agent reads the file with `read_file`. It writes it with `Write` after each run, and after the person adds, points or stops a source. It tells the person in one line what changed in it, and needs no agreement for that. When the file is missing, no source is on yet.

## 1. At the start of a session

1. **Check the sources that are on.**
   - **Person:** opens each source they ingest from, and looks for what arrived since they last added anything.
   - **The agent:** after its first steps, reads `ingest-sources.json`. For each source that is on, it counts the items after its "last_item_at", and reads none of them yet. It uses that connector's or plugin's own tools to search or list. Claude Code asks the person the first time each connector is used in a session. A source the person denies is left for this session.
2. **Offer once.**
   - **Person:** decides whether to go through what is new.
   - **The agent:** when any source has new items, ends the first reply with room for it with one line. The line names each source and its count. An example is "Since your last import: 14 new emails in Gmail and 3 new files in Google Drive. Shall I go through them?" That reply holds no other question, as the writing skill's "One issue at a time" says. It offers once per session. With nothing new, it says nothing about ingest.

**AI guided:** the agent gives the person each source's count, and waits for their yes.

## 2. Add a source

1. **See what can be a source.**
   - **Person:** looks at **Customize → Connectors** in Claude, and at their plugins.
   - **The agent:** names the connectors and plugins in the session that hold the firm's information. Those are mail, calendars, files, chat, a CRM, notes or tickets. It leaves out tools that hold none, such as a search engine. It does this when the person asks what it could ingest from, or asks to ingest with no source on.
2. **Point it.**
   - **Person:** says which source to add, and which part of it, such as "my Gmail label Suppliers" or "the Sales channel in Slack".
   - **The agent:** asks which scope its items go in, from the scopes the person may create in. It offers General for the firm's shared knowledge, and the person's private scope for their own mail. It asks how far back the first run goes, and offers the last 30 days.
3. **Record it.**
   - **Person:** notes the source, its part, its scope and the day to start from.
   - **The agent:** adds the source to `ingest-sources.json`, with "last_item_at" set to the start of that period. It says so in one line.

**AI guided:** the agent gives the person the new source's entry, and waits for their approval.

## 3. Go through what is new

1. **Read the new items.**
   - **Person:** reads each item that arrived since they last added anything.
   - **The agent:** reads each new item in each source that is on, oldest first, in the part the person pointed to. It uses the source's own tools. It reads at most 50 items in a run, and says when more are waiting.
2. **Pick what is worth keeping.**
   - **Person:** keeps each item that holds something the firm will need again.
   - **The agent:** keeps an item that holds a fact, decision, commitment, price, date, contact detail or document the firm will need again. It passes over newsletters, adverts, automatic notices and chat with nothing decided in it. It also passes over anything OKB already holds, which it checks with a file search for the item's subject. When unsure, it keeps the item and says why.
3. **Show what it found.**
   - **Person:** lists the items to save.
   - **The agent:** shows one table of the items it kept. The columns are the source, the item, what it holds in one line, and what it would become. That is an evidence record, a file, or both. A record also names any record it would link to, such as a customer's model record. One line below the table gives how many items it passed over, and why. It asks one question: which to save.

**AI guided:** the agent shows the table, and waits for the person's choice.

## 4. Save what the person agrees to

1. **Save each item as a record.**
   - **Person:** runs `okb okb_add_record p_scope=<scope> p_kind=evidence p_title="<title>" p_reason="Ingested from <source>" p_fields.summary="<what it holds>" p_fields.source_reference="<link>" p_fields.source_date=<date> p_fields.standing=stated p_fields.limitations="<limits>" p_preview=true`, then saves it.
   - **The agent:** previews an evidence record for each item the person chose, in the source's scope. It calls `okb_add_record` with `p_preview` true, as the records skill's section 3 describes. The title names the item, such as "Email from Harbour Timber: new prices from 1 December". The fields are:
     - `summary`: what the item holds that the firm needs, in plain English. Each fact, figure and date is as the item gives it. It is not a copy of the whole item.
     - `source_reference`: the item's own link in its source, when it starts `https://`. Otherwise it is plain words naming the source and the item, such as "Gmail, from Harbour Timber, 24 October 2026".
     - `source_date`: the day the item was sent, made or held.
     - `standing`: `stated` for what a person wrote or said, and `observed` for a record a system made, such as an invoice.
     - `limitations`: what the item does not show, such as "the attached price list was not read", or "none".
2. **Link it.**
   - **Person:** names the record the item is about, if any.
   - **The agent:** links the record to a record OKB holds in the same scope, when the item is about it. That may be a customer, a supplier, a plan or an activity. The link is `describes`, to that record's current version, as the records skill's section 3 describes.
3. **Upload each file.**
   - **Person:** downloads the document from its source, and uploads it with `okb upload_file`.
   - **The agent:** downloads a document the person chose into the agent folder, with the source's own tool. A contract or a price list is an example. It uploads it to the source's scope with `upload_file`, as the database operator's upload rule says. Its evidence record's `file_sha256` is the file's checksum.
4. **Save after one yes.**
   - **Person:** checks each preview, then saves it.
   - **The agent:** shows every save and upload together, as the records skill's section 3 describes. It saves them all after the person's one yes, in words in the chat. It reports each save in one line, and each refusal with OKB's own message.
5. **Move the mark on.**
   - **Person:** notes the newest item they read.
   - **The agent:** sets each source's "last_item_at" to the newest item read in this run, saved or passed over. It sets "last_run_at" to now, and writes `ingest-sources.json`.

**AI guided:** the agent gives the person the list of saves, and waits for their approval.

## 5. Change or stop a source

1. **Change it.**
   - **Person:** says to point a source at another part, change its scope, or stop it.
   - **The agent:** changes its entry in `ingest-sources.json`, and says so in one line. A stopped source is set to "off", and stays in the file. The agent never offers it again unasked. Records already saved stay in OKB.

**AI guided:** the agent gives the person the changed entry, and waits for their approval.

## Problems

- **A connector is not signed in, or has no tools:** the agent says so. It tells the person to connect it at **Customize → Connectors**, then start a new Code session.
- **The person denies Claude Code's prompt for a connector:** the agent leaves that source for this session, and says so in one line.
- **A save is refused:** the agent gives OKB's own message, and what it means from the records skill's "Problems with records". The source's mark does not move past that item.
- **An item's link would hold a person's details:** the agent names the source and the item in plain words instead. It never puts personal data in a link.
