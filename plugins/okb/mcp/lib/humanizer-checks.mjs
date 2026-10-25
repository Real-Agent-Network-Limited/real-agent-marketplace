// The humanizer plugin's checks, version 0.2.2, from its translate skill (Agent Bench, MIT licence),
// copied as the file's own header asks, unchanged below this header.
// Replace it whole, from a newer version of the humanizer plugin.

// The rules that can be a regular expression. Copy this file into any builder
// that produces prose and run `check()` over every authored string.
//
// Half of translate cannot be checked. Those rules are marked in SKILL.md and
// caught by reading. The point of this file is that the other half never has to
// be.
//
// No dependency. Node 18 or later.

// Twenty-five words is the cap ASD-STE100 sets for descriptive writing, and six
// sentences is the cap it sets for a paragraph. Both are counts, so both belong
// here. The sentence cap was thirty until the STE number replaced it.
export const MAX_SENTENCE_WORDS = 25;
export const MAX_PARAGRAPH_SENTENCES = 6;

// Words that name the same thing. A document picks one member of a set and uses
// it throughout; two members in one document send a reader looking for a
// distinction that is not there.
//
// The membership is a judgement and belongs to the project, so extend this list
// whenever a document is found using two words for one thing. The mechanism is
// form: counting two strings in one passage decides nothing about meaning.
export const TERM_SETS = [
  ["agent", "assistant", "bot", "worker"],
  ["folder", "directory"],
  ["machine", "computer", "box"],
  ["repo", "repository"],
  ["config", "configuration"],
  ["start", "launch", "boot"],
];

// Below this many uses, a word is a passing mention rather than the name the
// document has settled on.
const TERM_MIN_USES = 2;

const EM_DASH = /[—–]/;

// Words and constructions that inflate. Narrow on purpose: a rule that fires on
// plain writing gets routed around, and then it catches nothing.
const INFLATION = new RegExp([
  "\\b(?:leverage|leveraging|unlock|unlocks|unleash|empower|empowers|harness",
  "|seamless|seamlessly|robust|scalable|cutting.edge|state.of.the.art|world.class",
  "|myriad|plethora|pivotal|paradigm|synergy|holistic|transformative|revolutionary",
  "|game.chang\\w+|next.level|impactful|testament to|tapestry|beacon|symphony",
  "|journey|landscape of|realm of|delve|delves into|elevate|elevates)\\b",
  // "it is not X, it is Y" used as a move rather than a correction.
  "|\\b(?:it|this|that)(?:'s| is) not (?:just |merely |simply )?\\w+[^.]{0,40}, (?:it|this|that)(?:'s| is)\\b",
  // A sentence that ends by restating its own point as a moral.
  "|\\bwhich is (?:what|why|where) [^.]{0,60}$",
].join(""), "im");

// A status message written as though it were content. "Reading the code and
// writing the explanation. It takes a few seconds." was put where an explanation
// belonged, and the reader asked how knowing the duration helped them understand
// the function. It does not. A closed list, so this decides form, not meaning.
const WAFFLE =
  /\b(?:a few (?:seconds|moments)|just a (?:second|moment)|in a moment|please wait|hang tight|this (?:may|might|will) take|shortly|almost (?:there|done)|working on it|one moment)\b/i;

// Project bookkeeping that reached the writing. A task number, a plan, a date
// something was measured on, or the story of what somebody found out and when.
// It means nothing outside the tracker it came from. The line is whether the
// number describes the thing or the project: "takes about 14 seconds to stop"
// stays, "measured on 2026-08-14" goes.
//
// Decidable by form: a task number has a shape, and so does a date.
const INTERNAL = new RegExp([
  "\\btasks?\\s*#?\\d+",
  "|\\b(?:plan|prd|spec|ticket|issue|epic|story)\\s*#?\\d+(?:\\.\\d+)*",
  "|\\bPRD\\b",
  "|\\b\\d{4}-\\d{2}-\\d{2}\\b",
  "|\\b(?:episode|postmortem|post-mortem|incident report)\\b",
  "|\\bwe\\s+(?:found|saw|hit|learned|tried|discovered|decided|used to)\\b",
  "|\\b(?:used to be|previously|formerly|originally|until recently)\\b",
].join(""), "i");

// Prose about the page rather than about the subject.
const SELF_NARRATION =
  /\b(?:this (?:page|document|report|view|map)|on this page|shown (?:here|below|above)|the (?:code|file|tree|list) (?:below|above)|read from the (?:repository|disk)|as it is on disk|what you are looking at)\b/i;

// A bare count as its own sentence, and the absolute that follows it.
const COUNT_FRAGMENT =
  /^(?:One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|\d+)\s+[\w' ]{2,30}[.,][\w' ]{0,20}\.$/i;
const THERE_ARE =
  /^There (?:are|is)\s+(?:one|two|three|four|five|six|seven|eight|nine|ten|\d+)\.$/i;
const ABSOLUTE_OPENER = /^(?:None|All|Both|Every one|Not one|Each) of them\b/i;

// A definition written as a sensory scene instead of a definition. "What a
// person sees and touches" for user interface, whose standard definition is
// "the part of a device or application through which a person interacts with
// it". The paraphrase feels vivid and carries less.
// A definition written as a sensory scene instead of a definition. The standard
// definition of user interface is "the part of a device, application, or website
// through which a person interacts with it". What got written was "What a person
// sees and touches".
const PARAPHRASE =
  /^\s*(?:What|How) (?:a |the )?(?:person|user|reader|someone)\b[^.]{0,40}\b(?:sees|touches|feels|hears|watches|looks at|does)\b/i;

// Human faculties given to software where a technical verb exists. Verbs the
// field already uses stay: a server listens, a process sleeps, a lock is held,
// a parser reads.
const ANTHROPOMORPHIC =
  /\b(?:talks?|speaks?|chats?) (?:to|with)\b|\b(?:sees|saw|watches?|watching|looks? at|feels?|hears?|smells?)\b|\b(?:thinks?|believes?|knows?|understands?|wants?|hopes?|remembers?|forgets?)\b|\b(?:sits?|lives?|wanders?|wakes? up|breathes?|reaches? for)\b|\bputs? (?:it|them) (?:on|in|into)\b|\bhands? (?:it|them|the)\b/i;

// A name with a participial tag hung off it, used as a title. "Ledger, read end
// to end". "The pipeline, explained". The tag says nothing the name did not
// and nothing a reader could not assume, and the shape is one of the clearest
// markers of machine-written titling.
//
// Decidable by form: the whole string is a noun phrase, a comma, and a past
// participle from a closed list. Prose does not match, because a sentence has a
// finite verb and this shape has none.
const TITLE_TAG = new RegExp(
  // The head is a bare name, so a relative clause or a finite verb in it means this is a
  // sentence rather than a title, and the check stays out of prose.
  "^(?!.{0,60}\\b(?:that|which|who|whom|is|are|was|were|will|would|can|cannot|has|have|had|does|do|did)\\b)" +
  "[^,.!?]{1,60}, " +
  "(?:read|explained|explored|unpacked|decoded|demystified|deconstructed|dissected" +
  "|revisited|reconsidered|rethought|reimagined|examined|mapped|charted|distilled" +
  "|annotated|uncovered|revealed|laid bare|made simple|broken down|walked through" +
  "|from the inside|in full|at a glance|end to end|line by line|top to bottom)" +
  "\\b[^.!?]{0,40}\\.?$",
  "i",
);

// A sentence whose whole job is to promote the sentence before it. The fact came
// first and is checkable; this one is that fact again with a superlative on it,
// and the instruction after it is the reason the pair was written.
//
// The openers are a closed list, so this decides form. Whether what follows is
// an instruction has to be read. "Which means" is left to reading, because it
// usually carries a consequence the reader did not already have.
const ELEVATION =
  /(?:^|[.!?]\s+)(?:that|this|which)\s+(?:makes|made|is what makes)\s+(?:it|this|that|them)\b/im;

// A sentence explaining how a table or list is labelled, which the reader can
// already see. "Seven stages, lettered A to G so they are not confused with
// the numbered lessons" sat above a table whose first column read A to G.
// Across 333 documents in five folders no other sentence had either shape.
const LEGEND =
  /\b(?:lettered|numbered)\s+(?:[A-Z]|\d+)\s+to\s+(?:[A-Z]|\d+)\b|\bso (?:they|it|these|the \w+) (?:are|is) not confused with\b/i;

// A general rule, then "Here" standing in for "in this project" before the
// example. "Interview the person who owns the routine. Here that was the head of operations."
// Once is ordinary English. Repeated, it is the joint of a document compressed
// into rules with its examples bolted on, and a reader hears it as a template.
//
// The repetition is the tell, so this counts. One tutorial used it eight times,
// and across 215 other documents in four repositories none used it three times.
// "Here it is", "Here is" and "Here are" present a thing and are left alone.
const HERE_PIVOT =
  /(?:^|[.!?]\s+)Here,? (?!it is\b|is\b|are\b)(?:the|it|that|this|they|only|each|every|both|all|[A-Z][a-z]+(?:'s)?)\b/gm;
const HERE_PIVOT_LIMIT = 3;

// A heading, a table row and a list item each end where the line ends, and none
// of them carries terminal punctuation. Splitting on punctuation alone ran a
// heading into the paragraph under it and counted a whole table as one
// sentence, so the text is cut into units by line structure first.
const STRUCTURAL = /^\s*(?:#{1,6}\s|\||[-*+]\s|\d+[.)]\s|>|\s{4}\S)/;
const TABLE_ROW = /^\s*\|/;
const BLOCK_QUOTATION = /^\s*>/;

// A full stop inside a quotation is the quoted writer's, so cutting there put a
// citation half in one sentence and half in the next. The quote is masked to a
// run of one letter first, which keeps every offset and hides the punctuation.
// The full stop a quotation ends on is kept, because it also ends the sentence
// the quotation sits in. Everything before it goes, so the punctuation inside a
// citation no longer cuts it in half.
const maskQuoted = (u) =>
  u.replace(QUOTED, (m) => {
    const inner = m.slice(1, -1);
    const tail = /[.!?]$/.test(inner) ? inner.slice(-1) : "";
    return m[0] + "q".repeat(Math.max(0, inner.length - tail.length)) + tail + m.slice(-1);
  });

const SENTENCE_END =
  /(?<=[.!?])\s+|(?<=[.!?]\*{1,2})\s+|(?<=[.!?]["\u201D])\s+/g;

// A full stop inside an abbreviation does not end a sentence. Masking it keeps
// "the surrounding doc (e.g. \"vol-of-VIX\")" in one piece.
const ABBREVIATION = /\b(?:e\.g|i\.e|etc|cf|vs|approx|Mr|Mrs|Ms|Dr|St|No|Fig|Ch|pp?)\./gi;

const maskAbbreviations = (u) => u.replace(ABBREVIATION, (m) => m.replace(/\./g, "q"));

const cut = (unit) => {
  const masked = maskAbbreviations(maskQuoted(unit));
  const out = [];
  let start = 0;
  SENTENCE_END.lastIndex = 0;
  for (let m; (m = SENTENCE_END.exec(masked)); ) {
    out.push(unit.slice(start, m.index));
    start = m.index + m[0].length;
  }
  out.push(unit.slice(start));
  return out;
};

const units = (text) => {
  const out = [];
  let run = [];
  const flush = () => { if (run.length) out.push(run.join(" ")); run = []; };
  for (const line of withoutCode(text).split("\n")) {
    if (!line.trim()) { flush(); continue; }
    if (STRUCTURAL.test(line)) { flush(); out.push(line.trim()); continue; }
    run.push(line.trim());
  }
  flush();
  return out;
};

const sentences = (text) =>
  units(text)
    // A table row is cells rather than a sentence, and a block quotation is
    // somebody else's writing. Neither is the writer's to shorten.
    .filter((u) => !TABLE_ROW.test(u) && !BLOCK_QUOTATION.test(u))
    .flatMap(cut)
    .map((x) => x.trim())
    .filter(Boolean);

const words = (s) => s.replace(QUOTED, " q ").split(/\s+/).filter(Boolean).length;

const withoutCode = (text) =>
  String(text).replace(/```[\s\S]*?```/g, "").replace(/`[^`]*`/g, "");

// A quoted span counts as one word, and its punctuation never ends a sentence.
// These documents quote the prose they reject, and reading a citation as the
// writer's own put 33 findings on them that no rewrite could clear. The term
// check reads past quotations already, for the same reason.
const QUOTED = /"[^"]*"|[\u201C][^\u201D]*[\u201D]/g;

// A heading, a list item, a table row, a block quotation and an indented code
// block are not paragraphs. Only running prose is counted.
const NOT_A_PARAGRAPH = /^\s*(?:#|\||>|[-*+]\s|\d+[.)]\s|\s{4}\S)/;

const paragraphs = (text) =>
  withoutCode(text)
    .split(/\n\s*\n/)
    .map((b) => b.trim())
    .filter((b) => b && !NOT_A_PARAGRAPH.test(b));

// A document that quotes prose it rejects names the wrong word on purpose.
// Removing quotations took the false positives on the register's own files from
// four to none, so the term check reads this rather than the raw text.
const withoutQuotations = (text) =>
  withoutCode(text)
    .replace(/"[^"]{0,300}"/g, " ")
    .replace(/[\u201C][^\u201D]{0,300}[\u201D]/g, " ")
    .replace(/^\s*>.*$/gm, " ")
    .replace(/^\s*\|.*$/gm, " ")
    // A list item that is nothing but comma-separated single words is a
    // glossary of those words, not prose that uses two of them. Rule 17
    // declares its own sets in exactly this shape.
    .replace(/^\s*[-*+]\s*(?:[a-z]+,\s*)+[a-z]+\s*$/gim, " ")
    .toLowerCase();

const countWord = (text, word) =>
  (text.match(new RegExp("\\b" + word + "s?\\b", "g")) || []).length;

/**
 * Every rule this file can decide, applied to one passage.
 *
 * @param {string} text
 * @returns {Array<{rule: string, at: string}>} empty when the passage passes
 */
export function check(text) {
  const out = [];
  const push = (rule, at) => out.push({ rule, at: String(at).slice(0, 80) });
  const parts = sentences(text);

  if (EM_DASH.test(text)) push("em-dash", "use a comma, a colon, or two sentences");
  if (INFLATION.test(text)) push("flourish", INFLATION.exec(text)[0]);
  if (SELF_NARRATION.test(text)) push("self-narration", SELF_NARRATION.exec(text)[0]);
  if (WAFFLE.test(text)) push("waffle", WAFFLE.exec(text)[0]);
  if (INTERNAL.test(text)) push("internal-reference", INTERNAL.exec(text)[0]);
  if (TITLE_TAG.test(text)) push("title-tag", TITLE_TAG.exec(text)[0]);
  // Quoted examples of the shape are citations, not the writer's own legend.
  if (LEGEND.test(withoutQuotations(text))) push("legend", LEGEND.exec(withoutQuotations(text))[0]);
  if (ELEVATION.test(text)) push("elevation", ELEVATION.exec(text)[0].trim());

  const pivots = withoutCode(text).replace(/^\s*>.*$/gm, " ").match(HERE_PIVOT) || [];
  if (pivots.length >= HERE_PIVOT_LIMIT) {
    push("here-pivot", `${pivots.length} times: ${pivots.map((x) => x.replace(/^[.!?]?\s*/, "")).join(" / ")}`);
  }

  for (const s of parts) {
    if (COUNT_FRAGMENT.test(s) || THERE_ARE.test(s) || ABSOLUTE_OPENER.test(s)) {
      push("count-fragment", s);
    }
    if (words(s) > MAX_SENTENCE_WORDS) push("sentence-too-long", s);
  }

  for (const block of paragraphs(text)) {
    const n = sentences(block.replace(/\n/g, " ")).length;
    if (n > MAX_PARAGRAPH_SENTENCES) {
      push("paragraph-too-long", `${n} sentences: ${block}`);
    }
  }

  // One name per thing, for the length of the document.
  const plain = withoutQuotations(text);
  for (const set of TERM_SETS) {
    const used = set
      .map((w) => [w, countWord(plain, w)])
      .filter(([, n]) => n >= TERM_MIN_USES);
    if (used.length > 1) {
      push("two-names-one-thing", used.map(([w, n]) => `${w}(${n})`).join(", "));
    }
  }

  return out;
}

/** True when the passage breaks nothing this file can decide. */
export const passes = (text) => check(text).length === 0;
