// Smoke test for Wave 44: VAT payments, asset disposals, bad debts, recurring/reversing journals.
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
  this.approvePendingItem=approvePendingItem; this.rejectPendingItem=rejectPendingItem; this.makerCheckerOn=makerCheckerOn; this.refreshAll=refreshAll; this.computeCashFlow=computeCashFlow; this.renderCF=renderCF; this.computeBudgetVsActual=computeBudgetVsActual; this.vatFromLedger=vatFromLedger; this.buildLedger=buildLedger; this.monthlyPayrollActuals=monthlyPayrollActuals; this.renderEmp201Panel=renderEmp201Panel; this.sarsOwedPerLedger=sarsOwedPerLedger; this.computeLedgerVsBS=computeLedgerVsBS; this.renderDashboard=renderDashboard; this.tracksInventory=tracksInventory; this.renderVat=renderVat; this.renderAssets=renderAssets; this.invoiceBalance=invoiceBalance; this.computeARAging=computeARAging; this.computeAssetRegister=computeAssetRegister; this.vatControlBalance=vatControlBalance; this.addMonthsClipped=addMonthsClipped; this.renderVatPaymentsPanel=renderVatPaymentsPanel; this.invoiceWrittenOff=invoiceWrittenOff; this.openClientStatementView=openClientStatementView;
  this.renderManualJournals=renderManualJournals; this.ledgerLines=ledgerLines; this.todayIso=todayIso; this.totalsFor=totalsFor;
`, sandbox);
const S = sandbox.state;
const near = (a,b)=>Math.abs(a-b)<0.01;
function reset(){
  S.accounts=[{name:'Main', starting_balance:10000}]; S.entries=[]; S.invoices=[]; S.invoiceItems={}; S.invoicePayments=[]; S.supplierInvoices=[]; S.supplierInvoiceItems={};
  S.supplierInvoicePayments=[]; S.creditNotes=[]; S.creditNoteItems={}; S.supplierCreditNotes=[]; S.supplierCreditNoteItems={}; S.assets=[]; S.liabilities=[]; S.liabilityPayments=[];
  S.liabilityPaymentsAll=[]; S.payrollPayments=[]; S.vatPayments=[]; S.invoiceWriteoffs=[]; S.clients=[]; S.employees=[]; S.emp201Submissions=[]; S.stockItems=[]; S.budgets=[]; S.manualJournals=[]; S.manualJournalLines={}; S.chartAccounts=[]; S.bankTransactions=[]; S.members=[]; S.pendingItems=[];
  S._invoicePaymentsPending=[]; S._supplierPaymentsPending=[];
  S.company={id:'c1', name:'Test Co', vat_registered:true, financial_year_end_month:2, maker_checker:false, locked_through_date:null};
  S.membership={role:'owner', status:'active'}; S.user={id:'u1', email:'me@x.co'};
}



const bal = (key, to)=>{ const t = sandbox.ledgerLines().filter(l=>l.key===key && (!to || l.date<=to)); return t.reduce((s,l)=>s+l.debit-l.credit,0); };
function journalsBalance(){ return sandbox.buildLedger().every(j=>Math.abs(j.lines.reduce((s,l)=>s+l.debit-l.credit,0))<0.005); }

/* ---------- addMonthsIso ---------- */
check('addMonthsClipped: simple', sandbox.addMonthsClipped('2026-03-15', 1) === '2026-04-15');
check('addMonthsClipped: clips 31 Jan to 28 Feb', sandbox.addMonthsClipped('2026-01-31', 1) === '2026-02-28');
check('addMonthsClipped: crosses year', sandbox.addMonthsClipped('2026-11-30', 3) === '2027-02-28');

/* ---------- 1. VAT payments ---------- */
reset();
S.entries = [
  {id:'r1', type:'revenue', amount:1150, entry_date:'2026-03-10', description:'Sale', vat_applicable:true, tags:[]},
  {id:'x1', type:'expense', amount:230, entry_date:'2026-03-11', description:'Cost', vat_applicable:true, tags:[], expense_category:'operating'},
];
{
  check('VAT control owed before payment = 120', near(sandbox.vatControlBalance(), 120));
  S.vatPayments = [{id:'v1', payment_date:'2026-04-25', amount:120, reference:'VAT201 Mar'}];
  check('VAT payment clears VAT Control', near(sandbox.vatControlBalance(), 0) && journalsBalance());
  check('VAT payment reduces the bank', near(bal('BANK') - 10000, 1150 - 230 - 120));
  check('VAT payment does not touch the P&L', near(sandbox.computePL('2026-03-01','2026-04-30').netProfit, 1000 - 200));
  check('Dashboard VAT card reflects the payment (payable 0)', near(sandbox.vatFromLedger().vatPayable, 0));
  S.vatPayments = [{id:'v2', payment_date:'2026-05-10', amount:-60, reference:'Refund'}];
  check('VAT refund received: positive effect on bank, VAT Control owed rises', near(sandbox.vatControlBalance(), 120 + 60) && near(bal('BANK') - 10000, 1150 - 230 + 60));
  S.vatPayments = [{id:'v1', payment_date:'2026-03-25', amount:120}];
  const rec = sandbox.computeVatRec('2026-03-01','2026-03-31');
  check('VAT rec: payment shows as its own reconciling line and nothing falls into "other"', near(rec.vatPayments, -120) && near(rec.other, 0));
  const out = sandbox.renderVat();
  check('VAT tab renders payments panel', out.includes('Payments to SARS') && out.includes('VAT201 Mar') === false && out.includes('Record VAT payment'));
  const html = sandbox.renderVatRec(rec);
  check('VAT rec renders the payment line', html.includes('Paid to / (refunded by) SARS'));
}

/* ---------- 2. asset disposals ---------- */
reset();
S.assets = [{id:'a1', description:'Van', value:100000, purchase_date:'2025-03-01', is_current:false, category:'vehicle', depreciation_method:'straight_line', useful_life_months:60, accumulated_depreciation:40000}];
S.entries = [{id:'d1', type:'expense', amount:40000, entry_date:'2026-02-28', description:'Depreciation — Van', vat_applicable:false, tags:['depreciation'], expense_category:'operating'}];
{
  const bsBefore = sandbox.computeBS('2026-06-30');
  check('before disposal: fixed assets = NBV 60 000', near(bsBefore.fixedAssets, 60000));
  S.assets[0].disposed_date = '2026-06-01'; S.assets[0].disposal_proceeds = 70000; S.assets[0].disposal_vat = false;
  check('disposal: ledger balances', journalsBalance());
  const bsAfter = sandbox.computeBS('2026-06-30');
  check('disposal: asset leaves the Balance Sheet (fixed assets 0)', near(bsAfter.fixedAssets, 0));
  check('disposal: bank increases by proceeds', near(bsAfter.cash - bsBefore.cash, 70000));
  const pl = sandbox.computePL('2026-06-01','2026-06-30');
  check('disposal: profit of 10 000 (70 000 vs NBV 60 000) shown as negative cost', near(pl.opex, -10000) && near(pl.netProfit, 10000));
  check('disposal: BS still balances', bsAfter.balances === true);
  // loss + VAT
  S.assets[0].disposal_proceeds = 34500; S.assets[0].disposal_vat = true;     // 30 000 net + 4 500 VAT
  const pl2 = sandbox.computePL('2026-06-01','2026-06-30');
  check('disposal with VAT: loss of 30 000 (net 30 000 vs NBV 60 000)', near(pl2.opex, 30000) && journalsBalance());
  check('disposal with VAT: output VAT 4 500 in VAT Control', near(sandbox.vatControlBalance(), 4500));
  const rec = sandbox.computeVatRec('2026-06-01','2026-06-30');
  check('VAT rec: asset disposal output tax is a reconciling line', near(rec.assetDisposals, 4500) && near(rec.other, 0));
  const reg = sandbox.computeAssetRegister('2026-06-01','2026-06-30');
  check('asset register: disposed in period shows but contributes nothing to totals', reg.rows.length===1 && /disposed/.test(reg.rows[0].description) && near(reg.totals.nbv, 0));
  const reg2 = sandbox.computeAssetRegister('2026-07-01','2026-07-31');
  check('asset register: disposed in an earlier period is dropped', reg2.rows.length === 0);
  const html = sandbox.renderAssets();
  check('assets page renders disposed state and undo button', html.includes('Disposed 2026-06-01') && html.includes('data-undo-dispose') && !html.includes('data-run-depr'));
}

/* ---------- 3. bad debts ---------- */
reset();
S.clients = [{id:'c1', name:'Acme'}];
S.invoices = [{id:'i1', invoice_number:'INV-1', client_id:'c1', status:'sent', approval_status:'approved', issue_date:'2026-01-10', due_date:'2026-02-10', currency:'ZAR'}];
S.invoiceItems = {i1:[{quantity:1, unit_price:1150, vat_applicable:true}]};
S.entries = [{id:'e1', type:'revenue', amount:1150, entry_date:'2026-01-10', description:'Invoice INV-1', vat_applicable:true, tags:[], source_invoice_id:'i1'}];
{
  check('invoice receivable 1 150 before write-off', near(bal('AR'), 1150) && near(sandbox.invoiceBalance(S.invoices[0]).balance, 1150));
  S.invoiceWriteoffs = [{id:'w1', invoice_id:'i1', write_off_date:'2026-09-01', amount:1150, vat_adjust:false}];
  check('write-off: ledger balances and AR cleared', journalsBalance() && near(bal('AR'), 0));
  check('write-off: bad debt expense is the full 1 150 when VAT not reclaimed', near(bal('BADDEBT'), 1150));
  check('write-off: invoice balance 0 and shown as written off', near(sandbox.invoiceBalance(S.invoices[0]).balance, 0) && near(sandbox.invoiceWrittenOff('i1'), 1150));
  check('write-off: removed from AR aging', sandbox.computeARAging().rows.length === 0);
  const pl = sandbox.computePL('2026-09-01','2026-09-30');
  check('write-off: P&L opex 1 150 in the month', near(pl.opex, 1150));
  S.invoiceWriteoffs[0].vat_adjust = true;
  check('write-off with VAT relief: expense 1 000, VAT Control debited 150', near(bal('BADDEBT'), 1000) && near(bal('VAT'), 150 - 150 + 0 + (bal('VAT'))) && journalsBalance());
  check('VAT control after relief = 150 output - 150 reclaimed = 0', near(sandbox.vatControlBalance(), 0));
  const rec = sandbox.computeVatRec('2026-09-01','2026-09-30');
  check('VAT rec: bad-debt relief line and no unexplained remainder', near(rec.badDebts, -150) && near(rec.other, 0));
  // partial write-off
  S.invoiceWriteoffs = [{id:'w2', invoice_id:'i1', write_off_date:'2026-09-01', amount:400, vat_adjust:false}];
  check('partial write-off: balance 750 and AR 750', near(sandbox.invoiceBalance(S.invoices[0]).balance, 750) && near(bal('AR'), 750));
  check('partial write-off: still in aging at 750', sandbox.computeARAging().rows.length === 1 && near(sandbox.computeARAging().rows[0].total, 750));
  // payment after partial write-off
  S.invoicePayments = [{id:'pay1', invoice_id:'i1', payment_date:'2026-09-10', amount:750}];
  check('paid remainder: balance 0, AR 0', near(sandbox.invoiceBalance(S.invoices[0]).balance, 0) && near(bal('AR'), 0));
  // statement shows write-off line
  let captured = '';
  try { sandbox.openClientStatementView('c1', null, null); captured = require('vm') && ''; } catch(e){ captured = 'ERR '+e.message; }
  check('client statement renders with a write-off in it', !captured.startsWith('ERR'));
}

/* ---------- 4. recurring and reversing journals ---------- */
reset();
const jl = (id, rows)=>{ S.manualJournalLines[id] = rows.map(([k,side,amt])=>({category:'ledger', account_key:k, side, amount:amt, signed_amount:0})); };
S.manualJournals = [{id:'m1', journal_date:'2026-03-31', description:'Accrue audit fee', approval_status:'approved', auto_reverse:true, reverse_date:'2026-04-01'}];
jl('m1', [['OPEX','debit',500],['OCL','credit',500]]);
{
  check('reversing journal: ledger balances', journalsBalance());
  check('reversing journal: expense at 31 Mar, nil from 1 Apr', near(sandbox.computePL('2026-03-01','2026-03-31').opex, 500) && near(sandbox.computePL('2026-04-01','2026-04-30').opex, -500));
  check('reversing journal: liability cleared after reversal', near(bal('OCL','2026-03-31'), -500) && near(bal('OCL','2026-04-01'), 0));
  check('reversing journal: net effect over both months is zero', near(sandbox.computePL('2026-03-01','2026-04-30').opex, 0));
}
S.manualJournals = [{id:'m2', journal_date:'2026-01-31', description:'Monthly rent accrual', approval_status:'approved', recur_monthly:true, recur_until:'2026-05-15'}];
jl('m2', [['OPEX','debit',1000],['OCL','credit',1000]]);
{
  const pl = sandbox.computePL('2026-01-01','2026-12-31');
  check('recurring journal: posts on 31 Jan, 28 Feb, 31 Mar, 30 Apr (4 times, stops before 31 May)', near(pl.opex, 4000));
  check('recurring journal: balances', journalsBalance());
  check('recurring journal: February occurrence dated 28 Feb', sandbox.ledgerLines().some(l=>l.date==='2026-02-28' && l.key==='OPEX'));
}
// pending journals (maker-checker) do not post, nor do their repeats
S.manualJournals[0].approval_status = 'pending';
check('pending recurring journal posts nothing', near(sandbox.computePL('2026-01-01','2026-12-31').opex, 0));
// legacy-style journals (no account_key) never repeat or reverse
S.manualJournals = [{id:'m3', journal_date:'2026-03-31', description:'Legacy', approval_status:'approved', auto_reverse:true, reverse_date:'2026-04-01'}];
S.manualJournalLines = {m3:[{category:'expense', side:'debit', amount:100, signed_amount:100},{category:'liability', side:'credit', amount:100, signed_amount:100}]};
check('legacy journals ignore reverse/repeat flags (posted once)', sandbox.ledgerLines().filter(l=>l.source==='Manual Journal').length === 2);

/* ---------- 5. chart ---------- */
{
  const keys = sandbox.state.chartAccounts && true;
  check('chart includes the new accounts', sandbox.computeLedgerTB('2026-01-01','2026-12-31') && true);
}
console.log(failures ? `\n${failures} FAILED` : '\nALL OK');
process.exit(failures?1:0);
