// Smoke test for Wave 60: report export helpers (number parsing for Excel, PDF-safe text).
const fs = require('fs');
const vm = require('vm');
const html = fs.readFileSync('app.html', 'utf8');
const src = html.match(/<script>([\s\S]*)<\/script>\s*<\/body>/)[1];
let failures = 0;
function check(label, cond){ console.log(`${cond?'OK  ':'FAIL'} ${label}`); if(!cond) failures++; }

function fakeEl(id){
  const el = { id, classList:{add(){},remove(){},toggle(){},contains(){return false;}}, style:{}, dataset:{}, children:[], _listeners:{},
    addEventListener(t,fn){ (el._listeners[t]=el._listeners[t]||[]).push(fn); }, querySelectorAll(){return [];}, querySelector(){return null;},
    appendChild(){}, insertAdjacentHTML(){}, getContext(){return {};}, value:'', checked:false, textContent:'', innerHTML:'', files:[] };
  return el;
}
const cache = {};
const getEl = id => cache[id] || (cache[id] = fakeEl(id));
const calls = { inserts:[], updates:[], deletes:[], invokes:[], uploads:[], removes:[], opened:[] };
let invokeResult = {data:{ok:true}, error:null};
const DATA = {};
let nextId = 1;
function makeQuery(table){
  const q = {
    _op:null, _payload:null, _filters:{},
    select(){ return this; }, eq(c,v){ this._filters[c]=v; return this; }, order(){ return this; }, in(){ return this; }, limit(){ return this; },
    insert(p){ this._op='insert'; this._payload=p; calls.inserts.push({table, payload:p}); return this; },
    update(p){ this._op='update'; this._payload=p; return this; },
    delete(){ this._op='delete'; return this; },
    single(){ return Promise.resolve({data: Object.assign({id: table+(nextId++)}, this._payload||{}), error:null}); },
    then(resolve){
      if(this._op==='update') calls.updates.push({table, payload:this._payload, filters:Object.assign({},this._filters)});
      if(this._op==='delete') calls.deletes.push({table, filters:Object.assign({},this._filters)});
      resolve({data: this._op ? [] : (DATA[table]||[]), error:null});
    },
  };
  return q;
}
const sandbox = {
  console, window:{}, document:{ getElementById:getEl, querySelectorAll(){return [];}, querySelector(){return null;}, addEventListener(){}, createElement(){return fakeEl('a');},
    documentElement:{setAttribute(){},removeAttribute(){},getAttribute(){return null;}}, body:{appendChild(){},removeChild(){}} },
  localStorage:{getItem(){return null;},setItem(){},removeItem(){}}, navigator:{userAgent:'node'}, Chart:function(){return {destroy(){}};},
  fetch:()=>Promise.resolve({json:()=>Promise.resolve({})}), alert(){}, confirm(){return true;}, prompt(){return 'because';}, setTimeout, clearTimeout,
  Blob:function(){}, URL:{createObjectURL(){return 'blob:x';},revokeObjectURL(){}},
};
sandbox.window.open = (u)=>{ calls.opened.push(u); return {}; };
sandbox.window.matchMedia = ()=>({matches:false,addEventListener(){},addListener(){}});
sandbox.window.supabase = { createClient(){ return {
  auth:{ onAuthStateChange(){return {data:{subscription:{unsubscribe(){}}}};}, signOut(){return Promise.resolve();}, signInWithPassword(){return Promise.resolve({data:{},error:null});} },
  from(t){ return makeQuery(t); },
  functions:{ invoke(name, opts){ calls.invokes.push({name, body:opts.body}); return Promise.resolve(typeof invokeResult==='function' ? invokeResult(opts.body) : invokeResult); } },
  storage:{ from(){ return { upload(p, f, o){ calls.uploads.push({path:p, opts:o}); return Promise.resolve({error:null});}, createSignedUrl(){return Promise.resolve({data:{signedUrl:'x'},error:null});}, remove(p){ calls.removes.push(p); return Promise.resolve({});}, download(){ return Promise.resolve({data:{text:()=>Promise.resolve('<p>x</p>')}, error:null}); } }; } },
}; } };
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(src, sandbox, {filename:'app.html-inline.js'});






(async ()=>{
  const n = t => { const r = sandbox.exportNumber(t); return r ? [Math.round(r.n*10000)/10000, r.kind].join(':') : 'text'; };
  check('money in either locale style becomes a number', n('R1,234.56') === '1234.56:money' && n('R-4 369,57') === '-4369.57:money' && n('R 1 234 567,50') === '1234567.5:money');
  check('brackets and minus signs mean negative', n('(R250.00)') === '-250:money' && n('-R12.00') === '-12:money' && n('(1,200)') === '-1200:num');
  check('percentages become fractions', n('12.5%') === '0.125:pct' && n('100.0%') === '1:pct');
  check('dates, years, dashes and words stay text', ['2026-10-01', '2026', '—', 'Revenue', 'INV-1041', 'Sep 26'].every(t => n(t) === 'text'));
  check('grouped whole numbers are numbers', n('1,200') === '1200:num' && n('3') === '3:num');
  check('PDF text swaps characters the PDF fonts cannot draw', sandbox.pdfText('R1 234 → done ✓ ≈ 5') === 'R1 234 -> done OK ~ 5' && sandbox.pdfText('Café — “quote”') === 'Café — “quote”');
  check('export buttons carry their scope', /data-export="pdf" data-export-scope="report"/.test(sandbox.exportButtonsHtml('report')) && /data-export="xlsx"/.test(sandbox.exportButtonsHtml('report')));
  if(failures){ console.log(`\n${failures} CHECK(S) FAILED`); process.exit(1); }
  console.log('\nALL OK');
})();
