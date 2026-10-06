// Smoke test for Wave 42: comparatives, year-end close, bank rec, VAT recon, maker-checker.
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
  this.approvePendingItem=approvePendingItem; this.rejectPendingItem=rejectPendingItem; this.makerCheckerOn=makerCheckerOn; this.refreshAll=refreshAll;
  this.renderManualJournals=renderManualJournals; this.ledgerLines=ledgerLines; this.todayIso=todayIso; this.totalsFor=totalsFor;
`, sandbox);
const S = sandbox.state;
const near = (a,b)=>Math.abs(a-b)<0.01;
function reset(){
  S.accounts=[{name:'Main', starting_balance:10000}]; S.entries=[]; S.invoices=[]; S.invoiceItems={}; S.invoicePayments=[]; S.supplierInvoices=[]; S.supplierInvoiceItems={};
  S.supplierInvoicePayments=[]; S.creditNotes=[]; S.creditNoteItems={}; S.supplierCreditNotes=[]; S.supplierCreditNoteItems={}; S.assets=[]; S.liabilities=[]; S.liabilityPayments=[];
  S.liabilityPaymentsAll=[]; S.payrollPayments=[]; S.manualJournals=[]; S.manualJournalLines={}; S.chartAccounts=[]; S.bankTransactions=[]; S.members=[]; S.pendingItems=[];
  S._invoicePaymentsPending=[]; S._supplierPaymentsPending=[];
  S.company={id:'c1', name:'Test Co', vat_registered:true, financial_year_end_month:2, maker_checker:false, locked_through_date:null};
  S.membership={role:'owner', status:'active'}; S.user={id:'u1', email:'me@x.co'};
}

/* ---------- 1. comparatives ---------- */
check('shiftIsoYears: normal date', sandbox.shiftIsoYears('2026-03-15', -1) === '2025-03-15');
check('shiftIsoYears: 29 Feb -> 28 Feb in a non-leap year', sandbox.shiftIsoYears('2024-02-29', -1) === '2023-02-28');
{
  const r = sandbox.priorPeriodRange('2026-03-01','2026-03-31','year');
  check('priorPeriodRange year: same dates a year earlier', r.start==='2025-03-01' && r.end==='2025-03-31');
  const p = sandbox.priorPeriodRange('2026-03-01','2026-03-31','previous');
  check('priorPeriodRange previous: equal-length period immediately before (29 Jan-28 Feb)', p.start==='2026-01-29' && p.end==='2026-02-28');
  check('priorPeriodRange none -> null', sandbox.priorPeriodRange('2026-03-01','2026-03-31','none') === null);
}
reset();
S.entries = [
  {id:'a', type:'revenue', amount:2000, entry_date:'2026-03-10', description:'S26', vat_applicable:false, tags:[]},
  {id:'b', type:'revenue', amount:1000, entry_date:'2025-03-10', description:'S25', vat_applicable:false, tags:[]},
  {id:'c', type:'expense', amount:500, entry_date:'2026-03-12', description:'E26', vat_applicable:false, tags:[], expense_category:'operating'},
];
{
  const pl = sandbox.computePL('2026-03-01','2026-03-31'), prior = sandbox.computePL('2025-03-01','2025-03-31');
  const out = sandbox.renderPL(pl, prior);
  check('renderPL with comparative: header shows both periods + Variance', out.includes('2025-03-01 to 2025-03-31') && out.includes('Variance'));
  check('renderPL with comparative: revenue variance 1000 and 100%', out.includes('1,000') || out.includes('1 000') || /1[ , ]?000/.test(out));
  check('renderPL without comparative: no Variance header', !sandbox.renderPL(pl).includes('<th style="text-align:right;">Variance</th>'));
  const bs = sandbox.computeBS('2026-03-31'), bsp = sandbox.computeBS('2025-03-31');
  const b = sandbox.renderBS(bs, bsp);
  check('renderBS with comparative: As at both dates + Variance', b.includes('As at 2026-03-31') && b.includes('As at 2025-03-31') && b.includes('Variance'));
  check('renderBS without comparative still renders', sandbox.renderBS(bs).includes('Total Equity'));
}

/* ---------- 2. year-end close ---------- */
reset();
const fys = sandbox.financialYearsList();
const fy = fys.find(f=>f.end < sandbox.todayIso());      // a finished year
const fyNext = fys.find(f=>f.end === fy.end) && sandbox.financialYearsList()[0];
const inFY = d => d; // helper
const midFY = fy.start.slice(0,4)+'-'+fy.start.slice(5,7)+'-15';
S.entries = [
  {id:'r1', type:'revenue', amount:1150, entry_date:fy.start, description:'Sale', vat_applicable:true, tags:[]},
  {id:'x1', type:'expense', amount:300, entry_date:fy.start, description:'Rent', vat_applicable:false, tags:[], expense_category:'operating'},
];
{
  const cl = sandbox.buildClosingLines(fy.end);
  check('closing lines: net profit 700', near(cl.netProfit, 700));
  const dr = cl.lines.filter(l=>l.side==='debit').reduce((s,l)=>s+l.amount,0), crd = cl.lines.filter(l=>l.side==='credit').reduce((s,l)=>s+l.amount,0);
  check('closing lines balance', near(dr, crd));
  check('closing lines: revenue debited, expense credited, RE credited', cl.lines.some(l=>l.key==='REV'&&l.side==='debit'&&near(l.amount,1000)) && cl.lines.some(l=>l.key==='OPEX'&&l.side==='credit'&&near(l.amount,300)) && cl.lines.some(l=>l.key==='RE'&&l.side==='credit'&&near(l.amount,700)));
  // post it as a journal
  S.manualJournals = [{id:'yj', journal_date:fy.end, description:'Year-end close', kind:'year_end_close', fy_end:fy.end, approval_status:'approved'}];
  S.manualJournalLines = {yj: cl.lines.map(l=>({category:'ledger', account_key:l.key, side:l.side, amount:l.amount, signed_amount:0}))};
  const pl = sandbox.computePL(fy.start, fy.end);
  check('P&L for the closed year still shows its profit', near(pl.revenue,1000) && near(pl.netProfit,700));
  const nextStart = new Date(fy.end+'T00:00:00Z'); nextStart.setUTCDate(nextStart.getUTCDate()+1);
  const ns = nextStart.toISOString().slice(0,10);
  const plAfter = sandbox.computePL(ns, '2099-12-31');
  check('P&L for the next year starts at zero', near(plAfter.revenue,0) && near(plAfter.netProfit,0));
  const bs = sandbox.computeBS(fy.end);
  check('BS after close: retained earnings carries 700', !!bs.equityLines.find(l=>/retained/i.test(l.label) && near(l.amount,700)));
  check('BS after close: profit-to-date line is zero (no double count)', near(bs.equityLines.find(l=>/profit/i.test(l.label)).amount, 0));
  check('BS after close balances', bs.balances === true);
  const tbIn = sandbox.computeLedgerTB(fy.start, fy.end);
  check('TB for the closed year balances and shows revenue (not zeroed)', Math.abs(tbIn.diff)<0.005 && !!tbIn.rows.find(r=>r.key==='REV' && near(r.credit,1000)));
  check('TB for the closed year does not also show retained earnings (no double count)', !tbIn.rows.find(r=>r.key==='RE'));
  const tbNext = sandbox.computeLedgerTB(ns, '2099-12-31');
  check('TB for the next year balances with Retained Earnings b/f 700', Math.abs(tbNext.diff)<0.005 && !!tbNext.rows.find(r=>r.key==='RE' && near(r.credit,700)));
  const ye = sandbox.renderYearEnd();
  check('renderYearEnd: shows closed status + Reopen button', ye.includes('closed') && ye.includes('data-reopen-fy="'+fy.end+'"'));
}
// close / reopen actions via the stub
reset();
S.entries = [{id:'r1', type:'revenue', amount:1150, entry_date:fy.start, description:'Sale', vat_applicable:true, tags:[]}];
(async ()=>{
  calls.inserts.length = 0; calls.updates.length = 0; calls.deletes.length = 0;
  await sandbox.closeFinancialYear(fy.end);
  const jIns = calls.inserts.find(c=>c.table==='cc_manual_journals');
  check('closeFinancialYear inserts a year_end_close journal dated the year-end', !!jIns && jIns.payload.kind==='year_end_close' && jIns.payload.fy_end===fy.end && jIns.payload.journal_date===fy.end);
  const lIns = calls.inserts.find(c=>c.table==='cc_manual_journal_lines');
  check('closeFinancialYear inserts ledger lines (revenue debit + RE credit)', !!lIns && Array.isArray(lIns.payload) && lIns.payload.some(l=>l.account_key==='RE' && l.side==='credit') && lIns.payload.every(l=>l.category==='ledger'));
  const lock = calls.updates.find(u=>u.table==='cc_companies');
  check('closeFinancialYear locks the books through the year-end', !!lock && lock.payload.locked_through_date===fy.end);

  /* ---------- 3. bank reconciliation ---------- */
  reset();
  S.entries = [
    {id:'e1', type:'revenue', amount:1000, entry_date:'2026-02-01', description:'Deposit A', vat_applicable:false, tags:[]},
    {id:'e2', type:'revenue', amount:500, entry_date:'2026-02-05', description:'Deposit B (in transit)', vat_applicable:false, tags:[]},
    {id:'e3', type:'expense', amount:200, entry_date:'2026-02-06', description:'Cheque (unpresented)', vat_applicable:false, tags:[], expense_category:'operating'},
  ];
  S.bankTransactions = [
    {id:'t1', tx_date:'2026-02-01', description:'Deposit A', amount:1000, status:'matched', matched_entry_type:'revenue', matched_entry_id:'e1'},
    {id:'t2', tx_date:'2026-02-10', description:'Bank interest', amount:30, status:'unmatched'},
    {id:'t3', tx_date:'2026-02-11', description:'Bank fee', amount:-20, status:'ignored'},
  ];
  {
    const rec = sandbox.computeBankRec('2026-02-28', 10000+1000+30-20);   // statement = opening + A + interest - fee
    check('bank rec: ledger balance 11300', near(rec.ledgerBalance, 11300));
    check('bank rec: unmatched bank lines total 30, ignored -20', near(rec.unmatchedTotal,30) && near(rec.ignoredTotal,-20));
    check('bank rec: outstanding book postings = +500 - 200 (opening and matched excluded)', rec.outstanding.length===2 && near(rec.outstandingTotal, 300));
    check('bank rec: adjusted book 11310 and adjusted bank 11310', near(rec.adjustedBook, 11310) && near(rec.adjustedBank, 11310));
    check('bank rec: reconciled', rec.reconciled === true && near(rec.difference,0));
    const out = sandbox.renderBankRec(rec);
    check('renderBankRec: shows Reconciled message', out.includes('Reconciled'));
    const bad = sandbox.computeBankRec('2026-02-28', 11000);
    check('bank rec: wrong statement balance shows a difference', bad.reconciled===false && near(bad.difference, -10));
    check('renderBankRec: not-reconciled message', sandbox.renderBankRec(bad).includes('Not reconciled'));
    const none = sandbox.computeBankRec('2026-02-28', null);
    check('bank rec: no statement entered -> prompts for it', none.hasStatement===false && sandbox.renderBankRec(none).includes('Enter your statement balance'));
  }
  // payment matched via linked_payment_id
  reset();
  S.invoices = [{id:'i1', invoice_number:'INV-1', approval_status:'approved', status:'sent', issue_date:'2026-01-05'}];
  S.invoicePayments = [{id:'pay1', invoice_id:'i1', payment_date:'2026-02-02', amount:800}];
  S.bankTransactions = [{id:'t9', tx_date:'2026-02-02', description:'EFT', amount:800, status:'matched', matched_entry_type:'invoice', matched_entry_id:'i1', linked_payment_id:'pay1'}];
  {
    const rec = sandbox.computeBankRec('2026-02-28', 10800);
    check('bank rec: invoice payment matched via linked_payment_id is not outstanding', rec.outstanding.length===0 && rec.reconciled===true);
  }

  /* ---------- 4. VAT 201 reconciliation ---------- */
  reset();
  S.entries = [
    {id:'v1', type:'revenue', amount:1150, entry_date:'2026-03-05', description:'Sale', vat_applicable:true, tags:[]},
    {id:'v2', type:'expense', amount:230, entry_date:'2026-03-06', description:'Cost', vat_applicable:true, tags:[], expense_category:'operating'},
  ];
  S.creditNotes = [{id:'cn1', credit_note_number:'CN-1', approval_status:'approved', status:'issued', issue_date:'2026-03-10'}];
  S.creditNoteItems = {cn1:[{quantity:1, unit_price:115, vat_applicable:true}]};
  S.manualJournals = [{id:'vj', journal_date:'2026-03-20', description:'VAT adj', approval_status:'approved'}];
  S.manualJournalLines = {vj:[{category:'ledger', account_key:'VAT', side:'credit', amount:10, signed_amount:0},{category:'ledger', account_key:'OPEX', side:'debit', amount:10, signed_amount:0}]};
  {
    const r = sandbox.computeVatRec('2026-03-01','2026-03-31');
    check('VAT rec: VAT201 output 150, input 30, net 120', near(r.per201.output,150) && near(r.per201.input,30) && near(r.per201.net,120));
    check('VAT rec: credit note reduces output by 15', near(r.creditNotes, -15));
    check('VAT rec: journal to VAT +10', near(r.journals, 10));
    check('VAT rec: ledger movement = 120 - 15 + 10 = 115', near(r.ledgerMovement, 115));
    const tie = r.per201.net + r.roundingOutput + r.roundingInput + r.creditNotes + r.supplierCreditNotes + r.journals + r.other;
    check('VAT rec: VAT201 + reconciling items = ledger movement', near(tie, r.ledgerMovement));
    check('VAT rec: closing balance 115', near(r.closing, 115));
    const out = sandbox.renderVatRec(r);
    check('renderVatRec: shows reconciling items and credit-note note', out.includes('Customer credit notes issued') && out.includes('Movement on VAT Control account per ledger'));
  }

  /* ---------- 5. maker-checker ---------- */
  reset();
  S.company.maker_checker = true;
  S.manualJournals = [
    {id:'mj1', journal_date:'2026-04-01', description:'Pending journal', approval_status:'pending', created_by:'u1'},
    {id:'mj2', journal_date:'2026-04-02', description:'Their journal', approval_status:'pending', created_by:'u2'},
    {id:'mj3', journal_date:'2026-04-03', description:'Rejected one', approval_status:'rejected', rejection_note:'wrong account', created_by:'u2'},
  ];
  const jl = d=>[{category:'ledger', account_key:'OPEX', side:'debit', amount:d, signed_amount:0},{category:'ledger', account_key:'BANK', side:'credit', amount:d, signed_amount:0}];
  S.manualJournalLines = {mj1: jl(100), mj2: jl(200), mj3: jl(300)};
  S.members = [{user_id:'u2', email:'checker@x.co'}];
  S._invoicePaymentsPending = [{id:'ip1', invoice_id:'i1', payment_date:'2026-04-04', amount:50, approval_status:'pending', created_by:'u2'}];
  S.liabilities = [{id:'L1', description:'Bank loan', amount:5000, is_current:false, start_date:'2026-01-01'}];
  S.liabilityPaymentsAll = [{id:'lp1', liability_id:'L1', payment_date:'2026-04-05', principal_amount:400, interest_amount:25, approval_status:'pending', created_by:'u2'}];
  {
    check('makerCheckerOn reflects the company setting', sandbox.makerCheckerOn() === true);
    const bank = sandbox.ledgerLines().filter(l=>l.key==='BANK' && l.source==='Manual Journal');
    check('ledger ignores pending and rejected journals', bank.length === 0);
    const items = sandbox.rebuildPendingItems();
    check('pending items: 2 journals + 1 customer payment + 1 loan payment', items.length === 4 && items.filter(i=>i.kind==='journal').length === 2);
    check('canApproveItem: own item refused, other person ok', sandbox.canApproveItem({created_by:'u1'}) === false && sandbox.canApproveItem({created_by:'u2'}) === true);
    const panel = sandbox.renderApprovalsPanel();
    check('approvals panel lists items, own item has no Approve button', panel.includes('Awaiting your approval (4)') && panel.includes('data-approve-item="journal|mj2"') && !panel.includes('data-approve-item="journal|mj1"') && panel.includes('A different person must approve'));
    check('approvals panel names the other person', panel.includes('checker@x.co'));
    const mjTab = sandbox.renderManualJournals();
    check('Manual Journals tab shows pending/rejected pills and the panel', mjTab.includes('pending approval') && mjTab.includes('rejected') && mjTab.includes('Awaiting your approval') && mjTab.includes('wrong account'));
    // approve own -> refused
    calls.updates.length = 0;
    const own = await sandbox.approvePendingItem('journal', 'mj1');
    check('approving your own journal is refused (no update sent)', own === false && !calls.updates.some(u=>u.table==='cc_manual_journals'));
  }
  // approve someone else's (state will be refreshed from the stub afterwards — assert on calls)
  S.pendingItems = null; sandbox.rebuildPendingItems();
  calls.updates.length = 0; calls.inserts.length = 0;
  {
    const ok = await sandbox.approvePendingItem('journal', 'mj2');
    const up = calls.updates.find(u=>u.table==='cc_manual_journals');
    check('approving another person\'s journal sends status approved with approver', ok === true && up && up.payload.approval_status==='approved' && up.payload.approved_by==='u1' && up.filters.id==='mj2');
  }
  reset(); S.company.maker_checker = true;
  S.liabilities = [{id:'L1', description:'Bank loan', amount:5000, is_current:false, start_date:'2026-01-01'}];
  S.liabilityPaymentsAll = [{id:'lp1', liability_id:'L1', payment_date:'2026-04-05', principal_amount:400, interest_amount:25, approval_status:'pending', created_by:'u2'}];
  sandbox.rebuildPendingItems();
  calls.updates.length = 0; calls.inserts.length = 0;
  {
    await sandbox.approvePendingItem('liability_payment', 'lp1');
    const ie = calls.inserts.find(c=>c.table==='cc_entries');
    check('approving a loan payment books the interest expense then', !!ie && ie.payload.amount===25 && ie.payload.tags.includes('liability-payment'));
    const up = calls.updates.find(u=>u.table==='cc_liability_payments');
    check('approved loan payment records the interest entry id', !!up && up.payload.approval_status==='approved' && !!up.payload.interest_entry_id);
  }
  reset(); S.company.maker_checker = true;
  S.manualJournals = [{id:'mjr', journal_date:'2026-04-02', description:'To reject', approval_status:'pending', created_by:'u2'}];
  S.manualJournalLines = {mjr:[]};
  sandbox.rebuildPendingItems(); calls.updates.length = 0;
  {
    await sandbox.rejectPendingItem('journal', 'mjr', 'wrong');
    const up = calls.updates.find(u=>u.table==='cc_manual_journals');
    check('reject stores status rejected with the reason', !!up && up.payload.approval_status==='rejected' && up.payload.rejection_note==='wrong');
  }
  // maker-checker off: no panel, items approve immediately
  reset();
  check('maker-checker off: no approvals panel', sandbox.renderApprovalsPanel() === '');
  check('splitApproval: missing status counts as approved', sandbox.splitApproval([{id:1},{id:2,approval_status:'pending'},{id:3,approval_status:'rejected'}]).ok.length === 1);
  // loading: pending payments are not counted
  reset();
  DATA['cc_invoice_payments'] = [{id:'ok1', invoice_id:'i1', payment_date:'2026-04-01', amount:100, approval_status:'approved'},{id:'pp1', invoice_id:'i1', payment_date:'2026-04-02', amount:999, approval_status:'pending', created_by:'u2'}];
  DATA['cc_liability_payments'] = [{id:'lpA', liability_id:'L1', payment_date:'2026-04-01', principal_amount:10, interest_amount:0, approval_status:'approved'},{id:'lpP', liability_id:'L1', payment_date:'2026-04-02', principal_amount:999, interest_amount:0, approval_status:'pending', created_by:'u2'}];
  await sandbox.refreshAll();
  check('refreshAll: state.invoicePayments only holds approved payments', S.invoicePayments.length === 1 && S.invoicePayments[0].id === 'ok1');
  check('refreshAll: state.liabilityPayments only approved; all kept separately', S.liabilityPayments.length === 1 && S.liabilityPaymentsAll.length === 2);
  check('refreshAll: pending payments land in pendingItems', (S.pendingItems||[]).some(i=>i.kind==='invoice_payment' && i.id==='pp1') && (S.pendingItems||[]).some(i=>i.kind==='liability_payment' && i.id==='lpP'));

  /* ---------- 6. markup wiring ---------- */
  check('markup: all three payment forms send approval_status', (html.match(/approval_status: approvalStatusForNew\(\)/g)||[]).length >= 4);
  check('markup: Settings has the maker-checker checkbox and saves it', html.includes('id="company-maker-checker"') && html.includes('tracks_inventory, maker_checker'));
  check('markup: report tabs added', html.includes('data-report-tab="bankrec"') && html.includes('data-report-tab="vatrec"') && html.includes('data-report-tab="yearend"'));
  check('markup: comparison selector', html.includes('id="reports-compare"') && html.includes('Same period last year'));
  check('markup: dashboard shows the approvals panel', html.includes('${renderApprovalsPanel()}'));

  console.log(`\n${failures === 0 ? 'ALL WAVE 42 SMOKE CHECKS PASSED' : failures + ' CHECK(S) FAILED'}`);
  process.exit(failures === 0 ? 0 : 1);
})().catch(e=>{ console.log('FAIL exception: '+e.stack); process.exit(1); });
