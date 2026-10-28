// Smoke test for Wave 61: invoice stages, banking details on invoices, crediting an invoice.
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





vm.runInContext(`this.state=state;`, sandbox);
const S = sandbox.state;
const TODAY = sandbox.todayIso();
function reset(){
  S.accounts=[]; S.entries=[]; S.invoices=[]; S.invoiceItems={}; S.invoicePayments=[]; S.invoiceWriteoffs=[]; S.partyCredits=[]; S.creditAllocations=[];
  S.creditNotes=[]; S.creditNoteItems={}; S.paymentLinks=[]; S.fxRates=[]; S.reminderLog=[]; S.attachments=[]; S.stockItems=[];
  S.clients=[{id:'cl1', name:'Acme', email:'a@acme.co', address:'1 Long St\nCape Town'}];
  S.company={id:'c1', name:'Test Co', vat_registered:true, address:'12 Rivonia Rd\nSandton', contact_email:'co@test.co'};
  S.membership={role:'owner', status:'active'}; S.user={id:'u1', email:'me@x.co'};
}
const inv = (id, extra, amount) => { S.invoices.push(Object.assign({id, invoice_number:'INV-'+id, client_id:'cl1', issue_date:'2026-10-01', due_date:'2099-01-01', status:'draft', approval_status:'approved', submitted_at:'2026-10-01T00:00:00Z', currency:'ZAR', exchange_rate:1}, extra||{})); S.invoiceItems[id] = [{description:'Work', quantity:1, unit_price: amount||1000, vat_applicable:true}]; return S.invoices[S.invoices.length-1]; };
(async ()=>{
  reset();
  const d = inv('d', {approval_status:'pending', submitted_at:null});
  const w = inv('w', {approval_status:'pending'});
  const a = inv('a');
  const s1 = inv('s', {status:'sent'});
  const e = inv('e', {emailed_at:'2026-10-02T00:00:00Z'});
  const p = inv('p'); S.invoicePayments.push({invoice_id:'p', amount:1000, approval_status:'approved'});
  const r = inv('r', {approval_status:'rejected'});
  const st = id => sandbox.invoiceStage(S.invoices.find(i=>i.id===id));
  check('stages: draft, awaiting approval, approved, sent (marked or emailed), paid, rejected', st('d')==='draft' && st('w')==='awaiting' && st('a')==='approved' && st('s')==='sent' && st('e')==='sent' && st('p')==='paid' && st('r')==='rejected');
  check('isDraftInvoice only for unsubmitted, unapproved invoices', sandbox.isDraftInvoice(d) && !sandbox.isDraftInvoice(w) && !sandbox.isDraftInvoice(a));
  let html = sandbox.renderInvoices();
  check('invoice page has stage tabs with counts', /data-invoice-tab="draft"[^>]*>Drafts <span class="tab-count">1<\/span>/.test(html) && /Awaiting approval <span class="tab-count">1/.test(html) && /Sent <span class="tab-count">2/.test(html) && /Paid <span class="tab-count">1/.test(html) && /data-invoice-tab="rejected"/.test(html));
  S.invoiceTab = 'draft';
  html = sandbox.renderInvoices();
  check('Drafts tab lists only drafts', /INV-d/.test(html) && !/INV-a</.test(html) && !/INV-p</.test(html));
  S.invoiceTab = 'paid';
  check('Paid tab lists paid invoices', /INV-p/.test(sandbox.renderInvoices()) && !/INV-s</.test(sandbox.renderInvoices()));
  S.invoiceTab = null;
  check('drafts are not counted as waiting for approval', /Pending approval \(1\)/.test(sandbox.renderInvoices()));
  // credit notes against the invoice
  S.creditNotes = [{id:'cn1', invoice_id:'s', currency:'ZAR', exchange_rate:1, approval_status:'approved', status:'issued'}, {id:'cn2', invoice_id:'s', currency:'ZAR', exchange_rate:1, approval_status:'approved', status:'draft'}];
  S.creditNoteItems = {cn1:[{quantity:1, unit_price:400, vat_applicable:true}], cn2:[{quantity:1, unit_price:100, vat_applicable:true}]};
  let b = sandbox.invoiceBalance(s1);
  check('an issued credit note reduces the invoice balance; a draft one does not', b.credited === 400 && b.balance === 600);
  S.creditNoteItems.cn1[0].unit_price = 1000;
  check('fully credited invoice moves to Paid and shows "Credited"', sandbox.invoiceStage(s1) === 'paid' && /Credited/.test(sandbox.invoiceStagePill(s1)));
  // foreign invoice credited in its own currency
  const f = inv('f', {status:'sent', currency:'USD', exchange_rate:18});
  S.creditNotes.push({id:'cn3', invoice_id:'f', currency:'USD', exchange_rate:18, approval_status:'approved', status:'issued'});
  S.creditNoteItems.cn3 = [{quantity:1, unit_price:250, vat_applicable:false}];
  check('foreign invoice: open foreign balance net of the credit note', Math.abs(sandbox.foreignOpenFor('invoice', f) - 750) < 0.01 && Math.abs(sandbox.invoiceBalance(f).balance - 13500) < 0.01);
  // banking details
  reset();
  S.accounts = [{id:'b1', name:'Main', type:'bank', bank_name:'FNB', account_number:'62001234567', branch_code:'250655', show_on_invoices:true}, {id:'b2', name:'Savings', type:'savings', bank_name:'Nedbank', account_number:'1122334455', branch_code:'198765'}, {id:'b3', name:'Cash', type:'bank'}];
  const x = inv('x');
  check('invoice shows the default account when none is chosen', sandbox.invoiceBankAccount(x).id === 'b1');
  x.bank_account_id = 'b2';
  check('a chosen account wins', sandbox.invoiceBankAccount(x).id === 'b2');
  x.hide_bank_details = true;
  check('banking details can be switched off per invoice', sandbox.invoiceBankAccount(x) === null);
  x.hide_bank_details = false; x.bank_account_id = null; S.accounts[0].show_on_invoices = false;
  check('no default and none chosen: nothing shown', sandbox.invoiceBankAccount(x) === null);
  const lines = sandbox.bankDetailsLines(S.accounts[1], 'INV-x');
  check('banking lines: bank, holder (company name by default), number, branch, type, reference', JSON.stringify(lines.map(l=>l[0])) === JSON.stringify(['Bank','Account holder','Account number','Branch code','Account type','Payment reference']) && lines[1][1] === 'Test Co' && lines[5][1] === 'INV-x');
  x.bank_account_id = 'b2';
  const email = sandbox.invoiceEmailHtml(x, S.invoiceItems.x, S.clients[0], 'Hi', {total:1000, subtotal:869.57, vatTotal:130.43, zarTotal:1000, isForeign:false});
  check('invoice email carries banking details and the client address', /Banking details for EFT payments/.test(email) && /1122334455/.test(email) && /198765/.test(email) && /1 Long St/.test(email));
  const opts = sandbox.bankAccountOptions('b2', false);
  check('bank picker: default, accounts with numbers (masked), and "don\'t show"', /Default \(none set yet\)/.test(opts) && /value="b2" selected/.test(opts) && /••••4455/.test(opts) && !/value="b3"/.test(opts) && /__none/.test(opts));
  if(failures){ console.log(`\n${failures} CHECK(S) FAILED`); process.exit(1); }
  console.log('\nALL OK');
})();
