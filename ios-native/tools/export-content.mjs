// Copies the website's content tables into the Swift package, so both apps read one source.
// Run after editing quotes, extra-credit questions, themes or the "Next" list in index.html:
//   node ios-native/tools/export-content.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadWeb } from "./load-web.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const w = loadWeb("2026-10-01T12:00:00");
const content = {
  quoteCategories: w.QUOTE_CATS.map(([id, name]) => ({ id, name })),
  quotes: w.QUOTES.map(q => ({ c: q.c, a: q.a, t: q.t })),
  extraCredit: w.EC_QUESTIONS,
  themes: w.THEMES,
  nextHabits: w.NEXT_HABITS.map(h => ({ name: h.name, when: h.when, tag: h.tag, sum: h.sum, stages: h.stages || [] })),
};
const out = path.resolve(here, "../ReadingLogCore/Sources/ReadingLogCore/Resources/content.json");
fs.writeFileSync(out, JSON.stringify(content, null, 1) + "\n");
console.log(`wrote ${path.relative(process.cwd(), out)}: ${content.quotes.length} quotes, ${content.extraCredit.length}×${content.extraCredit[0].length} extra credit, ${content.themes.length} themes, ${content.nextHabits.length} next habits`);
