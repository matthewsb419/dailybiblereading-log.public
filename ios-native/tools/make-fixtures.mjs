// Builds the parity fixtures: a made-up log (never real entries — this repo is public), then the
// website's own answers for it on several dates. The Swift tests must reproduce every value.
//   node ios-native/tools/make-fixtures.mjs [path/to/data.json]   (a real file stays local: pass --out)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadWeb } from "./load-web.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const outIdx = args.indexOf("--out");
const outPath = outIdx >= 0 ? args[outIdx + 1] : path.resolve(here, "../ReadingLogCore/Tests/ReadingLogCoreTests/Fixtures/fixtures.json");
const inPath = args.find((a, i) => !a.startsWith("--") && args[i - 1] !== "--out");

// ---------- a deterministic made-up log ----------
function rng(seed){ let s = seed >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }
function synthetic(){
  const r = rng(7), pick = a => a[Math.floor(r() * a.length)];
  const w = loadWeb("2026-10-20T09:00:00");
  const entries = {}, marks = {};
  let day = 1;
  const d = new Date(2026, 7, 30);
  for(let i = 0; i < 52; i++, d.setDate(d.getDate() + 1)){
    const key = w.keyOf(d);
    if(r() < 0.12) continue;                                   // a missed day
    const e = { day, date: key };
    const n = r() < 0.15 ? Math.floor(r() * 3) : 3;            // sometimes partial
    ["god", "stood", "today"].forEach((q, j) => { e[q] = j < n ? "Note " + day + "." + j : ""; });
    for(const t of w.TRACKERS){
      if(r() < 0.1) continue;
      if(t.id === "mg") e[t.id] = pick(["yes", "no", "off"]);
      else e[t.id] = r() < 0.75 ? t.good : (t.good === "yes" ? "no" : "yes");
    }
    if(r() < 0.8) e.st = Math.floor(3000 + r() * 12000);
    if(r() < 0.7) e.kg = Math.floor(r() * 4);
    if(r() < 0.5) e.gr = "yes";
    if(key >= "2026-09-06" && r() < 0.6){
      const ec = w.ecFor(key); e.ec = "Extra " + key; e.ecCh = ec.ch; e.ecQ = ec.qi;
    }
    e.savedAt = new Date(d.getTime() + 20 * 3600e3 + Math.floor(r() * 3600e3)).toISOString();
    entries[day] = e; day++;
  }
  // a read-ahead day written on the same date as the last one, and a stale leftover
  entries[day] = { day, date: "2026-10-19", god: "Ahead", stood: "", today: "", savedAt: "2026-10-19T22:00:00.000Z" }; day++;
  entries[day + 3] = { day: day + 3, date: "2026-10-02", p: "no", savedAt: "2026-10-02T10:00:00.000Z" };
  // calendar backfill marks, some newer and some older than the entry they shadow
  for(const [k, f, v, at] of [
    ["2026-09-03", "p", "yes", "2026-09-30T00:00:00.000Z"], ["2026-09-03", "m", "", "2026-09-30T00:00:00.000Z"],
    ["2026-09-14", "mg", "off", "2026-09-16T00:00:00.000Z"], ["2026-09-21", "g", "yes", "2026-09-22T00:00:00.000Z"],
    ["2026-09-25", "st", 9100, "2026-10-01T00:00:00.000Z"], ["2026-10-04", "kg", 3, "2026-10-05T00:00:00.000Z"],
    ["2026-10-08", "h", "no", "2026-01-01T00:00:00.000Z"], ["2026-09-28", "mg", "yes", "2026-09-29T00:00:00.000Z"],
  ]){ (marks[k] ||= {})[f] = v; marks[k][f + "At"] = at; }
  return {
    version: 1, entries, marks,
    goals: ["Love God", "Lead my family", "Finish strong at work", "Stay fit", "Give generously"],
    goalsSavedAt: "2026-09-01T00:00:00.000Z",
    myQuotes: [
      { id: "a1", t: "Keep going.", a: "Me", made: "2026-09-02T00:00:00.000Z", at: "2026-09-02T00:00:00.000Z" },
      { id: "b2", t: "Gone", a: "", made: "2026-09-03T00:00:00.000Z", at: "2026-09-04T00:00:00.000Z", del: true },
      { id: "c3", t: "Second line\nof a quote", a: "", made: "2026-09-05T00:00:00.000Z", at: "2026-09-05T00:00:00.000Z" },
    ],
  };
}

const base = inPath ? JSON.parse(fs.readFileSync(inPath, "utf8")) : synthetic();
const clone = x => JSON.parse(JSON.stringify(x));

function withState(nowISO, st){
  const w = loadWeb(nowISO);
  w.state = clone(st);
  ["entries", "goals", "marks", "myQuotes"].forEach(k => { if(!w.state[k]) w.state[k] = k === "entries" || k === "marks" ? {} : []; });
  return w;
}

function snapshot(nowISO){
  const w = withState(nowISO, base);
  const today = w.keyOf();
  const range = (from, n) => Array.from({ length: n }, (_, i) => w.shiftKey(from, i));
  const s = w.stepStats();
  const ks = w.kegStats();
  const defs = w.habitDefs(), yest = w.shiftKey(today, -1);
  const tracker = {};
  for(const t of w.TRACKERS){
    const map = w.pmMap(t.id), first = w.pmFirst(map);
    const nowKey = t.shift < 0 ? w.yKey() : today;
    tracker[t.id] = {
      map, first,
      week: first ? w.tWeek(map, first, nowKey, t.weekday) : null,
      months: first ? w.allMonths().map(m => ({ y: m.y, m: m.m, s: w.pmMonthStats(map, first, m.y, m.m, nowKey, t.weekday) })) : [],
    };
  }
  return {
    now: nowISO, today,
    currentDay: w.currentDay(), nextUnloggedDay: w.nextUnloggedDay(),
    dateMapDays: Object.fromEntries(Object.entries(w.dateMap()).map(([k, e]) => [k, e.day])),
    planDayMap: w.planDayMap(), firstDate: w.firstDate(),
    months: w.allMonths(), week: w.weekStats(),
    tracker,
    steps: {
      map: s.map, total: s.total, logged: s.logged, best: s.best, bestK: s.bestK, pace: s.pace, overPace: s.overPace,
      streak: s.streak, counted: s.counted, from: s.from, daysLeft: s.daysLeft, target: s.target, need: s.need, avg: s.avg,
      projected: s.projected, hitDate: s.hitDate, span: s.span, last: s.last, required: s.required, taken: s.taken,
      pct: s.pct, pass: s.pass, grade: s.grade, needText: w.stepNeedText(), needSeries: w.needSeries(s),
    },
    keg: {
      level: ks.prog.level, weeks: ks.prog.weeks, plan: ks.plan, next: ks.prog.next, today: ks.today, total: ks.total,
      days: ks.days, atGoal: ks.atGoal, anyDay: ks.anyDay, streak: ks.streak, last7: ks.last7, avg: ks.avg,
      wkGrade: ks.wkGrade, allGrade: ks.allGrade, steps: w.kegPlan(),
    },
    habits: { week: w.habitWindow(defs, w.shiftKey(yest, -6), yest), all: w.habitWindow(defs, "1900-01-01", yest) },
    goalIndex: Object.fromEntries(range("2026-09-01", 60).map(k => [k, w.goalIndex(k, (w.state.goals || []).length)])),
    quoteIndex: Object.fromEntries(range("2026-09-01", 200).map(k => [k, w.quoteIndex(k)])),
    quoteBankSize: w.quoteBank().length,
    extraCredit: Object.fromEntries(range("2026-09-01", 120).map(k => [k, w.ecFor(k)])),
    ecDays: w.ecDays(), ecMapDays: Object.keys(w.ecMap()).sort(),
    markdown: w.toMarkdown(),
  };
}

// edits: the same calls on the same state must leave the same JSON behind
function edits(){
  const out = [];
  const run = (name, nowISO, fn) => { const w = withState(nowISO, base); fn(w); out.push({ name, now: nowISO, state: w.state }); };
  run("mark p yes on a day with an entry", "2026-10-20T09:00:00", w => w.setMark("p", "2026-09-10", "yes"));
  run("clear j on a day with an entry", "2026-10-20T09:00:00", w => w.setMark("j", "2026-09-10", ""));
  run("mark h on a day with no entry", "2026-10-20T09:00:00", w => w.setMark("h", "2026-08-01", "yes"));
  run("steps backfill", "2026-10-20T09:00:00", w => w.setMark("st", "2026-09-30", 12345));
  run("keg add today", "2026-10-20T09:00:00", w => w.kegAdd(1));
  const remote = clone(base);
  remote.entries ||= {}; remote.marks ||= {}; remote.myQuotes ||= [];
  const k2 = Object.keys(remote.entries)[1] || "2";
  remote.entries[k2] = { ...(remote.entries[k2] || { day: Number(k2), date: "2026-09-01" }), god: "Edited elsewhere", savedAt: "2030-01-01T00:00:00.000Z" };
  remote.marks["2026-09-03"] ||= {};
  remote.entries["99"] = { day: 99, date: "2026-10-18", god: "x", stood: "y", today: "z", savedAt: "2026-10-18T10:00:00.000Z" };
  remote.marks["2026-09-03"].p = "no"; remote.marks["2026-09-03"].pAt = "2031-01-01T00:00:00.000Z";
  remote.goals = ["Only one"]; remote.goalsSavedAt = "2030-01-01T00:00:00.000Z";
  remote.myQuotes.push({ id: "z9", t: "From another phone", a: "", made: "2026-10-01T00:00:00.000Z", at: "2026-10-01T00:00:00.000Z" });
  run("merge remote", "2026-10-20T09:00:00", w => { w.__changed = w.mergeRemote(clone(remote)); });
  out[out.length - 1].changed = true;
  out[out.length - 1].remote = remote;
  return out;
}

// saving the Today card: the website's writeDraft() reads the page, so give it a fake page
function drafts(){
  const out = [];
  const nowISO = "2026-10-20T09:00:00";
  const probe = withState(nowISO, base);
  const keys = Object.keys(probe.state.entries);
  const staleKey = keys.find(k => probe.staleEntry(probe.state.entries[k]));
  const scenarios = [
    { name: "new current day", day: probe.currentDay(),
      answers: { god: "He keeps promises", stood: "Why the census?", today: "Trust him" },
      trackers: { p: "no", m: "yes", j: "yes", h: null }, steps: "12,345", goalRead: true, ec: { text: "Written", ch: 3, qi: 4 } },
    { name: "clear a past day", day: Number(keys[2]), answers: { god: "", stood: "", today: "" }, steps: "", goalRead: false },
    { name: "write on a stale day", day: Number(staleKey), answers: { god: "Now written", stood: "", today: "" }, trackers: { j: "no" } },
    { name: "past day, untouched trackers", day: Number(keys[4]), answers: { god: "Edited", stood: "x", today: "y" }, goalRead: false, ec: { text: "  ", ch: 1, qi: 0 } },
  ].filter(x => x.day);
  for(const sc of scenarios){
    const w = withState(nowISO, base);
    w.viewDay = sc.day;
    const node = v => ({ value: v, dataset: {} });
    const seg = v => ({ querySelector: () => (v ? { dataset: { v } } : null) });
    const doc = {
      querySelector(sel){
        let m;
        if((m = sel.match(/^textarea\[data-q="(\w+)"\]$/))) return m[1] in sc.answers ? node(sc.answers[m[1]]) : null;
        if((m = sel.match(/^\.seg\[data-t="(\w+)"\]$/))) return sc.trackers && m[1] in sc.trackers ? seg(sc.trackers[m[1]]) : null;
        if(sel === 'textarea[data-x="ec"]') return sc.ec ? { value: sc.ec.text, dataset: { ch: String(sc.ec.ch), qi: String(sc.ec.qi) } } : null;
        return null;
      },
      getElementById(id){
        if(id === "steps") return "steps" in sc ? node(sc.steps) : null;
        if(id === "goalRead") return "goalRead" in sc ? { dataset: { v: sc.goalRead ? "yes" : "" } } : null;
        return null;
      },
      querySelectorAll(){ return []; },
    };
    w.document = doc;
    w.writeDraft();
    out.push({ ...sc, now: nowISO, state: w.state });
  }
  return out;
}

const nows = ["2026-09-20T08:00:00", "2026-10-14T21:30:00", "2026-10-20T09:00:00", "2026-12-26T12:00:00", "2027-03-01T07:00:00"];
const w0 = loadWeb(nows[0]);
const fixtures = {
  timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  plan: w0.PLAN,
  state: base,
  snapshots: nows.map(snapshot),
  edits: edits(),
  drafts: drafts(),
};
fs.writeFileSync(outPath, JSON.stringify(fixtures));
console.log(`wrote ${outPath} (${(fs.statSync(outPath).size / 1024).toFixed(0)} KB, ${fixtures.snapshots.length} dates, ${fixtures.plan.length} plan days)`);
