// Smoke test for Wave 46: foreign-exchange gains/losses (realised + unrealised) and invoice emailing helpers.
const fs = require('fs');
const vm = require('vm');
const html = fs.readFileSync('index.html', 'utf8');
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
const calls = { inserts:[], updates:[], deletes:[] };
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
sandbox.window.matchMedia = ()=>({matches:false,addEventListener(){},addListener(){}});
sandbox.window.supabase = { createClient(){ return {
  auth:{ onAuthStateChange(){return {data:{subscription:{unsubscribe(){}}}};}, signOut(){return Promise.resolve();}, signInWithPassword(){return Promise.resolve({data:{},error:null});} },
  from(t){ return makeQuery(t); },
  storage:{ from(){ return { upload(){return Promise.resolve({error:null});}, createSignedUrl(){return Promise.resolve({data:{signedUrl:'x'},error:null});}, remove(){return Promise.resolve({});} }; } },
}; } };
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(src, sandbox, {filename:'index.html-inline.js'});
vm.runInContext(`
  this.state=state; this.computePL=computePL; this.computeBS=computeBS; this.computeLedgerTB=computeLedgerTB; this.renderPL=renderPL; this.renderBS=renderBS;
  this.priorPeriodRange=priorPeriodRange; this.shiftIsoYears=shiftIsoYears; this.buildClosingLines=buildClosingLines; this.renderYearEnd=renderYearEnd;
  this.closeFinancialYear=closeFinancialYear; this.reopenFinancialYear=reopenFinancialYear; this.financialYearsList=financialYearsList;
  this.computeBankRec=computeBankRec; this.renderBankRec=renderBankRec; this.computeVatRec=computeVatRec; this.renderVatRec=renderVatRec;
  this.splitApproval=splitApproval; this.rebuildPendingItems=rebuildPendingItems; this.canApproveItem=canApproveItem; this.renderApprovalsPanel=renderApprovalsPanel;
  this.approvePendingItem=approvePendingItem; this.rejectPendingItem=rejectPendingItem; this.makerCheckerOn=makerCheckerOn; this.refreshAll=refreshAll; this.computeCashFlow=computeCashFlow; this.renderCF=renderCF; this.computeBudgetVsActual=computeBudgetVsActual; this.vatFromLedger=vatFromLedger; this.buildLedger=buildLedger; this.monthlyPayrollActuals=monthlyPayrollActuals; this.renderEmp201Panel=renderEmp201Panel; this.sarsOwedPerLedger=sarsOwedPerLedger; this.computeLedgerVsBS=computeLedgerVsBS; this.renderDashboard=renderDashboard; this.tracksInventory=tracksInventory; this.renderVat=renderVat; this.renderAssets=renderAssets; this.invoiceBalance=invoiceBalance; this.computeARAging=computeARAging; this.computeAssetRegister=computeAssetRegister; this.vatControlBalance=vatControlBalance; this.addMonthsClipped=addMonthsClipped; this.computeTaxComputation=computeTaxComputation; this.renderTaxComputation=renderTaxComputation; this.renderAFS=renderAFS; this.postTaxProvision=postTaxProvision; this.removeTaxProvision=removeTaxProvision; this.companyFinancialYearBounds=companyFinancialYearBounds; this.expenseLineItems=expenseLineItems; this.renderCompanyTax=renderCompanyTax; this.renderYearEnd=renderYearEnd; this.computeProvisionalTax=computeProvisionalTax; this.taxProvisionJournal=taxProvisionJournal; this.renderVatPaymentsPanel=renderVatPaymentsPanel; this.invoiceWrittenOff=invoiceWrittenOff; this.openClientStatementView=openClientStatementView;
  this.renderManualJournals=renderManualJournals; this.billBalance=billBalance; this.computeAPAging=computeAPAging; this.computeFX=computeFX; this.renderFX=renderFX; this.fxPositionsAsOf=fxPositionsAsOf; this.fxRateOn=fxRateOn; this.paymentCleared=paymentCleared; this.settledForeign=settledForeign; this.invoiceEmailHtml=invoiceEmailHtml; this.fxRevaluationJournals=fxRevaluationJournals; this.fetchFxRate=fetchFxRate; this.CURRENCIES=CURRENCIES; this.supplierInvoiceModal=supplierInvoiceModal; this.recognizeSupplierInvoiceExpense=recognizeSupplierInvoiceExpense; this.ledgerLines=ledgerLines; this.todayIso=todayIso; this.totalsFor=totalsFor;
`, sandbox);
const S = sandbox.state;
const near = (a,b)=>Math.abs(a-b)<0.01;
function reset(){
  S.accounts=[{name:'Main', starting_balance:10000}]; S.entries=[]; S.invoices=[]; S.invoiceItems={}; S.invoicePayments=[]; S.supplierInvoices=[]; S.supplierInvoiceItems={};
  S.supplierInvoicePayments=[]; S.creditNotes=[]; S.creditNoteItems={}; S.supplierCreditNotes=[]; S.supplierCreditNoteItems={}; S.assets=[]; S.liabilities=[]; S.liabilityPayments=[];
  S.liabilityPaymentsAll=[]; S.payrollPayments=[]; S.vatPayments=[]; S.taxAdjustments=[]; S.provisionalTax=[]; S.invoiceWriteoffs=[]; S.clients=[]; S.employees=[]; S.emp201Submissions=[]; S.stockItems=[]; S.budgets=[]; S.manualJournals=[]; S.manualJournalLines={}; S.chartAccounts=[]; S.bankTransactions=[]; S.members=[]; S.fxRates=[]; S.suppliers=[{id:'s1',name:'Globex'}]; S.clients=[{id:'cl1',name:'Acme', email:'a@acme.co'}]; S.pendingItems=[];
  S._invoicePaymentsPending=[]; S._supplierPaymentsPending=[];
  S.company={id:'c1', name:'Test Co', vat_registered:true, financial_year_end_month:2, maker_checker:false, locked_through_date:null};
  S.membership={role:'owner', status:'active'}; S.user={id:'u1', email:'me@x.co'};
}





const bal = (key, to)=>{ const t = sandbox.ledgerLines().filter(l=>l.key===key && (!to || l.date<=to)); return t.reduce((s,l)=>s+l.debit-l.credit,0); };
function journalsBalance(){ return sandbox.buildLedger().every(j=>Math.abs(j.lines.reduce((s,l)=>s+l.debit-l.credit,0))<0.005); }
const D0 = '2026-03-10', D1 = '2026-03-20', D2 = '2026-03-31';
function usdInvoice(){
  S.invoices = [{id:'i1', invoice_number:'INV-1', client_id:'cl1', issue_date:D0, due_date:D1, status:'sent', approval_status:'approved', currency:'USD', exchange_rate:18}];
  S.invoiceItems = {i1:[{description:'Consulting', quantity:1, unit_price:1000, vat_applicable:false}]};
  S.entries.push({id:'e1', type:'revenue', amount:18000, entry_date:D0, description:'Invoice INV-1', vat_applicable:false, tags:['invoice'], source_invoice_id:'i1'});
}
function usdBill(){
  S.supplierInvoices = [{id:'b1', bill_number:'B-1', supplier_id:'s1', issue_date:D0, due_date:D1, approval_status:'approved', currency:'USD', exchange_rate:19, expense_category:'operating'}];
  S.supplierInvoiceItems = {b1:[{description:'Hosting', quantity:1, unit_price:500, vat_applicable:false}]};
  S.entries.push({id:'e2', type:'expense', amount:9500, entry_date:D0, description:'Bill B-1', vat_applicable:false, tags:['supplier_invoice'], expense_category:'operating', source_supplier_invoice_id:'b1'});
}

/* 1. realised gain on a customer payment */
reset(); usdInvoice();
S.invoicePayments = [{id:'p1', invoice_id:'i1', payment_date:D1, amount:18500, foreign_amount:1000}];
{
  const b = sandbox.invoiceBalance(S.invoices[0]);
  check('realised: invoice fully settled in foreign terms (balance 0)', near(b.balance, 0) && near(b.paid, 18000) && near(b.total, 18000));
  check('realised: bank receives the 18 500 actually banked', near(bal('BANK') - 10000, 18500));
  check('realised: receivable cleared at the booked rate (AR = 0)', near(bal('AR'), 0));
  check('realised: 500 FX gain credited', near(bal('FX'), -500));
  check('realised: ledger balances', journalsBalance());
  const pl = sandbox.computePL('1900-01-01', '9999-12-31');
  check('realised: gain lifts profit (18 000 revenue + 500 gain)', near(pl.netProfit, 18500) && near(pl.opex, -500));
}

/* 2. realised loss on a partial payment */
reset(); usdInvoice();
S.invoicePayments = [{id:'p1', invoice_id:'i1', payment_date:D1, amount:7000, foreign_amount:400}];
{
  const b = sandbox.invoiceBalance(S.invoices[0]);
  check('partial: balance is the unpaid 600 USD at 18 = 10 800', near(b.balance, 10800) && near(b.paid, 7200));
  check('partial: 200 FX loss debited', near(bal('FX'), 200));
  const pos = sandbox.fxPositionsAsOf(D2);
  check('partial: open foreign position 600 USD', pos.length===1 && near(pos[0].open, 600) && pos[0].kind==='AR');
  check('partial: ledger balances', journalsBalance());
}

/* 3. legacy / bank-matched payment without foreign_amount clears at face value */
reset(); usdInvoice();
S.invoicePayments = [{id:'p1', invoice_id:'i1', payment_date:D1, amount:18000}];
check('legacy payment: clears at face value, no FX', near(sandbox.invoiceBalance(S.invoices[0]).balance, 0) && near(bal('FX'), 0) && near(sandbox.fxPositionsAsOf(D2).length, 0));

/* 4. supplier bill in USD */
reset(); usdBill();
S.supplierInvoicePayments = [{id:'sp1', supplier_invoice_id:'b1', payment_date:D1, amount:9250, foreign_amount:500}];
{
  const b = sandbox.billBalance(S.supplierInvoices[0]);
  check('bill: total in ZAR 9 500, settled, balance 0', near(b.total, 9500) && near(b.paid, 9500) && near(b.balance, 0));
  check('bill: payable cleared (AP = 0)', near(bal('AP'), 0));
  check('bill: paid 9 250 from bank', near(10000 - bal('BANK'), 9250));
  check('bill: 250 FX gain credited', near(bal('FX'), -250));
  check('bill: ledger balances', journalsBalance());
  S.supplierInvoicePayments = [];
  check('bill: unpaid foreign bill appears in AP aging at ZAR value', near(sandbox.computeAPAging().rows.filter(r=>/B-1/.test(r.description)).reduce((s,r)=>s+r.amount,0), 9500));
}

/* 5. unrealised revaluation and its reversal */
reset(); usdInvoice(); usdBill();
S.fxRates = [{id:'r1', rate_date:D2, currency:'USD', rate:20}];
{
  // AR: 1000 USD, 18 -> 20 = +2 000. AP: 500 USD, 19 -> 20 = +500 payable (loss).
  check('unrealised: AR revalued up by 2 000 at the closing date', near(bal('AR', D2), 18000 + 2000));
  check('unrealised: AP revalued up by 500 at the closing date', near(bal('AP', D2), -(9500 + 500)));
  check('unrealised: net FX gain 1 500 at the closing date', near(bal('FX', D2), -1500));
  const next = '2026-04-01';
  check('unrealised: reversed the next day (AR back to 18 000, FX 0)', near(bal('AR', next), 18000) && near(bal('AP', next), -9500) && near(bal('FX', next), 0));
  check('unrealised: ledger balances', journalsBalance());
  const fx = sandbox.computeFX('2026-03-01', '2026-03-31');
  check('unrealised: report shows 1 500 unrealised, 0 realised', near(fx.unrealised, 1500) && near(fx.realised, 0) && fx.open.length===2);
  check('unrealised: open-balance gain/(loss) per document (+2 000 invoice, -500 bill)', near(fx.open.find(o=>o.kind==='AR').gain, 2000) && near(fx.open.find(o=>o.kind==='AP').gain, -500));
  S.fxRates = [{id:'r2', rate_date:D2, currency:'EUR', rate:21}];
  check('no rate for the currency held: no revaluation', near(bal('FX', D2), 0) && near(bal('AR', D2), 18000));
  // payment after the rate date settles against the ORIGINAL rate (reversal makes it consistent)
  S.fxRates = [{id:'r1', rate_date:D2, currency:'USD', rate:20}];
  S.invoicePayments = [{id:'p9', invoice_id:'i1', payment_date:'2026-04-10', amount:20100, foreign_amount:1000}];
  check('post-revaluation payment: AR clears to 0, realised gain 2 100 vs booked rate', near(bal('AR', '2026-04-30'), 0) && near(bal('FX', '2026-04-30'), -2100));
  check('post-revaluation payment: ledger balances', journalsBalance());
  // payment before the rate date means nothing is open to revalue for that invoice
  S.invoicePayments = [{id:'p9', invoice_id:'i1', payment_date:D1, amount:18000, foreign_amount:1000}];
  check('fully paid before the rate date: no AR revaluation', near(bal('AR', D2), 0) && near(bal('AP', D2), -(9500+500)));
}

/* 6. statement and rendering */
reset(); usdInvoice(); usdBill();
S.invoicePayments = [{id:'p1', invoice_id:'i1', payment_date:D1, amount:7000, foreign_amount:400}];
S.fxRates = [{id:'r1', rate_date:D2, currency:'USD', rate:20}];
{
  let ok = true; try{ sandbox.openClientStatementView('cl1', '', ''); }catch(e){ ok=false; console.log(e); }
  check('client statement renders with foreign payment', ok);
  const out = sandbox.renderFX('2026-03-01','2026-03-31');
  check('FX tab renders rates, open balances and postings', /Closing exchange rates/.test(out) && /INV-1/.test(out) && /B-1/.test(out) && /FX postings/.test(out));
  check('FX tab shows the saved rate', /20/.test(out));
  S.state = S; S.reportsTab = 'fx';
  let r = true; try{ sandbox.render(); }catch(e){ r=false; console.log(e); }
  check('reports page renders on the FX tab', r);
  check('currencies include the new ones', ['AUD','CAD','CHF','CNY','JPY'].every(c=>sandbox.CURRENCIES.includes(c)));
  const m = sandbox.supplierInvoiceModal();
  check('supplier bill form has currency + rate fields', /supplier-invoice-currency/.test(m) && /supplier-invoice-exchange-rate/.test(m));
  check('fxRateOn picks latest rate on or before date', sandbox.fxRateOn('USD','2026-04-01').rate===20 && sandbox.fxRateOn('USD','2026-03-01')===null);
}

/* 7. email body */
reset(); usdInvoice();
{
  const items = S.invoiceItems.i1;
  const h = sandbox.invoiceEmailHtml(S.invoices[0], items, S.clients[0], 'Hello <b>there</b>', {total:1000, subtotal:1000, vatTotal:0, zarTotal:18000, isForeign:true});
  check('email html includes invoice number, company, total in USD', /INV-1/.test(h) && /Test Co/.test(h) && /1[\s, ]*000[.,]00 USD/.test(h));
  check('email html escapes the message', !/<b>there/.test(h) && /&lt;b&gt;there/.test(h));
  check('email html shows ZAR booking note for foreign invoice', /booked at 18/.test(h));
}

console.log(failures ? `\n${failures} FAILED` : '\nALL OK');
process.exit(failures ? 1 : 0);
