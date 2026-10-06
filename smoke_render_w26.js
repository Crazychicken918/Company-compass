// Smoke test for Wave 43: payroll/EMP201 to ledger, stock/inventory, dashboard+budget on ledger, cash flow from ledger.
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
  this.approvePendingItem=approvePendingItem; this.rejectPendingItem=rejectPendingItem; this.makerCheckerOn=makerCheckerOn; this.refreshAll=refreshAll; this.computeCashFlow=computeCashFlow; this.renderCF=renderCF; this.computeBudgetVsActual=computeBudgetVsActual; this.vatFromLedger=vatFromLedger; this.buildLedger=buildLedger; this.monthlyPayrollActuals=monthlyPayrollActuals; this.renderEmp201Panel=renderEmp201Panel; this.sarsOwedPerLedger=sarsOwedPerLedger; this.computeLedgerVsBS=computeLedgerVsBS; this.renderDashboard=renderDashboard; this.tracksInventory=tracksInventory;
  this.renderManualJournals=renderManualJournals; this.ledgerLines=ledgerLines; this.todayIso=todayIso; this.totalsFor=totalsFor;
`, sandbox);
const S = sandbox.state;
const near = (a,b)=>Math.abs(a-b)<0.01;
function reset(){
  S.accounts=[{name:'Main', starting_balance:10000}]; S.entries=[]; S.invoices=[]; S.invoiceItems={}; S.invoicePayments=[]; S.supplierInvoices=[]; S.supplierInvoiceItems={};
  S.supplierInvoicePayments=[]; S.creditNotes=[]; S.creditNoteItems={}; S.supplierCreditNotes=[]; S.supplierCreditNoteItems={}; S.assets=[]; S.liabilities=[]; S.liabilityPayments=[];
  S.liabilityPaymentsAll=[]; S.payrollPayments=[]; S.employees=[]; S.emp201Submissions=[]; S.stockItems=[]; S.budgets=[]; S.manualJournals=[]; S.manualJournalLines={}; S.chartAccounts=[]; S.bankTransactions=[]; S.members=[]; S.pendingItems=[];
  S._invoicePaymentsPending=[]; S._supplierPaymentsPending=[];
  S.company={id:'c1', name:'Test Co', vat_registered:true, financial_year_end_month:2, maker_checker:false, locked_through_date:null};
  S.membership={role:'owner', status:'active'}; S.user={id:'u1', email:'me@x.co'};
}


const bal = (key, to)=>{ const t = sandbox.ledgerLines().filter(l=>l.key===key && (!to || l.date<=to)); return t.reduce((s,l)=>s+l.debit-l.credit,0); };
function journalsBalance(){ return sandbox.buildLedger().every(j=>Math.abs(j.lines.reduce((s,l)=>s+l.debit-l.credit,0))<0.005); }

/* ---------- 1. payroll to ledger ---------- */
reset();
S.payrollPayments = [{id:'p1', employee_id:'e1', pay_date:'2026-03-25', paid:true, gross:20000, net:15000, basic_salary:20000, travel_allowance:0, paye:3000, uif_employee:177.12, uif_employer:177.12, retirement_deduction:1000, medical_deduction:500, other_deduction:0, deductions:5000}];
S.employees = [{id:'e1', name:'Sam', active:true, salary:20000, pay_frequency:'monthly'}];
{
  check('payroll: ledger balances', journalsBalance());
  check('payroll: gross + employer UIF expensed (20 177.12)', near(bal('PAYROLL'), 20177.12));
  check('payroll: net pay leaves the bank (15 000)', near(bal('BANK') - 10000, -15000));
  check('payroll: SARS payable = PAYE 3000 + UIF 354.24', near(-bal('SARS'), 3354.24));
  check('payroll: pension/medical held in PAYDED (1 500 = gross - net - paye - uifEE ... )', near(-bal('PAYDED'), 20000-15000-3000-177.12));
  const pl = sandbox.computePL('2026-03-01','2026-03-31');
  check('P&L payroll cost shows 20 177.12 (not net 15 000)', near(pl.payrollCost, 20177.12));
  const bs = sandbox.computeBS('2026-03-31');
  check('BS carries SARS + deductions as current liabilities and still balances', bs.balances === true && near(bs.currentLiabOther, 3354.24 + (5000-3000-177.12)));
  check('BS check vs ledger: no differences', sandbox.computeLedgerVsBS('2026-03-31').hasDifferences === false);
}
// legacy payslip with no breakdown -> net only
reset();
S.payrollPayments = [{id:'p0', employee_id:'e1', pay_date:'2026-03-25', paid:true, net:8000}];
check('legacy payslip (net only) posts exactly as before', near(bal('PAYROLL'), 8000) && near(bal('SARS'), 0) && near(bal('BANK')-10000, -8000) && journalsBalance());
// unpaid payslips are ignored
reset();
S.payrollPayments = [{id:'p9', pay_date:'2026-03-25', paid:false, gross:5000, net:4000, paye:500}];
check('unpaid payslip posts nothing', near(bal('PAYROLL'), 0));

// SDL applies only above the R500k threshold
reset();
S.employees = [{id:'e1', name:'Big', active:true, salary:60000, pay_frequency:'monthly'}];
S.payrollPayments = [{id:'p1', employee_id:'e1', pay_date:'2026-03-25', paid:true, gross:60000, net:42000, basic_salary:60000, travel_allowance:0, paye:15000, uif_employee:177.12, uif_employer:177.12}];
{
  check('SDL accrued at 1% when over the threshold (600 in SARS + payroll)', near(-bal('SARS'), 15000+354.24+600) && near(bal('PAYROLL'), 60000+177.12+600) && journalsBalance());
  const m = sandbox.monthlyPayrollActuals()[0];
  check('EMP201 panel SDL equals the accrued SDL', near(m.sdl, 600));
  const panel = sandbox.renderEmp201Panel();
  check('EMP201 panel shows what is owed to SARS per the ledger', panel.includes('Owed to SARS per the ledger') && panel.includes('Mark submitted &amp; paid'));
  // EMP201 paid
  S.emp201Submissions = [{id:'s1', period_month:'2026-03', submitted:true, submitted_date:'2026-04-07', paye:15000, uif_employee:177.12, uif_employer:177.12, sdl:600}];
  check('EMP201 paid: SARS liability cleared', near(bal('SARS'), 0) && near(sandbox.sarsOwedPerLedger(), 0));
  check('EMP201 paid: bank reduced by the payment on the paid date', near(bal('BANK','2026-04-07') - 10000, -42000 - 15954.24) && near(bal('BANK','2026-04-06') - 10000, -42000));
  check('EMP201 paid: P&L unaffected by the payment', near(sandbox.computePL('2026-04-01','2026-04-30').payrollCost, 0));
  S.emp201Submissions[0].submitted = false;
  check('EMP201 un-submitted: liability back', near(-bal('SARS'), 15954.24));
}

/* ---------- 2. stock / inventory ---------- */
reset();
S.company.tracks_inventory = true;
S.stockItems = [{id:'st1', name:'Widget', unit_cost:10, qty_on_hand:90}];     // bought 100, sold 10
S.entries = [
  {id:'b1', type:'expense', amount:1150, entry_date:'2026-03-02', description:'Bill B1', vat_applicable:true, tags:[], expense_category:'cost_of_sales', source_supplier_invoice_id:'sb1'},
  {id:'c1', type:'expense', amount:100, entry_date:'2026-03-10', description:'Cost of sales — Widget (INV-1)', vat_applicable:false, tags:['cost-of-sales','stock'], expense_category:'cost_of_sales'},
];
S.supplierInvoiceItems = {sb1:[{quantity:100, unit_price:11.5, vat_applicable:true, stock_item_id:'st1'}]};
S.supplierInvoices = [{id:'sb1', bill_number:'B1', approval_status:'approved', status:'approved'}];
{
  check('stock: ledger balances', journalsBalance());
  check('stock: bill goes to Inventory, not to cost of sales', near(bal('INV','2026-03-05'), 1000) && near(bal('COS','2026-03-05'), 0));
  check('stock: sale relieves Inventory and charges cost of sales 100', near(bal('COS'), 100) && near(bal('INV'), 900));
  check('stock: no cash leaves the bank for the auto cost-of-sales entry', near(bal('BANK'), 10000));
  check('stock: cost expensed once (P&L COS = 100)', near(sandbox.computePL('2026-03-01','2026-03-31').cos, 100));
  check('stock: Inventory equals stock list value (90 x 10 = 900)', near(bal('INV'), 900));
}
// opening stock not backed by a bill
reset();
S.stockItems = [{id:'st1', name:'Widget', unit_cost:10, qty_on_hand:50}];
check('stock: opening stock brought in against Opening Balance Equity', near(bal('INV'), 500) && near(bal('OBE'), -10500) && journalsBalance());
// service business: no stock effect
reset(); S.company.tracks_inventory = false; S.stockItems = [{id:'st1', name:'x', unit_cost:10, qty_on_hand:50}];
check('stock: businesses that do not track inventory get no stock posting', near(bal('INV'), 0));
// non-stock bill lines still expensed
reset();
S.entries = [{id:'b2', type:'expense', amount:230, entry_date:'2026-03-02', description:'Bill B2', vat_applicable:true, tags:[], expense_category:'operating', source_supplier_invoice_id:'sb2'}];
S.supplierInvoiceItems = {sb2:[{quantity:1, unit_price:230, vat_applicable:true, stock_item_id:null}]};
check('bills without stock lines still expense normally', near(bal('OPEX'), 200) && near(bal('INV'), 0));

/* ---------- 3. dashboard + budget on the ledger ---------- */
reset();
S.entries = [
  {id:'r1', type:'revenue', amount:1150, entry_date:'2026-03-10', description:'Sale', vat_applicable:true, tags:['sales']},
  {id:'x1', type:'expense', amount:230, entry_date:'2026-03-11', description:'Ads', vat_applicable:true, tags:['marketing'], expense_category:'operating'},
  {id:'x2', type:'expense', amount:115, entry_date:'2026-03-12', description:'More ads', vat_applicable:true, tags:['marketing'], expense_category:'operating'},
];
S.invoices=[{id:'i1', invoice_number:'INV-1', status:'sent', approval_status:'approved', issue_date:'2026-03-15', due_date:'2026-04-15'}];
S.payrollPayments = [{id:'p1', pay_date:'2026-03-25', paid:true, gross:2000, net:1500, paye:300, uif_employee:20, uif_employer:20, basic_salary:2000}];
{
  const t = sandbox.totalsFor();
  check('dashboard revenue is VAT-exclusive (1 000)', near(t.revenue, 1000));
  check('dashboard expenses = opex 300 + payroll cost 2 020 (VAT-exclusive, payroll at full cost)', near(t.expenses, 300 + 2020));
  check('dashboard balance = ledger bank balance', near(t.predictedBalance, bal('BANK')));
  const pl = sandbox.computePL('0001-01-01','9999-12-31');
  check('dashboard agrees with the P&L', near(t.revenue, pl.revenue) && near(t.expenses, pl.cos + pl.totalOpex));
  const bs = sandbox.computeBS('9999-12-31');
  check('dashboard net worth = Balance Sheet equity', near(t.netWorth, bs.equity) && near(t.totalAssets, bs.totalAssets));
  const v = sandbox.vatFromLedger();
  check('dashboard VAT from VAT Control: output 150, input 45, payable 105', near(v.vatCollected,150) && near(v.vatPaid,45) && near(v.vatPayable,105));
  const out = sandbox.renderDashboard();
  check('dashboard renders', out.includes('Predicted Balance') && out.includes('excl. VAT'));
  S.budgets = [{id:'b1', tag:'marketing', type:'expense', monthly_amount:400}, {id:'b2', tag:'sales', type:'revenue', monthly_amount:1000}];
  const rows = sandbox.computeBudgetVsActual('2026-03-01','2026-03-31');
  const mk = rows.find(r=>r.tag==='marketing'), sl = rows.find(r=>r.tag==='sales');
  check('budget actual for expense is VAT-exclusive (300)', near(mk.actual, 300) && near(mk.pct, 0.75));
  check('budget actual for revenue is VAT-exclusive (1 000)', near(sl.actual, 1000));
}

/* ---------- 4. cash flow from the ledger ---------- */
reset();
S.entries = [
  {id:'r1', type:'revenue', amount:1150, entry_date:'2026-03-10', description:'Sale', vat_applicable:true, tags:[]},
  {id:'x1', type:'expense', amount:300, entry_date:'2026-03-11', description:'Rent', vat_applicable:false, tags:[], expense_category:'operating'},
  {id:'x2', type:'expense', amount:200, entry_date:'2026-03-12', description:'Stock buy', vat_applicable:false, tags:[], expense_category:'cost_of_sales'},
];
S.assets = [{id:'a1', description:'Laptop', value:30000, purchase_date:'2026-03-05', is_current:false, category:'equipment'}];
S.liabilities = [{id:'l1', description:'Bank loan', amount:50000, start_date:'2026-03-06', is_current:false}];
S.payrollPayments = [{id:'p1', pay_date:'2026-03-25', paid:true, gross:2000, net:1500, paye:300, uif_employee:20, uif_employer:20, basic_salary:2000}];
S.emp201Submissions = [{id:'s1', period_month:'2026-03', submitted:true, submitted_date:'2026-03-30', paye:300, uif_employee:20, uif_employer:20, sdl:0}];
S.manualJournals = [{id:'mj', journal_date:'2026-03-20', description:'Owner loan in', approval_status:'approved'}];
S.manualJournalLines = {mj:[{category:'ledger', account_key:'BANK', side:'debit', amount:500, signed_amount:0},{category:'ledger', account_key:'CAPITAL', side:'credit', amount:500, signed_amount:0}]};
{
  const cf = sandbox.computeCashFlow('2026-03-01','2026-03-31');
  check('CF: cash from revenue 1 150', near(cf.cashFromRevenue, 1150));
  check('CF: cost of sales 200 and opex 300', near(cf.cosOut, 200) && near(cf.opexOut, 300));
  check('CF: payroll net 1 500 and SARS 340 shown separately', near(cf.payrollOut, 1500) && near(cf.sarsOut, 340));
  check('CF: net operating = 1150-200-300-1500-340', near(cf.netOperating, -1190));
  check('CF: recorded asset/loan are non-cash memo lines (not in investing/financing cash)', near(cf.assetPurchases,0) && near(cf.liabilityDraws,0) && near(cf.assetsRecordedNonCash,30000) && near(cf.liabilitiesRecordedNonCash,50000));
  check('CF: manual journal bank line shown as other cash movement 500', near(cf.otherCashMovements, 500));
  check('CF now reconciles to the Balance Sheet cash', cf.reconciles === true && near(cf.closingCashDerived, cf.closingCashActual));
  check('CF closing = opening 10 000 + net change', near(cf.closingCashDerived, 10000 + cf.netChange) && near(cf.closingCashActual, bal('BANK')));
  const html = sandbox.renderCF(cf);
  check('CF renders SARS row, memo lines and no mismatch banner', html.includes('SARS') && html.includes('not a cash movement') && !html.includes("doesn't quite match"));
}
// loan repayment is financing, reconciles with a later period
S.liabilities = [{id:'l1', description:'Bank loan', amount:5000, start_date:'2026-01-01', is_current:false}];
S.liabilityPayments = [{id:'lp1', liability_id:'l1', payment_date:'2026-03-15', principal_amount:1000, interest_amount:0, amount:1000}];
{
  const cf = sandbox.computeCashFlow('2026-03-01','2026-03-31');
  check('CF: loan principal repaid 1 000 is financing', near(cf.liabilityPrincipalRepaid, 1000) && near(cf.netFinancing, -1000) && cf.reconciles === true);
  const cf2 = sandbox.computeCashFlow('2026-04-01','2026-04-30');
  check('CF: next period opens at the prior close', near(cf2.openingCash, sandbox.computeCashFlow('2026-03-01','2026-03-31').closingCashDerived) && cf2.reconciles === true);
}

console.log(failures ? `\n${failures} FAILED` : '\nALL OK');
process.exit(failures?1:0);
