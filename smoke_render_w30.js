// Smoke test for Wave 47: foreign-currency bank matching and the ledger health check.
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
  this.renderManualJournals=renderManualJournals; this.matchBankTransaction=matchBankTransaction; this.suggestedMatchesFor=suggestedMatchesFor; this.computeHealthCheck=computeHealthCheck; this.renderHealthCheck=renderHealthCheck; this.renderHealthBanner=renderHealthBanner; this.foreignOpenFor=foreignOpenFor; this.guessForeignSettled=guessForeignSettled; this.outstandingInvoices=outstandingInvoices; this.taxProvisionJournal=taxProvisionJournal; this.billBalance=billBalance; this.computeAPAging=computeAPAging; this.computeFX=computeFX; this.renderFX=renderFX; this.fxPositionsAsOf=fxPositionsAsOf; this.fxRateOn=fxRateOn; this.paymentCleared=paymentCleared; this.settledForeign=settledForeign; this.invoiceEmailHtml=invoiceEmailHtml; this.fxRevaluationJournals=fxRevaluationJournals; this.fetchFxRate=fetchFxRate; this.CURRENCIES=CURRENCIES; this.supplierInvoiceModal=supplierInvoiceModal; this.recognizeSupplierInvoiceExpense=recognizeSupplierInvoiceExpense; this.ledgerLines=ledgerLines; this.todayIso=todayIso; this.totalsFor=totalsFor;
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






const TODAY = sandbox.todayIso();
const days = n => { const d = new Date(TODAY+'T00:00:00Z'); d.setUTCDate(d.getUTCDate()+n); return d.toISOString().slice(0,10); };
function usdInvoiceAt(date){
  S.invoices = [{id:'i1', invoice_number:'INV-1', client_id:'cl1', issue_date:date, due_date:date, status:'sent', approval_status:'approved', currency:'USD', exchange_rate:18}];
  S.invoiceItems = {i1:[{description:'Consulting', quantity:1, unit_price:1000, vat_applicable:false}]};
  S.entries.push({id:'e1', type:'revenue', amount:18000, entry_date:date, description:'Invoice INV-1', vat_applicable:false, tags:['invoice'], source_invoice_id:'i1'});
}
function usdBillAt(date){
  S.supplierInvoices = [{id:'b1', bill_number:'B-1', supplier_id:'s1', issue_date:date, due_date:date, approval_status:'approved', currency:'USD', exchange_rate:19, expense_category:'operating'}];
  S.supplierInvoiceItems = {b1:[{description:'Hosting', quantity:500, unit_price:1, vat_applicable:false}]};
  S.entries.push({id:'e2', type:'expense', amount:9500, entry_date:date, description:'Bill B-1', vat_applicable:false, tags:['supplier_invoice'], expense_category:'operating', source_supplier_invoice_id:'b1'});
}
const paymentInserts = t => calls.inserts.filter(c=>c.table===t);

/* 1. suggestions for foreign documents */
reset(); const dI = days(-3); usdInvoiceAt(dI);
S.bankTransactions = [{id:'t1', tx_date:days(-1), description:'ACME USD', amount:18500, status:'unmatched'}, {id:'t2', tx_date:days(-1), description:'big', amount:30000, status:'unmatched'}];
check('foreign invoice suggested for a Rand amount near its balance', sandbox.suggestedMatchesFor(S.bankTransactions[0]).some(m=>m.type==='invoice' && /USD/.test(m.description)));
check('foreign invoice not suggested when the Rand amount is far off', !sandbox.suggestedMatchesFor(S.bankTransactions[1]).some(m=>m.type==='invoice'));
check('open foreign balance is 1 000 USD', near(sandbox.foreignOpenFor('invoice', S.invoices[0]), 1000));
check('guess: full settle when the Rand value is close to the open balance', near(sandbox.guessForeignSettled(S.invoices[0], 1000, 18500, TODAY), 1000));
check('guess: partial settle converts at the booked rate', near(sandbox.guessForeignSettled(S.invoices[0], 1000, 7200, TODAY), 400));

/* 2. matching records the foreign amount (and asks first) */
(async ()=>{
  calls.inserts.length = 0;
  sandbox.prompt = ()=>'1000';
  await sandbox.matchBankTransaction('t1', 'invoice', 'i1');
  const p = paymentInserts('cc_invoice_payments')[0];
  check('matching a foreign invoice books a payment with the foreign amount', !!p && near(p.payload.amount, 18500) && near(p.payload.foreign_amount, 1000));

  reset(); usdInvoiceAt(dI); S.bankTransactions = [{id:'t1', tx_date:days(-1), description:'ACME', amount:18500, status:'unmatched'}];
  calls.inserts.length = 0; sandbox.prompt = ()=>null;
  await sandbox.matchBankTransaction('t1', 'invoice', 'i1');
  check('cancelling the foreign-amount prompt books nothing', paymentInserts('cc_invoice_payments').length===0);

  reset(); usdInvoiceAt(dI); S.bankTransactions = [{id:'t1', tx_date:days(-1), description:'ACME', amount:18500, status:'unmatched'}];
  calls.inserts.length = 0; sandbox.prompt = ()=>'abc';
  await sandbox.matchBankTransaction('t1', 'invoice', 'i1');
  check('invalid foreign amount is refused', paymentInserts('cc_invoice_payments').length===0);

  reset(); usdBillAt(dI); S.bankTransactions = [{id:'t3', tx_date:days(-1), description:'Globex', amount:-9250, status:'unmatched'}];
  calls.inserts.length = 0; sandbox.prompt = ()=>'500';
  await sandbox.matchBankTransaction('t3', 'supplier_invoice', 'b1');
  const q = paymentInserts('cc_supplier_invoice_payments')[0];
  check('matching a foreign bill books a payment with the foreign amount', !!q && near(q.payload.amount, 9250) && near(q.payload.foreign_amount, 500));

  // rand-only invoices never prompt
  reset(); S.invoices = [{id:'z1', invoice_number:'INV-Z', client_id:'cl1', issue_date:dI, due_date:dI, status:'sent', approval_status:'approved', currency:'ZAR', exchange_rate:1}];
  S.invoiceItems = {z1:[{description:'x', quantity:1, unit_price:500, vat_applicable:false}]};
  S.bankTransactions = [{id:'t9', tx_date:days(-1), description:'pay', amount:500, status:'unmatched'}];
  calls.inserts.length = 0; let asked = false; sandbox.prompt = ()=>{ asked = true; return '1'; };
  await sandbox.matchBankTransaction('t9', 'invoice', 'z1');
  const z = paymentInserts('cc_invoice_payments')[0];
  check('Rand invoices are matched without any prompt', !asked && !!z && z.payload.foreign_amount === null);

  /* 3. health check */
  const byId = (hc,id)=>hc.checks.find(c=>c.id===id);
  reset(); usdInvoiceAt(dI); usdBillAt(dI);
  S.fxRates = [{id:'r1', rate_date:days(-5), currency:'USD', rate:18.5}];
  {
    const hc = sandbox.computeHealthCheck();
    check('healthy books: no failures', hc.summary.fail===0);
    check('healthy books: journals balance, BS balances, sub-ledgers agree', ['journals','bs','ledgervsbs','ar','ap','inv-posted','bill-posted'].every(id=>byId(hc,id).status==='ok'));
    check('recent closing rate satisfies the FX check', byId(hc,'fx-rates').status==='ok');
  }
  S.fxRates = [];
  check('no closing rate for open USD balances is flagged', byId(sandbox.computeHealthCheck(),'fx-rates').status==='warn');
  // invoice edited after approval -> AR sub-ledger disagrees
  S.fxRates = [{id:'r1', rate_date:days(-5), currency:'USD', rate:18.5}];
  S.invoiceItems.i1[0].unit_price = 1200;
  {
    const hc = sandbox.computeHealthCheck();
    check('invoice edited after approval: receivables check fails', byId(hc,'ar').status==='fail' && /3[\s, ]*600/.test(byId(hc,'ar').detail));
    check('banner appears for failures', /Health check/.test(sandbox.renderHealthBanner()));
  }
  S.invoiceItems.i1[0].unit_price = 1000;
  // approved invoice with no revenue entry
  S.entries = S.entries.filter(e=>e.id!=='e1');
  check('approved invoice without a revenue entry fails', byId(sandbox.computeHealthCheck(),'inv-posted').status==='fail');
  usdInvoiceAt(dI); S.entries = S.entries.filter((e,i,a)=>a.findIndex(x=>x.id===e.id)===i);
  // duplicate numbers
  S.invoices.push({...S.invoices[0], id:'i2'}); S.invoiceItems.i2 = []; 
  check('duplicate invoice numbers are flagged', byId(sandbox.computeHealthCheck(),'dupes').status==='warn');
  S.invoices = S.invoices.slice(0,1);
  // foreign payment without a foreign amount
  S.invoicePayments = [{id:'p1', invoice_id:'i1', payment_date:days(-2), amount:5000}];
  check('foreign payment without a foreign amount is flagged', byId(sandbox.computeHealthCheck(),'fx-payments').status==='warn');
  S.invoicePayments = [];
  // stale bank line
  S.bankTransactions = [{id:'old', tx_date:days(-45), description:'old', amount:100, status:'unmatched'}];
  check('bank line unmatched for 45 days is flagged', byId(sandbox.computeHealthCheck(),'bank-old').status==='warn');
  S.bankTransactions = [];
  // negative stock, negative bank
  S.stockItems = [{id:'st1', name:'Widget', qty_on_hand:-3, unit_cost:5}];
  check('negative stock is flagged', byId(sandbox.computeHealthCheck(),'stock-neg').status==='warn');
  S.stockItems = [];
  S.accounts = [{name:'Main', starting_balance:-500}];
  check('overdrawn bank is flagged', byId(sandbox.computeHealthCheck(),'bank-neg').status==='warn');
  // tax provision for last year
  reset();
  const fy = sandbox.companyFinancialYearBounds(-1);
  S.entries = [{id:'r1', type:'revenue', amount:100000, entry_date:fy.start.slice(0,8)+'15', description:'Sales', vat_applicable:false, tags:[]}];
  check('profit last year with no tax recognised is flagged', byId(sandbox.computeHealthCheck(),'tax-provision').status==='warn');
  // rendering
  const out = sandbox.renderHealthCheck();
  check('health check tab renders groups and statuses', /Ledger integrity/.test(out) && /Sub-ledgers/.test(out) && /Foreign exchange/.test(out) && /status-pill/.test(out));
  S.reportsTab = 'health';
  let ok = true; try{ sandbox.render(); }catch(e){ ok=false; console.log(e); }
  check('reports page renders on the health tab', ok);
  check('empty books pass cleanly', (reset(), sandbox.computeHealthCheck().summary.fail===0));

  console.log(failures ? `\n${failures} FAILED` : '\nALL OK');
  process.exit(failures ? 1 : 0);
})().catch(e=>{ console.log('ERROR', e); process.exit(1); });
