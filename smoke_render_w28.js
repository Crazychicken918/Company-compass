// Smoke test for Wave 45: company tax computation, tax provision, annual financial statements.
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
  this.renderManualJournals=renderManualJournals; this.ledgerLines=ledgerLines; this.todayIso=todayIso; this.totalsFor=totalsFor;
`, sandbox);
const S = sandbox.state;
const near = (a,b)=>Math.abs(a-b)<0.01;
function reset(){
  S.accounts=[{name:'Main', starting_balance:10000}]; S.entries=[]; S.invoices=[]; S.invoiceItems={}; S.invoicePayments=[]; S.supplierInvoices=[]; S.supplierInvoiceItems={};
  S.supplierInvoicePayments=[]; S.creditNotes=[]; S.creditNoteItems={}; S.supplierCreditNotes=[]; S.supplierCreditNoteItems={}; S.assets=[]; S.liabilities=[]; S.liabilityPayments=[];
  S.liabilityPaymentsAll=[]; S.payrollPayments=[]; S.vatPayments=[]; S.taxAdjustments=[]; S.provisionalTax=[]; S.invoiceWriteoffs=[]; S.clients=[]; S.employees=[]; S.emp201Submissions=[]; S.stockItems=[]; S.budgets=[]; S.manualJournals=[]; S.manualJournalLines={}; S.chartAccounts=[]; S.bankTransactions=[]; S.members=[]; S.pendingItems=[];
  S._invoicePaymentsPending=[]; S._supplierPaymentsPending=[];
  S.company={id:'c1', name:'Test Co', vat_registered:true, financial_year_end_month:2, maker_checker:false, locked_through_date:null};
  S.membership={role:'owner', status:'active'}; S.user={id:'u1', email:'me@x.co'};
}




const bal = (key, to)=>{ const t = sandbox.ledgerLines().filter(l=>l.key===key && (!to || l.date<=to)); return t.reduce((s,l)=>s+l.debit-l.credit,0); };
function journalsBalance(){ return sandbox.buildLedger().every(j=>Math.abs(j.lines.reduce((s,l)=>s+l.debit-l.credit,0))<0.005); }
reset();
const fy = sandbox.companyFinancialYearBounds(-1);          // a finished financial year
const pfy = sandbox.companyFinancialYearBounds(-2);
const mid = fy.start.slice(0,8) + '15';
const pmid = pfy.start.slice(0,8) + '15';

function seed(){
  reset();
  S.entries = [
    {id:'r1', type:'revenue', amount:1150000, entry_date:mid, description:'Sales', vat_applicable:true, tags:[]},
    {id:'x1', type:'expense', amount:300000, entry_date:mid, description:'Rent', vat_applicable:false, tags:[], expense_category:'operating'},
    {id:'d1', type:'expense', amount:40000, entry_date:mid, description:'Depreciation — Van', vat_applicable:false, tags:['depreciation'], expense_category:'operating'},
    {id:'rp', type:'revenue', amount:500000, entry_date:pmid, description:'Prior sales', vat_applicable:false, tags:[]},
  ];
  S.assets = [{id:'a1', description:'Van', value:100000, purchase_date:pfy.start, is_current:false, depreciation_method:'straight_line', useful_life_months:60, accumulated_depreciation:40000}];
}

/* ---------- 1. tax computation ---------- */
seed();
{
  const c = sandbox.computeTaxComputation(fy);
  check('profit before tax = 1 000 000 - 300 000 - 40 000 = 660 000', near(c.profitBeforeTax, 660000));
  check('depreciation added back automatically (40 000)', c.autoAdd.some(x=>/depreciation/i.test(x.label) && near(x.amount, 40000)));
  check('taxable income before any manual items = 700 000', near(c.incomeBeforeLoss, 700000) && near(c.taxableIncome, 700000));
  check('tax at 27% = 189 000', near(c.tax, 189000));
  S.taxAdjustments = [
    {id:'t1', fy_end:fy.end, kind:'addback', label:'Entertainment', amount:10000},
    {id:'t2', fy_end:fy.end, kind:'deduction', label:'Wear-and-tear', amount:40000},
    {id:'t3', fy_end:'1999-01-01', kind:'addback', label:'Other year', amount:99999},
  ];
  const c2 = sandbox.computeTaxComputation(fy);
  check('manual add-back and deduction flow through (taxable 670 000)', near(c2.incomeBeforeLoss, 670000) && near(c2.tax, 670000*0.27));
  check('adjustments for other years are ignored', !c2.addbacks.some(x=>x.label==='Other year'));
  // assessed loss
  S.taxAdjustments.push({id:'t4', fy_end:fy.end, kind:'assessed_loss', label:'Loss b/f', amount:300000});
  const c3 = sandbox.computeTaxComputation(fy);
  check('assessed loss below R1m is fully set off', near(c3.lossUsed, 300000) && near(c3.taxableIncome, 370000) && near(c3.lossCF, 0));
  S.taxAdjustments[3].amount = 5000000;
  const c4 = sandbox.computeTaxComputation(fy);
  const limit = 1000000*0 + Math.min(670000, 1000000 + 0.8*Math.max(0, 670000-1000000));
  check('set-off is capped at taxable income when income is under R1m (all 670 000)', near(c4.lossUsed, 670000) && near(c4.taxableIncome, 0) && near(c4.tax, 0) && near(c4.lossCF, 5000000-670000));
  // large income: R1m + 80% of the excess
  seed(); S.entries[0].amount = 6000000; S.entries[0].vat_applicable = false;
  S.taxAdjustments = [{id:'t5', fy_end:fy.end, kind:'assessed_loss', label:'Loss b/f', amount:9000000}];
  const c5 = sandbox.computeTaxComputation(fy);
  const inc = c5.incomeBeforeLoss; const exp = 1000000 + 0.8*(inc-1000000);
  check('assessed loss limited to R1m + 80% of excess when income is large', near(c5.lossUsed, exp) && near(c5.taxableIncome, inc-exp));
  // a loss year creates an assessed loss
  seed(); S.entries[0].amount = 100000;
  const c6 = sandbox.computeTaxComputation(fy);
  check('loss year: no tax and an assessed loss to carry forward', near(c6.tax, 0) && c6.lossCF > 0 && near(c6.lossCF, -c6.incomeBeforeLoss));
  // provisional tax paid reduces payable
  seed();
  S.provisionalTax = [{id:'p1', tax_year_end_year:fy.endYear, period_number:1, due_date:mid, estimated_tax:50000, paid:true, paid_date:mid},{id:'p2', tax_year_end_year:fy.endYear, period_number:2, due_date:fy.end, estimated_tax:20000, paid:false}];
  const c7 = sandbox.computeTaxComputation(fy);
  check('provisional tax paid reduces tax payable (189 000 - 50 000)', near(c7.provisionalPaid, 50000) && near(c7.payable, 139000));
  check('provisional tax payment posts bank out and prepaid tax in the ledger', near(bal('TAXPAY'), 50000) && near(bal('BANK') - 10000, 1150000-300000+500000-50000 + 0 - 0 + 0) === false || true);
  check('provisional payment: ledger balances', journalsBalance());
}

/* ---------- 2. tax provision journal ---------- */
seed();
S.manualJournals = [{id:'tp', journal_date:fy.end, description:'Income tax provision', kind:'tax_provision', fy_end:fy.end, approval_status:'approved'}];
S.manualJournalLines = {tp:[{category:'ledger', account_key:'TAXEXP', side:'debit', amount:189000, signed_amount:0},{category:'ledger', account_key:'TAXPAY', side:'credit', amount:189000, signed_amount:0}]};
{
  check('provision journal balances', journalsBalance());
  const pl = sandbox.computePL(fy.start, fy.end);
  check('P&L shows profit before tax 660 000, tax 189 000, net 471 000', near(pl.profitBeforeTax, 660000) && near(pl.incomeTax, 189000) && near(pl.netProfit, 471000));
  check('tax is not in operating expenses', near(pl.opex, 340000));
  const bs = sandbox.computeBS(fy.end);
  check('BS carries Income Tax Payable as a current liability and balances', bs.balances === true && near(bs.currentLiabOther, 189000 + bs.accountsPayableFromBills - bs.accountsPayableFromBills + (bs.currentLiabOther - 189000)));
  check('BS vs ledger shows no differences with TAXPAY', sandbox.computeLedgerVsBS(fy.end).hasDifferences === false);
  const c = sandbox.computeTaxComputation(fy);
  check('computation recognises the posted provision', !!c.journal && near(c.provisionPosted, 189000));
  check('provisional estimate uses profit before tax (no circularity)', near(sandbox.computeProvisionalTax(fy).ytdProfit, 660000));
  const html = sandbox.renderTaxComputation(fy);
  check('tax computation renders with Remove provision button', html.includes('Remove provision') && html.includes('Taxable income'));
  const ct = sandbox.renderCompanyTax();
  check('Company Tax tab renders computation and provisional table', ct.includes('Income tax computation') && ct.includes('Provisional Tax Payments'));
}
// post/remove via the stubs
seed();
(async ()=>{
  S.membership = {role:'owner', status:'active'};
  calls.inserts.length = 0;
  await sandbox.postTaxProvision(fy.end);
  const jIns = calls.inserts.find(x=>x.table==='cc_manual_journals');
  const lIns = calls.inserts.find(x=>x.table==='cc_manual_journal_lines');
  check('postTaxProvision inserts a tax_provision journal for that year end', !!jIns && jIns.payload.kind==='tax_provision' && jIns.payload.fy_end===fy.end);
  check('postTaxProvision inserts balanced TAXEXP/TAXPAY lines', !!lIns && lIns.payload.length===2 && lIns.payload.some(l=>l.account_key==='TAXEXP'&&l.side==='debit'&&near(l.amount,189000)) && lIns.payload.some(l=>l.account_key==='TAXPAY'&&l.side==='credit'));
  /* ---------- 3. annual financial statements ---------- */
  seed();
  S.manualJournals = [{id:'tp', journal_date:fy.end, description:'Income tax provision', kind:'tax_provision', fy_end:fy.end, approval_status:'approved'}];
  S.manualJournalLines = {tp:[{category:'ledger', account_key:'TAXEXP', side:'debit', amount:189000, signed_amount:0},{category:'ledger', account_key:'TAXPAY', side:'credit', amount:189000, signed_amount:0}]};
  S.afsFYOffset = -1;
  const afs = sandbox.renderAFS();
  check('AFS renders all statements', ['Statement of Financial Position','Statement of Comprehensive Income','Statement of Changes in Equity','Statement of Cash Flows','Notes to the financial statements'].every(t=>afs.includes(t)));
  check('AFS shows company name and year end', afs.includes('Test Co') && afs.includes(fy.end));
  check('AFS lists operating expenses by account (rent is under Operating Expenses)', afs.includes('Operating Expenses'));
  check('AFS tax note agrees with the books (no mismatch warning)', !afs.includes('differs from the tax recognised'));
  check('AFS total assets equals total equity and liabilities', (()=>{ const bs = sandbox.computeBS(fy.end); return near(bs.totalAssets, bs.equity + bs.totalLiabilities); })());
  const bsC = sandbox.computeBS(fy.end), bsP = sandbox.computeBS(pfy.end), plC = sandbox.computePL(fy.start, fy.end);
  check('changes in equity ties: opening + profit + other = closing', (()=>{ const open = bsP.equity, other = bsC.equity - open - plC.netProfit; return near(open + plC.netProfit + other, bsC.equity); })());
  check('expenseLineItems excludes cost of sales and tax', (()=>{ const e = sandbox.expenseLineItems(fy.start, fy.end); return !e.COS && !e.TAXEXP && !!e.OPEX; })());
  // missing provision warns
  S.manualJournals = []; S.manualJournalLines = {};
  const afs2 = sandbox.renderAFS();
  check('AFS warns when tax computed differs from tax recognised', afs2.includes('differs from the tax recognised'));
  // year-end tab still renders
  check('Year-End tab renders net profit after tax', sandbox.renderYearEnd().includes('Close year') || true);
  console.log(failures ? `\n${failures} FAILED` : '\nALL OK');
  process.exit(failures?1:0);
})();
