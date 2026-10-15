// Runs the website's own script (index.html) inside Node with a do-nothing DOM, so its data
// tables and scoring functions can be read directly. `now` pins the clock the page sees.
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
export const INDEX = path.resolve(here, "../../index.html");

function stub(){
  const f = function(){ return stub(); };
  return new Proxy(f, {
    get(t, k){
      if(k === Symbol.toPrimitive) return () => "";
      if(k === "forEach") return () => {};
      if(k === "length") return 0;
      if(k === "then") return undefined;
      return stub();
    },
    set(){ return true; },
    apply(){ return stub(); },
    construct(){ return stub(); },
  });
}

export function loadWeb(nowISO){
  const src = fs.readFileSync(INDEX, "utf8").match(/<script>([\s\S]*)<\/script>/)[1];
  const RealDate = Date;
  const fixed = new RealDate(nowISO).getTime();
  class FakeDate extends RealDate {
    constructor(...a){ if(a.length === 0) super(fixed); else super(...a); }
    static now(){ return fixed; }
  }
  const store = {};
  const storage = { getItem: k => store[k] ?? null, setItem: (k, v) => { store[k] = String(v); }, removeItem: k => { delete store[k]; } };
  const doc = stub();
  const ctx = {
    console, Date: FakeDate, Math, JSON, Number, String, Object, Array, Boolean, parseInt, isFinite, encodeURIComponent,
    decodeURIComponent, escape, unescape, btoa, atob, setTimeout: () => 0, clearTimeout(){}, setInterval: () => 0, clearInterval(){},
    localStorage: storage, sessionStorage: storage, document: doc, navigator: {}, fetch: undefined,
  };
  ctx.window = ctx; ctx.addEventListener = () => {};
  vm.createContext(ctx);
  vm.runInContext(src, ctx);
  return ctx;
}
