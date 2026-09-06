with open('index.html', 'r') as f:
    content = f.read()

# 1. Add employeeTasks to state
old = "  employees: [],\n  payrollPayments: [],"
new = "  employees: [],\n  payrollPayments: [],\n  employeeTasks: [],"
assert old in content
content = content.replace(old, new)

# 2. Fetch employee tasks in refreshAll
old = """  const [members, accounts, entries, assets, liabilities, clients, invoices, employees, payments] = await Promise.all([
    sb.from('cc_company_members').select('*').eq('company_id', cid),
    sb.from('cc_accounts').select('*').eq('company_id', cid),
    sb.from('cc_entries').select('*').eq('company_id', cid).order('entry_date', {ascending:false}),
    sb.from('cc_assets').select('*').eq('company_id', cid),
    sb.from('cc_liabilities').select('*').eq('company_id', cid),
    sb.from('cc_clients').select('*').eq('company_id', cid),
    sb.from('cc_invoices').select('*').eq('company_id', cid).order('issue_date', {ascending:false}),
    sb.from('cc_employees').select('*').eq('company_id', cid),
    sb.from('cc_payroll_payments').select('*').eq('company_id', cid).order('pay_date', {ascending:false})
  ]);
  state.members = members.data || [];
  state.accounts = accounts.data || [];
  state.entries = entries.data || [];
  state.assets = assets.data || [];
  state.liabilities = liabilities.data || [];
  state.clients = clients.data || [];
  state.invoices = invoices.data || [];
  state.employees = employees.data || [];
  state.payrollPayments = payments.data || [];
}"""
new = """  const [members, accounts, entries, assets, liabilities, clients, invoices, employees, payments, tasks] = await Promise.all([
    sb.from('cc_company_members').select('*').eq('company_id', cid),
    sb.from('cc_accounts').select('*').eq('company_id', cid),
    sb.from('cc_entries').select('*').eq('company_id', cid).order('entry_date', {ascending:false}),
    sb.from('cc_assets').select('*').eq('company_id', cid),
    sb.from('cc_liabilities').select('*').eq('company_id', cid),
    sb.from('cc_clients').select('*').eq('company_id', cid),
    sb.from('cc_invoices').select('*').eq('company_id', cid).order('issue_date', {ascending:false}),
    sb.from('cc_employees').select('*').eq('company_id', cid),
    sb.from('cc_payroll_payments').select('*').eq('company_id', cid).order('pay_date', {ascending:false}),
    sb.from('cc_employee_tasks').select('*').eq('company_id', cid).order('created_at', {ascending:false})
  ]);
  state.members = members.data || [];
  state.accounts = accounts.data || [];
  state.entries = entries.data || [];
  state.assets = assets.data || [];
  state.liabilities = liabilities.data || [];
  state.clients = clients.data || [];
  state.invoices = invoices.data || [];
  state.employees = employees.data || [];
  state.payrollPayments = payments.data || [];
  state.employeeTasks = tasks.data || [];
}"""
assert old in content
content = content.replace(old, new)

# 3. Dashboard: add a Team & Current Tasks panel
old = """    <div class="panel">
      <h3 style="margin-top:0;">Recent activity</h3>
      ${state.entries.slice(0,8).length ? `<table><thead><tr><th>Date</th><th>Type</th><th>Description</th><th>Amount</th></tr></thead><tbody>
        ${state.entries.slice(0,8).map(e=>`<tr><td>${e.entry_date}</td><td>${e.type}</td><td>${e.description}</td><td>${fmt(e.amount)}</td></tr>`).join('')}
      </tbody></table>` : `<div class="empty">No entries yet.</div>`}
    </div>
  `;
}"""
new = """    <div class="panel">
      <h3 style="margin-top:0;">Recent activity</h3>
      ${state.entries.slice(0,8).length ? `<table><thead><tr><th>Date</th><th>Type</th><th>Description</th><th>Amount</th></tr></thead><tbody>
        ${state.entries.slice(0,8).map(e=>`<tr><td>${e.entry_date}</td><td>${e.type}</td><td>${e.description}</td><td>${fmt(e.amount)}</td></tr>`).join('')}
      </tbody></table>` : `<div class="empty">No entries yet.</div>`}
    </div>
    <div class="panel">
      <h3 style="margin-top:0;">Team &amp; current tasks</h3>
      ${state.employees.length ? `<table><thead><tr><th>Employee</th><th>Role</th><th>Working on</th></tr></thead><tbody>
        ${state.employees.filter(e=>e.active).map(e=>{
          const openTasks = state.employeeTasks.filter(t=>t.employee_id===e.id && t.status!=='done');
          return `<tr><td>${e.name}</td><td>${e.role_title||'—'}</td><td>${openTasks.length ? openTasks.map(t=>`<span class="tag-pill" title="${t.status}">${t.description}</span>`).join(' ') : '<span style="color:var(--muted);">No active task</span>'}</td></tr>`;
        }).join('')}
      </tbody></table>` : `<div class="empty">No employees yet. Add your team under Payroll.</div>`}
    </div>
  `;
}"""
assert old in content
content = content.replace(old, new)

# 4. Payroll: add "+ Assign Task" button per employee row and a Tasks panel
old = """      ${state.employees.length ? `<table><thead><tr><th>Name</th><th>Role</th><th>Salary</th><th>Frequency</th><th>Active</th>${isAdmin()?'<th></th>':''}</tr></thead><tbody>
        ${state.employees.map(e=>`<tr><td>${e.name}</td><td>${e.role_title||'—'}</td><td>${fmt(e.salary)}</td><td>${e.pay_frequency}</td><td>${e.active?'Yes':'No'}</td>
        ${isAdmin()?`<td><button class="btn small secondary" data-pay-employee="${e.id}">Record Payment</button> <button class="btn small danger" data-del-employee="${e.id}">Delete</button></td>`:''}</tr>`).join('')}
      </tbody></table>` : `<div class="empty">No employees yet.</div>`}
    </div>
    <div class="panel">
      <h3 style="margin-top:0;">Recent payments</h3>"""
new = """      ${state.employees.length ? `<table><thead><tr><th>Name</th><th>Role</th><th>Salary</th><th>Frequency</th><th>Active</th>${isAdmin()?'<th></th>':''}</tr></thead><tbody>
        ${state.employees.map(e=>`<tr><td>${e.name}</td><td>${e.role_title||'—'}</td><td>${fmt(e.salary)}</td><td>${e.pay_frequency}</td><td>${e.active?'Yes':'No'}</td>
        ${isAdmin()?`<td><button class="btn small secondary" data-pay-employee="${e.id}">Record Payment</button> <button class="btn small secondary" data-task-employee="${e.id}">Assign Task</button> <button class="btn small danger" data-del-employee="${e.id}">Delete</button></td>`:''}</tr>`).join('')}
      </tbody></table>` : `<div class="empty">No employees yet.</div>`}
    </div>
    <div class="panel">
      <h3 style="margin-top:0;">Tasks</h3>
      ${state.employeeTasks.length ? `<table><thead><tr><th>Employee</th><th>Task</th><th>Status</th>${isAdmin()?'<th></th>':''}</tr></thead><tbody>
        ${state.employeeTasks.map(t=>`<tr><td>${state.employees.find(e=>e.id===t.employee_id)?.name||'—'}</td><td>${t.description}</td><td><span class="status-pill status-${t.status==='done'?'paid':(t.status==='in_progress'?'sent':'draft')}">${t.status.replace('_',' ')}</span></td>
        ${isAdmin()?`<td>
          ${t.status!=='done'?`<button class="btn small secondary" data-complete-task="${t.id}">Mark Done</button>`:''}
          <button class="btn small danger" data-del-task="${t.id}">Delete</button>
        </td>`:''}</tr>`).join('')}
      </tbody></table>` : `<div class="empty">No tasks assigned yet.</div>`}
    </div>
    <div class="panel">
      <h3 style="margin-top:0;">Recent payments</h3>"""
assert old in content
content = content.replace(old, new)

# 5. Add the Assign Task modal alongside the employee/payment modals
old = """    <div class="modal-backdrop hidden" id="payment-modal-backdrop"><div class="modal">
      <button class="close-x" id="payment-modal-close">✕</button>
      <h2>Record Payment</h2>
      <form id="payment-form">
        <input type="hidden" id="payment-employee-id">
        <div class="field"><label>Pay date</label><input type="date" id="payment-date" required></div>
        <div class="field"><label>Gross (R)</label><input type="number" step="0.01" id="payment-gross" required></div>
        <div class="field"><label>Deductions (R)</label><input type="number" step="0.01" id="payment-deductions" value="0"></div>
        <div class="modal-actions"><button type="button" class="btn secondary" id="payment-cancel">Cancel</button><button type="submit" class="btn">Save Payment</button></div>
      </form>
    </div></div>` : ''}
  `;
}"""
new = """    <div class="modal-backdrop hidden" id="payment-modal-backdrop"><div class="modal">
      <button class="close-x" id="payment-modal-close">✕</button>
      <h2>Record Payment</h2>
      <form id="payment-form">
        <input type="hidden" id="payment-employee-id">
        <div class="field"><label>Pay date</label><input type="date" id="payment-date" required></div>
        <div class="field"><label>Gross (R)</label><input type="number" step="0.01" id="payment-gross" required></div>
        <div class="field"><label>Deductions (R)</label><input type="number" step="0.01" id="payment-deductions" value="0"></div>
        <div class="modal-actions"><button type="button" class="btn secondary" id="payment-cancel">Cancel</button><button type="submit" class="btn">Save Payment</button></div>
      </form>
    </div></div>
    <div class="modal-backdrop hidden" id="task-modal-backdrop"><div class="modal">
      <button class="close-x" id="task-modal-close">✕</button>
      <h2>Assign Task</h2>
      <form id="task-form">
        <input type="hidden" id="task-employee-id">
        <div class="field"><label>What are they working on?</label><textarea id="task-description" rows="2" required style="width:100%;"></textarea></div>
        <div class="field"><label>Status</label><select id="task-status"><option value="todo">To do</option><option value="in_progress" selected>In progress</option><option value="done">Done</option></select></div>
        <div class="modal-actions"><button type="button" class="btn secondary" id="task-cancel">Cancel</button><button type="submit" class="btn">Save Task</button></div>
      </form>
    </div></div>` : ''}
  `;
}"""
assert old in content
content = content.replace(old, new)

# 6. Wire up the new task handlers
old = """  document.getElementById('payment-form')?.addEventListener('submit', async (e)=>{
    e.preventDefault();
    const gross = parseFloat(document.getElementById('payment-gross').value);
    const deductions = parseFloat(document.getElementById('payment-deductions').value)||0;
    const {error} = await sb.from('cc_payroll_payments').insert({
      employee_id: document.getElementById('payment-employee-id').value,
      company_id: state.company.id,
      pay_date: document.getElementById('payment-date').value,
      gross, deductions, net: gross - deductions, paid: true
    });
    if(error){ toast(error.message); return; }
    await refreshAll(); render(); toast('Payment recorded.');
  });
}"""
new = """  document.getElementById('payment-form')?.addEventListener('submit', async (e)=>{
    e.preventDefault();
    const gross = parseFloat(document.getElementById('payment-gross').value);
    const deductions = parseFloat(document.getElementById('payment-deductions').value)||0;
    const {error} = await sb.from('cc_payroll_payments').insert({
      employee_id: document.getElementById('payment-employee-id').value,
      company_id: state.company.id,
      pay_date: document.getElementById('payment-date').value,
      gross, deductions, net: gross - deductions, paid: true
    });
    if(error){ toast(error.message); return; }
    await refreshAll(); render(); toast('Payment recorded.');
  });

  const taskBackdrop = document.getElementById('task-modal-backdrop');
  document.querySelectorAll('[data-task-employee]').forEach(btn=>{
    btn.addEventListener('click', ()=>{
      document.getElementById('task-employee-id').value = btn.dataset.taskEmployee;
      document.getElementById('task-description').value = '';
      document.getElementById('task-status').value = 'in_progress';
      taskBackdrop.classList.remove('hidden');
    });
  });
  document.getElementById('task-cancel')?.addEventListener('click', ()=>taskBackdrop.classList.add('hidden'));
  document.getElementById('task-modal-close')?.addEventListener('click', ()=>taskBackdrop.classList.add('hidden'));
  document.getElementById('task-form')?.addEventListener('submit', async (e)=>{
    e.preventDefault();
    const {error} = await sb.from('cc_employee_tasks').insert({
      company_id: state.company.id,
      employee_id: document.getElementById('task-employee-id').value,
      description: document.getElementById('task-description').value.trim(),
      status: document.getElementById('task-status').value
    });
    if(error){ toast(error.message); return; }
    await refreshAll(); render(); toast('Task assigned.');
  });
  document.querySelectorAll('[data-complete-task]').forEach(btn=>{
    btn.addEventListener('click', async ()=>{
      await sb.from('cc_employee_tasks').update({status:'done'}).eq('id', btn.dataset.completeTask);
      await refreshAll(); render();
    });
  });
  document.querySelectorAll('[data-del-task]').forEach(btn=>{
    btn.addEventListener('click', async ()=>{
      if(!confirm('Delete this task?')) return;
      await sb.from('cc_employee_tasks').delete().eq('id', btn.dataset.delTask);
      await refreshAll(); render();
    });
  });
}"""
assert old in content
content = content.replace(old, new)

with open('index.html', 'w') as f:
    f.write(content)

print("patch2 applied")
