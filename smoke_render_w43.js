// Smoke test for Wave 61 (part 2): client/supplier terms and groups, invoice payment terms, quotes flow.
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
  S.creditNotes=[]; S.creditNoteItems={}; S.paymentLinks=[]; S.fxRates=[]; S.reminderLog=[]; S.attachments=[]; S.stockItems=[]; S.quotes=[]; S.quoteItems={};
  S.clients=[{id:'cl1', name:'Acme', email:'a@acme.co', account_ref:'CUST-1', client_group:'Retail', payment_method:'debit_order', payment_terms_days:7, contact_person:'Thandi'},
             {id:'cl2', name:'Bravo', email:'b@b.co', client_group:'Wholesale', payment_method:'eft', payment_terms_days:30},
             {id:'cl3', name:'Charlie'}];
  S.suppliers=[{id:'sp1', name:'Paper Co', registration_number:'2019/1/07', vat_number:'4123', payment_method:'debit_order', payment_terms_days:0}];
  S.company={id:'c1', name:'Test Co', vat_registered:true, address:'12 Rivonia Rd', contact_email:'co@test.co'};
  S.membership={role:'owner', status:'active'}; S.user={id:'u1', email:'me@x.co'};
  calls.inserts.length = 0; calls.updates.length = 0;
}
(async ()=>{
  reset();
  // helpers
  check('addDaysIso adds calendar days across a month end', sandbox.addDaysIso('2026-10-28', 7) === '2026-11-04' && sandbox.addDaysIso('2026-12-31', 1) === '2027-01-01');
  check('termsDays accepts 0-365 only', sandbox.termsDays('30') === 30 && sandbox.termsDays('0') === 0 && sandbox.termsDays('abc') === null && sandbox.termsDays('400') === null);
  check('terms label: method and days', sandbox.partyTermsLabel(S.clients[0]) === 'Debit order, 7 days' && sandbox.partyTermsLabel(S.suppliers[0]) === 'Debit order, on receipt' && sandbox.partyTermsLabel(S.clients[2]) === '—');
  check('long and short dates', sandbox.fmtLongDate('2026-10-29') === '29 October 2026' && sandbox.fmtShortDate('2026-10-01') === '1 Oct 2026');
  const dTxt = sandbox.defaultPaymentTermsText('debit_order', '2026-10-29', 'INV-1');
  check('debit order wording names the collection date', /debit order on 29 October 2026/.test(dTxt));
  check('EFT wording gives the due date and the reference', /EFT by 29 October 2026/.test(sandbox.defaultPaymentTermsText('eft', '2026-10-29', 'INV-7')) && /INV-7 as your payment reference/.test(sandbox.defaultPaymentTermsText('eft', '2026-10-29', 'INV-7')));
  check('no method and no due date: no wording', sandbox.defaultPaymentTermsText('', '', 'INV-1') === '');
  check('billing period: month, quarter, week, year', sandbox.billingPeriodFor('2026-10-15', 'monthly') === '1 Oct 2026 – 31 Oct 2026' && sandbox.billingPeriodFor('2026-11-02', 'quarterly') === '1 Oct 2026 – 31 Dec 2026' && sandbox.billingPeriodFor('2026-10-15', 'weekly') === '15 Oct 2026 – 21 Oct 2026' && sandbox.billingPeriodFor('2026-03-10', 'annually') === '1 Mar 2026 – 28 Feb 2027');
  // clients page: grouped, ref and terms columns, edit buttons, filter
  let html = sandbox.renderClients();
  check('clients grouped under their group headings, ungrouped last', html.indexOf('>Retail') > -1 && html.indexOf('>Retail') < html.indexOf('>Wholesale') && html.indexOf('>Wholesale') < html.indexOf('No group'));
  check('client rows show the customer ref, contact and terms, with an Edit button', /CUST-1/.test(html) && /Thandi/.test(html) && /Debit order, 7 days/.test(html) && /data-edit-client="cl1"/.test(html));
  check('client form has reference, group, VAT, payment method and terms', /id="client-ref"/.test(html) && /id="client-group"/.test(html) && /id="client-vat"/.test(html) && /id="client-paymethod"/.test(html) && /id="client-terms"/.test(html) && /<option value="Retail">/.test(html));
  S.clientGroupFilter = 'Wholesale';
  html = sandbox.renderClients();
  check('group filter narrows the list', /Bravo/.test(html) && !/>Acme</.test(html));
  S.clientGroupFilter = '';
  sandbox.fillPartyForm('client', S.clients[0]);
  getEl('client-terms').value = '14'; getEl('client-group').value = ' VIP ';
  const o = sandbox.readPartyForm('client');
  check('client form round-trips the new fields', o.account_ref === 'CUST-1' && o.client_group === 'VIP' && o.payment_method === 'debit_order' && o.payment_terms_days === 14 && o.contact_person === 'Thandi');
  sandbox.fillPartyForm('supplier', S.suppliers[0]);
  const so = sandbox.readPartyForm('supplier');
  check('supplier form carries the registration number, VAT number and terms', so.registration_number === '2019/1/07' && so.vat_number === '4123' && so.payment_terms_days === 0 && so.payment_method === 'debit_order' && !('account_ref' in so));
  const sup = sandbox.renderSupplierInvoices();
  check('supplier list shows reg no, VAT and terms with Edit', /2019\/1\/07/.test(sup) && /VAT 4123/.test(sup) && /Debit order, on receipt/.test(sup) && /data-edit-supplier="sp1"/.test(sup) && /id="supplier-reg"/.test(sup));
  // bill due date follows supplier terms
  getEl('supplier-invoice-supplier').value = 'sp1'; getEl('supplier-invoice-issue-date').value = '2026-10-10'; getEl('supplier-invoice-due-date').value = ''; getEl('supplier-invoice-due-date').dataset = {};
  S.suppliers[0].payment_terms_days = 30;
  sandbox.billDueFromTerms(false);
  check('a bill\'s due date comes from the supplier\'s credit terms', getEl('supplier-invoice-due-date').value === '2026-11-09');
  getEl('supplier-invoice-due-date').value = '2026-12-01'; getEl('supplier-invoice-due-date').dataset.auto = '';
  sandbox.billDueFromTerms(false);
  check('a due date typed by hand is kept', getEl('supplier-invoice-due-date').value === '2026-12-01');
  // invoice form defaults from the client
  getEl('invoice-client').value = 'cl1'; getEl('invoice-issue-date').value = '2026-10-22'; getEl('invoice-number').value = 'INV-9';
  ['invoice-due-date','invoice-customer-ref','invoice-payment-terms'].forEach(id=>{ getEl(id).value = ''; getEl(id).dataset = {auto:'1'}; });
  getEl('invoice-payment-method').value = '';
  sandbox.applyInvoiceClientDefaults(true);
  check('choosing a client fills ref, method, due date (terms) and the payment terms wording', getEl('invoice-customer-ref').value === 'CUST-1' && getEl('invoice-payment-method').value === 'debit_order' && getEl('invoice-due-date').value === '2026-10-29' && /debit order on 29 October 2026/.test(getEl('invoice-payment-terms').value));
  getEl('invoice-payment-terms').value = 'My own words'; getEl('invoice-payment-terms').dataset.auto = '';
  getEl('invoice-client').value = 'cl2';
  sandbox.applyInvoiceClientDefaults(false);
  check('edited payment terms are not overwritten when the client changes', getEl('invoice-payment-terms').value === 'My own words' && getEl('invoice-due-date').value === '2026-11-21');
  getEl('invoice-billing-period').value = 'Oct 2026';
  const xf = sandbox.invoiceExtraFields();
  check('invoice saves ref (following the new client), period, method and terms', xf.customer_ref === null && xf.billing_period === 'Oct 2026' && xf.payment_terms === 'My own words');
  // invoices list: group filter and ref
  S.invoices = [{id:'i1', invoice_number:'INV-1', client_id:'cl1', issue_date:'2026-10-01', status:'draft', approval_status:'approved', submitted_at:'x', currency:'ZAR', exchange_rate:1, customer_ref:'PO-77'},
                {id:'i2', invoice_number:'INV-2', client_id:'cl2', issue_date:'2026-10-01', status:'draft', approval_status:'approved', submitted_at:'x', currency:'ZAR', exchange_rate:1}];
  S.invoiceItems = {i1:[{description:'A', details:'Period: Oct', quantity:1, unit_price:100, vat_applicable:true}], i2:[]};
  S.invoiceGroupFilter = 'Retail';
  html = sandbox.renderInvoices();
  check('invoice list filters by client group and shows the customer ref', /INV-1/.test(html) && !/INV-2</.test(html) && /Ref PO-77/.test(html) && /id="invoice-group-filter"/.test(html));
  S.invoiceGroupFilter = '';
  const em = sandbox.invoiceEmailHtml(Object.assign({}, S.invoices[0], {payment_method:'debit_order', payment_terms:'Collected on the 1st.', billing_period:'Oct 2026', due_date:'2026-10-29'}), S.invoiceItems.i1, S.clients[0], 'Hi', {total:100, subtotal:86.96, vatTotal:13.04, zarTotal:100});
  check('invoice email shows line details, period, customer ref and payment terms', /Period: Oct/.test(em) && /Period Oct 2026/.test(em) && /Your ref PO-77/.test(em) && /Collected on the 1st\./.test(em));
  // recurring copy rolls the billing period and wording, and is submitted
  reset();
  S.invoices = [{id:'t1', invoice_number:'INV-2026-001', client_id:'cl1', issue_date:'2026-09-01', due_date:'2026-09-08', status:'sent', approval_status:'approved', submitted_at:'x', currency:'ZAR', exchange_rate:1,
    is_recurring:true, recurrence_frequency:'monthly', recurrence_next_date:'2026-10-01', payment_method:'debit_order', customer_ref:'CUST-1',
    billing_period: sandbox.billingPeriodFor('2026-09-01', 'monthly'), payment_terms: sandbox.defaultPaymentTermsText('debit_order', '2026-09-08', 'INV-2026-001')}];
  DATA.cc_invoice_items = [{description:'Subscription', details:'Monthly', quantity:1, unit_price:450, vat_applicable:true, account_key:null}];
  await sandbox.generateDueRecurringInvoices();
  const made = calls.inserts.find(c=>c.table==='cc_invoices');
  check('recurring copy: submitted, same gap to due date, period and wording rolled forward', made && made.payload.submitted_at && made.payload.due_date === '2026-10-08' && made.payload.billing_period === '1 Oct 2026 – 31 Oct 2026' && /8 October 2026/.test(made.payload.payment_terms) && made.payload.customer_ref === 'CUST-1');
  const madeItems = calls.inserts.find(c=>c.table==='cc_invoice_items');
  check('recurring copy keeps line details', madeItems && madeItems.payload[0].details === 'Monthly');
  DATA.cc_invoice_items = [];
  // quotes
  reset();
  const yest = sandbox.addDaysIso(TODAY, -1), next = sandbox.addDaysIso(TODAY, 10);
  S.quotes = [{id:'q1', quote_number:'QUO-1', client_id:'cl1', issue_date:TODAY, expiry_date:next, status:'draft'},
              {id:'q2', quote_number:'QUO-2', client_id:'cl1', issue_date:TODAY, expiry_date:next, status:'sent'},
              {id:'q3', quote_number:'QUO-3', client_id:'cl1', issue_date:TODAY, expiry_date:yest, status:'sent'},
              {id:'q4', quote_number:'QUO-4', client_id:'cl1', issue_date:TODAY, status:'converted', converted_invoice_id:'iX'},
              {id:'q5', quote_number:'QUO-5', client_id:'cl1', issue_date:TODAY, status:'declined', decline_reason:'Too dear'}];
  const qs = id => sandbox.quoteStage(S.quotes.find(q=>q.id===id));
  check('quote stages: draft, sent, expired (past valid-until), accepted (incl. old "converted"), declined', qs('q1')==='draft' && qs('q2')==='sent' && qs('q3')==='expired' && qs('q4')==='accepted' && qs('q5')==='declined');
  html = sandbox.renderQuotes();
  check('quotes page has stage tabs with counts', /data-quote-tab="draft"[^>]*>Drafts <span class="tab-count">1/.test(html) && /Accepted <span class="tab-count">1/.test(html) && /Declined <span class="tab-count">1/.test(html) && /Expired <span class="tab-count">1/.test(html));
  check('an accepted quote cannot be deleted; a declined one stays listed', !/data-del-quote="q4"/.test(html) && /QUO-5/.test(html));
  S.quoteTab = 'declined';
  check('Declined tab lists only declined quotes', /QUO-5/.test(sandbox.renderQuotes()) && !/QUO-1</.test(sandbox.renderQuotes()));
  S.quoteTab = null;
  calls.inserts.length = 0;
  const qinv = await sandbox.createInvoiceFromQuote(Object.assign({}, S.quotes[1], {customer_ref:'PO-9', notes:'Thanks'}), [{description:'Design', details:'5 pages', quantity:1, unit_price:1000, vat_applicable:true, account_key:'bogus'}]);
  const qi = calls.inserts.find(c=>c.table==='cc_invoices').payload;
  const qii = calls.inserts.find(c=>c.table==='cc_invoice_items').payload;
  check('accepting a quote creates a submitted invoice with the client\'s terms and the quote\'s ref', qinv && qi.submitted_at && qi.approval_status === 'approved' && qi.due_date === sandbox.addDaysIso(TODAY, 7) && qi.customer_ref === 'PO-9' && qi.payment_method === 'debit_order' && /debit order/.test(qi.payment_terms));
  check('the invoice lines carry the quote details (an unknown sales account falls back to Sales)', qii[0].details === '5 pages' && qii[0].account_key === 'REV' && qii[0].unit_price === 1000);
  const qe = sandbox.quoteEmailHtml(S.quotes[1], [{description:'Design', details:'5 pages', quantity:1, unit_price:1000, vat_applicable:true}], S.clients[0], 'Hello');
  check('quote email: number, details, total and how to accept', /Quote QUO-2/.test(qe) && /5 pages/.test(qe) && /Quote total/.test(qe) && /accept this quote/.test(qe));
  if(failures){ console.log(`\n${failures} CHECK(S) FAILED`); process.exit(1); }
  console.log('\nALL OK');
})();
