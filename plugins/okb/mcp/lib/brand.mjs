// The firm's brand, as OKB keeps it: one model record in General titled Brand. Its brand node's attributes hold the
// palette, six tokens each with a light and a dark value, the heading and body fonts, and the logo, a small copy as a
// data address, with a second copy for dark mode where the logo's own has dark text. readBrand reads it as the signed-in person. brandOf keeps only the values that are a colour, a font's
// name or a picture's data address, so no value can carry markup or a style of its own into a card or a page.
//
// The okb plugin's styles/ folder holds tokens.css, Real Agent's own value for each --brand- custom property, and one
// stylesheet for each kind of card or page, each reading only those properties. cardTokens and printTokens give the same
// properties from a firm's brand, each token the brand lacks taking the plain value, so a branded card or page never
// mixes Real Agent's colours with the firm's. A card takes the light and the dark palette, and follows the chat's
// theme; a printed page or deck takes the light palette.
//
// This file is the one source of all of it: the okb plugin's page tools import it, and workers/connector/make-cards.mjs
// copies it into the connector as src/brand-core.ts, whose card_page dresses the cards with it.

/** The palette's tokens. accent_text is the accent deepened for legible text on paper. */
export const TOKENS = ["ink", "paper", "muted", "rule", "accent", "accent_text"];
const COLOUR = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i;
const FONT = /^[A-Za-z0-9][A-Za-z0-9 -]{0,59}$/;
const GENERIC = new Set(["serif", "sans-serif", "monospace", "cursive", "system-ui", "ui-serif", "ui-sans-serif", "ui-monospace"]);
const PICTURE = /^data:image\/(?:png|jpeg|gif|webp);base64,[A-Za-z0-9+/]+={0,2}$/;
/** The longest logo copy a card or page takes, in characters of its data address: a picture 200 pixels across. */
export const MAX_LOGO = 300_000;
/** Where a card may load the brand's Google Fonts from. */
export const FONT_DOMAINS = ["https://fonts.googleapis.com", "https://fonts.gstatic.com"];
/** How long a card or page waits for the brand before it takes its look without one. */
export const BRAND_WAIT_MS = 5000;

/** A card's plain value of each --brand- property: the chat's own colours and type. */
const PLAIN_CARD = {
  ink: "var(--color-text-primary, CanvasText)", paper: "var(--color-background-primary, Canvas)", surface: "var(--color-background-secondary, rgba(128, 128, 128, .08))",
  muted: "var(--color-text-secondary, GrayText)", rule: "var(--color-border-primary, rgba(128, 128, 128, .4))",
  accent: "var(--color-text-primary, CanvasText)", "on-accent": "var(--color-background-primary, Canvas)", "accent-text": "var(--color-text-primary, CanvasText)",
  "heading-font": "var(--font-sans, system-ui, sans-serif)", "body-font": "var(--font-sans, system-ui, sans-serif)",
};
/** A printed page's or deck's plain value of each --brand- property: the print skill's plain style. */
const PLAIN_PRINT = {
  ink: "#313131", paper: "#ffffff", surface: "#f0eee6", muted: "#5f5e5a", rule: "rgba(49, 49, 49, .24)",
  accent: "#8f8d86", "on-accent": "#ffffff", "accent-text": "#1a9fff",
  "heading-font": '"Helvetica Neue", Arial, sans-serif', "body-font": '"Helvetica Neue", Arial, sans-serif',
};

const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

/** A font's fallbacks: each a font's name or a generic family, ending in a generic one. */
function fallbackOf(text) {
  const names = String(text ?? "").split(",").map(n => n.trim()).filter(n => FONT.test(n));
  return names.some(n => GENERIC.has(n)) ? names : [...names, "sans-serif"];
}

/** Whether a value is a logo's copy a card or page may take: a PNG, JPEG, GIF or WebP data address of at most MAX_LOGO. */
const pictureOf = v => typeof v === "string" && v.length <= MAX_LOGO && PICTURE.test(v);

/** The brand from okb_show_record's answer for the Brand record, or null where it holds nothing a card can use. */
export function brandOf(record) {
  const nodes = record?.payload?.graph?.nodes;
  const node = Array.isArray(nodes) ? nodes.find(n => n?.type === "brand") : null;
  const a = node?.attributes;
  if (!a || typeof a !== "object") return null;
  const palette = { light: {}, dark: {} };
  for (const mode of ["light", "dark"]) {
    for (const token of TOKENS) {
      const c = a.palette?.[mode]?.[token];
      if (typeof c === "string" && COLOUR.test(c.trim())) palette[mode][token] = c.trim().toLowerCase();
    }
  }
  const fonts = {};
  for (const role of ["heading", "body"]) {
    const f = a.fonts?.[role];
    if (typeof f?.family === "string" && FONT.test(f.family.trim())) fonts[role] = { family: f.family.trim(), google: f.source === "google", fallback: fallbackOf(f.fallback) };
  }
  const l = a.logo;
  const logo = pictureOf(l?.data_address)
    ? { src: l.data_address, alt: typeof l.alt === "string" && l.alt.trim() ? l.alt.trim() : String(node.label ?? "") } : null;
  // The dark-mode copy goes with the logo only: with no logo, there is nothing for it to stand in for.
  if (logo && pictureOf(l.dark?.data_address)) logo.dark = l.dark.data_address;
  if (!Object.keys(palette.light).length && !Object.keys(palette.dark).length && !Object.keys(fonts).length && !logo) return null;
  return { name: String(node.label ?? ""), palette, fonts, logo };
}

/** A font's family and fallbacks as CSS gives them: a generic family as it is, and every font's name in quotes. */
export const stack = f => [`"${f.family}"`, ...f.fallback.map(n => GENERIC.has(n) ? n : `"${n}"`)].join(", ");
/** The brand's [light, dark] values of a token, each falling back on the other, or null where it gives neither. */
export const pairOf = (brand, token) => {
  const light = brand?.palette.light[token] ?? brand?.palette.dark[token], dark = brand?.palette.dark[token] ?? light;
  return light ? [light, dark] : null;
};

/** A colour's relative luminance, as WCAG 2 measures it. */
function luminance(hex) {
  const h = hex.length === 4 ? hex.slice(1).split("").map(c => c + c).join("") : hex.slice(1);
  return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16) / 255)
    .map(v => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)
    .reduce((sum, v, i) => sum + v * [0.2126, 0.7152, 0.0722][i], 0);
}
/** The contrast of two colours, from 1 to 21, as WCAG 2 measures it. */
export function contrast(a, b) {
  const [x, y] = [luminance(a), luminance(b)];
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}
/** Text on a fill of the accent: the palette's ink or paper, whichever reads better on it, where that reads at 4.5 to 1,
 * and otherwise black or white, whichever reads better. */
export function onAccent(accent, palette) {
  const best = choices => choices.reduce((a, b) => contrast(b, accent) > contrast(a, accent) ? b : a);
  const own = [palette.ink, palette.paper].filter(Boolean);
  if (own.length && contrast(best(own), accent) >= 4.5) return best(own);
  return best(["#000000", "#ffffff"]);
}

/** Each --brand- property's value from the brand, for one mode, or null for a token the brand lacks. */
function valuesOf(brand, mode) {
  const p = { ...(mode === "dark" ? brand.palette.light : brand.palette.dark), ...brand.palette[mode] };
  return {
    ink: p.ink ?? null, paper: p.paper ?? null, muted: p.muted ?? null, rule: p.rule ?? null,
    // A raised surface: the paper with two fifths of the rule in it.
    surface: p.paper && p.rule ? `color-mix(in srgb, ${p.rule} 40%, ${p.paper})` : null,
    accent: p.accent ?? null, "on-accent": p.accent ? onAccent(p.accent, p) : null, "accent-text": p.accent_text ?? p.accent ?? null,
  };
}
const fontsOf = brand => ({ "heading-font": brand.fonts.heading ? stack(brand.fonts.heading) : null, "body-font": brand.fonts.body ? stack(brand.fonts.body) : null });
const declarations = values => Object.entries(values).map(([k, v]) => `  --brand-${k}: ${v};`).join("\n");

/** The @import of the brand's Google Fonts, or nothing. It goes first in a stylesheet. */
export function fontImport(brand) {
  const families = [...new Set(["heading", "body"].map(r => brand?.fonts[r]).filter(f => f?.google).map(f => f.family))];
  return families.length ? `@import url("https://fonts.googleapis.com/css2?${families.map(f => `family=${f.replace(/ /g, "+")}:wght@400;600`).join("&")}&display=swap");\n` : "";
}

/** The tokens a card takes from the brand's light palette in the dark theme too: a fill and the text on it, which read in
 * either theme. Every other token takes the chat's own dark value where the brand gives no dark ink and paper. */
const ON_EITHER = new Set(["accent", "on-accent"]);

/** A card's --brand- properties from the brand, each in light and dark, so the card follows the chat's theme. A token the
 * brand lacks takes the chat's own value. A brand with no dark ink and paper of its own takes the chat's dark values for
 * its text, surfaces and rules, since its light ones would be dark on a dark chat. They go after tokens.css, so they win. */
export function cardTokens(brand) {
  const light = valuesOf(brand, "light"), dark = valuesOf(brand, "dark"), fonts = fontsOf(brand);
  const ownDark = Boolean(brand.palette.dark.ink && brand.palette.dark.paper);
  const values = {};
  for (const k of Object.keys(PLAIN_CARD)) {
    if (k in fonts) { values[k] = fonts[k] ?? PLAIN_CARD[k]; continue; }
    if (!light[k]) { values[k] = PLAIN_CARD[k]; continue; }
    const night = ownDark || ON_EITHER.has(k) ? dark[k] ?? light[k] : PLAIN_CARD[k];
    values[k] = `light-dark(${light[k]}, ${night})`;
  }
  return `:root {\n${declarations(values)}\n}\n`;
}

/** A printed page's or deck's --brand- properties from the brand's light palette. A token the brand lacks takes the plain
 * value. */
export function printTokens(brand) {
  const light = valuesOf(brand, "light"), fonts = fontsOf(brand);
  const values = Object.fromEntries(Object.keys(PLAIN_PRINT).map(k => [k, (k in fonts ? fonts[k] : light[k]) ?? PLAIN_PRINT[k]]));
  return `:root {\n  color-scheme: light;\n${declarations(values)}\n}\n`;
}

/** A printed page's or deck's whole brand style: its fonts' @import, its tokens, then the kind's stylesheet. */
export const printStyle = (brand, kindCss) => `${fontImport(brand)}${printTokens(brand)}${kindCss.trimEnd()}\n`;

/** The brand's logo as an <img> of the class given, or nothing. It is the light logo always, as paper takes it. */
export const logoHtml = (brand, cls) => brand?.logo ? `<img class="${cls}" alt="${esc(brand.logo.alt)}" src="${brand.logo.src}">` : "";

/** The brand's logo for a card, as <img> of the class given, or nothing. With a dark-mode copy it is two: the light
 * logo, then the dark one, hidden. LOGO_SWITCH shows the one that fits the light or dark mode the card is in. */
export const themedLogoHtml = (brand, cls) => brand?.logo?.dark
  ? `<img class="${cls}" data-scheme="light" alt="${esc(brand.logo.alt)}" src="${brand.logo.src}">` +
    `<img class="${cls}" data-scheme="dark" alt="${esc(brand.logo.alt)}" src="${brand.logo.dark}" hidden>`
  : logoHtml(brand, cls);

/** A card's code that shows its dark logo in dark mode and its light logo otherwise. A card is in dark mode where the
 * palette's light-dark() takes its dark value at the logo: the same test that picks the brand's dark accent. It looks
 * again when the computer's mode changes, and when Claude sets the card's mode on its root. */
export const LOGO_SWITCH = `;(function () {
  var logos = document.querySelectorAll("img[data-scheme]");
  if (!logos.length) return;
  function dark(img) {
    var probe = document.createElement("span");
    probe.style.cssText = "position: absolute; visibility: hidden; color: #000; color: light-dark(#000, #fff);";
    img.parentNode.appendChild(probe);
    var seen = getComputedStyle(probe).color;
    probe.remove();
    return seen === "rgb(255, 255, 255)";
  }
  function show() {
    Array.prototype.forEach.call(logos, function (img) { img.hidden = (img.getAttribute("data-scheme") === "dark") !== dark(img); });
  }
  show();
  if (window.matchMedia) window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", show);
  if (window.MutationObserver) new MutationObserver(show).observe(document.documentElement, { attributes: true, attributeFilter: ["style", "class"] });
})();
`;

/** The value of work, or null where work fails or takes longer than ms. With strict, a failure or the wait running out
 * throws instead. The timer never keeps the process alive. */
async function within(ms, work, strict = false) {
  let timer;
  const late = new Promise((done, fail) => {
    timer = setTimeout(() => strict ? fail(new Error("OKB didn't answer in time.")) : done(null), ms);
    if (typeof timer === "object") timer?.unref?.();
  });
  const done = Promise.resolve().then(work);
  try { return await Promise.race([strict ? done : done.catch(() => null), late]); } finally { clearTimeout(timer); }
}

/**
 * The Brand record in General, read with call(fn, args), which runs one OKB function as the signed-in person and gives its
 * result or throws. The newest model record in General titled Brand, in any case, is the brand. With none, no grant to
 * read General, a refusal, or no answer within BRAND_WAIT_MS, there is no brand. With strict, a refusal or no answer in
 * time throws, and null means OKB holds no Brand record. Nothing is kept between reads.
 */
export function readBrand(call, { wait = BRAND_WAIT_MS, strict = false } = {}) {
  return within(wait, async () => {
    let general = null, cursor = null;
    do {
      const page = await call("okb_get_scopes", { p_cursor: cursor, p_limit: 100 });
      general = (page?.items ?? []).find(s => s.code === "general") ?? null;
      cursor = page?.next_cursor ?? null;
    } while (cursor && !general);
    if (!general) return null;
    // The title search matches any title holding the word, newest first, so each page is read until the Brand record.
    let hit = null;
    cursor = null;
    do {
      const found = await call("okb_find_records", { p_kind: "model", p_scope_id: general.scope_id, p_title: "Brand", p_cutoff: null, p_cursor: cursor, p_limit: 100 });
      hit = (found?.items ?? []).find(r => String(r.title ?? "").trim().toLowerCase() === "brand") ?? null;
      cursor = found?.next_cursor ?? null;
    } while (cursor && !hit);
    if (!hit) return null;
    return brandOf(await call("okb_show_record", { p_record: hit.record_id }));
  }, strict);
}
