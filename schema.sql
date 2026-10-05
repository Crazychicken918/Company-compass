-- Company Compass schema
-- Run this in the Supabase SQL Editor for the Company Compass project.
-- Prefix: cc_
-- Includes: RBAC (owner/admin/viewer/staff with per-module permissions),
-- invoice + credit note approval workflow, Credit Notes module.

-- ============ COMPANIES & MEMBERSHIP ============

create table if not exists cc_companies (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  vat_number text,
  registration_number text,
  created_at timestamptz default now()
);

create table if not exists cc_company_members (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  email text not null,
  role text not null default 'viewer' check (role in ('owner','admin','viewer','staff')),
  status text not null default 'active' check (status in ('pending','active')),
  -- permissions shape for role='staff': { "modules": ["invoices","credit_notes"], "can_approve": false }
  permissions jsonb not null default '{}'::jsonb,
  invited_at timestamptz default now()
);

create unique index if not exists cc_company_members_unique on cc_company_members (company_id, email);

-- ============ ACCOUNTS (bank/savings) ============

create table if not exists cc_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  name text not null,
  type text not null default 'bank' check (type in ('bank','savings')),
  starting_balance numeric not null default 0,
  created_at timestamptz default now()
);

-- ============ CLIENTS ============

create table if not exists cc_clients (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  address text,
  created_at timestamptz default now()
);

-- ============ REVENUE / EXPENSE ENTRIES ============

create table if not exists cc_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  account_id uuid references cc_accounts(id) on delete set null,
  client_id uuid references cc_clients(id) on delete set null,
  type text not null check (type in ('revenue','expense')),
  description text not null,
  amount numeric not null,
  entry_date date not null default current_date,
  is_recurring boolean not null default false,
  recurrence_frequency text,
  recurrence_next_date date,
  tags text[] default '{}',
  vat_applicable boolean not null default false,
  -- only meaningful when type='expense': splits Cost of Sales from Operating
  -- Expenses so the P&L report can compute Gross Profit
  expense_category text not null default 'operating' check (expense_category in ('cost_of_sales','operating')),
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

-- ============ ASSETS / LIABILITIES ============

create table if not exists cc_assets (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  description text not null,
  value numeric not null,
  category text,
  -- current (cash-like / convertible within 12 months) vs fixed/non-current,
  -- used by the Balance Sheet report
  is_current boolean not null default false,
  -- Fixed Asset Register / depreciation (only meaningful for fixed, i.e. !is_current, assets)
  purchase_date date,
  -- 'straight_line' (uses useful_life_months) or 'reducing_balance' (uses depreciation_rate)
  depreciation_method text default 'straight_line' check (depreciation_method is null or depreciation_method in ('straight_line','reducing_balance')),
  useful_life_months integer,
  depreciation_rate numeric, -- annual %, reducing-balance method only
  residual_value numeric not null default 0,
  accumulated_depreciation numeric not null default 0,
  last_depreciation_run date,
  created_at timestamptz default now()
);

create table if not exists cc_liabilities (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  description text not null,
  type text not null default 'other' check (type in ('loan','creditor','other')),
  amount numeric not null,
  interest_rate numeric,
  term_months integer,
  start_date date,
  -- powers payables aging + due-date alerts
  due_date date,
  -- due within 12 months vs long-term, used by the Balance Sheet report
  is_current boolean not null default false,
  created_at timestamptz default now()
);

-- ============ INVOICING ============

create table if not exists cc_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  client_id uuid references cc_clients(id) on delete set null,
  invoice_number text not null,
  issue_date date not null default current_date,
  due_date date,
  status text not null default 'draft' check (status in ('draft','sent','paid','overdue')),
  notes text,
  created_by uuid references auth.users(id),
  approval_status text not null default 'approved' check (approval_status in ('pending','approved','rejected')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  rejection_note text,
  -- recurring invoices
  is_recurring boolean not null default false,
  recurrence_frequency text check (recurrence_frequency in ('weekly','monthly','quarterly','annually')),
  recurrence_next_date date,
  recurrence_end_date date,
  created_at timestamptz default now()
);

create table if not exists cc_invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references cc_invoices(id) on delete cascade,
  description text not null,
  quantity numeric not null default 1,
  unit_price numeric not null default 0,
  vat_applicable boolean not null default true
);

-- ============ CREDIT NOTES ============

create table if not exists cc_credit_notes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  client_id uuid references cc_clients(id) on delete set null,
  invoice_id uuid references cc_invoices(id) on delete set null,
  credit_note_number text not null,
  issue_date date not null default current_date,
  reason text,
  status text not null default 'draft' check (status in ('draft','issued')),
  approval_status text not null default 'approved' check (approval_status in ('pending','approved','rejected')),
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  rejection_note text,
  notes text,
  created_at timestamptz default now()
);

create table if not exists cc_credit_note_items (
  id uuid primary key default gen_random_uuid(),
  credit_note_id uuid not null references cc_credit_notes(id) on delete cascade,
  description text not null,
  quantity numeric not null default 1,
  unit_price numeric not null default 0,
  vat_applicable boolean not null default true
);

-- ============ PAYROLL ============

create table if not exists cc_employees (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  name text not null,
  role_title text,
  salary numeric not null default 0,
  pay_frequency text not null default 'monthly' check (pay_frequency in ('monthly','weekly','biweekly')),
  start_date date,
  active boolean not null default true,
  created_at timestamptz default now()
);

create table if not exists cc_payroll_payments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references cc_employees(id) on delete cascade,
  company_id uuid not null references cc_companies(id) on delete cascade,
  pay_date date not null default current_date,
  gross numeric not null default 0,
  deductions numeric not null default 0,
  net numeric not null default 0,
  paid boolean not null default false,
  created_at timestamptz default now()
);

-- ============ EMPLOYEE TASKS ============

create table if not exists cc_employee_tasks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  employee_id uuid not null references cc_employees(id) on delete cascade,
  description text not null,
  status text not null default 'in_progress' check (status in ('todo','in_progress','done')),
  created_at timestamptz default now()
);

-- ============ HELPER FUNCTIONS ============
-- Returns true if the current user is an active member of the company.
create or replace function cc_is_member(target_company_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from cc_company_members
    where company_id = target_company_id
      and user_id = auth.uid()
      and status = 'active'
  );
$$;

-- Returns true if the current user is owner/admin (management) of the company.
create or replace function cc_is_admin(target_company_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from cc_company_members
    where company_id = target_company_id
      and user_id = auth.uid()
      and status = 'active'
      and role in ('owner','admin')
  );
$$;

-- Returns true if the current user is management, or staff granted this module.
create or replace function cc_has_module(target_company_id uuid, module text)
returns boolean
language sql security definer stable as $$
  select exists (
    select 1 from cc_company_members
    where company_id = target_company_id and user_id = auth.uid() and status = 'active'
      and (
        role in ('owner','admin')
        or (role = 'staff' and (permissions->'modules') ? module)
      )
  );
$$;

-- Returns true if the current user is management, or staff flagged as an approver.
create or replace function cc_can_approve(target_company_id uuid)
returns boolean
language sql security definer stable as $$
  select exists (
    select 1 from cc_company_members
    where company_id = target_company_id and user_id = auth.uid() and status = 'active'
      and (
        role in ('owner','admin')
        or (role = 'staff' and coalesce((permissions->>'can_approve')::boolean, false))
      )
  );
$$;

-- ============ ROW LEVEL SECURITY ============

alter table cc_companies enable row level security;
alter table cc_company_members enable row level security;
alter table cc_accounts enable row level security;
alter table cc_clients enable row level security;
alter table cc_entries enable row level security;
alter table cc_assets enable row level security;
alter table cc_liabilities enable row level security;
alter table cc_invoices enable row level security;
alter table cc_invoice_items enable row level security;
alter table cc_credit_notes enable row level security;
alter table cc_credit_note_items enable row level security;
alter table cc_employees enable row level security;
alter table cc_payroll_payments enable row level security;
alter table cc_employee_tasks enable row level security;

-- cc_companies
create policy "members can view company" on cc_companies for select
  using (cc_is_member(id) or owner_id = auth.uid());
create policy "owner can insert company" on cc_companies for insert
  with check (owner_id = auth.uid());
create policy "admin can update company" on cc_companies for update
  using (cc_is_admin(id));

-- cc_company_members
create policy "members can view membership" on cc_company_members for select
  using (cc_is_member(company_id) or email = auth.jwt() ->> 'email');
create policy "admin can manage members insert" on cc_company_members for insert
  with check (cc_is_admin(company_id) or not exists (select 1 from cc_company_members m where m.company_id = cc_company_members.company_id));
create policy "admin can manage members update" on cc_company_members for update
  using (cc_is_admin(company_id) or user_id = auth.uid());
create policy "admin can manage members delete" on cc_company_members for delete
  using (cc_is_admin(company_id));

-- accounts: management only (no module for this yet)
create policy "members select accounts" on cc_accounts for select using (cc_is_member(company_id));
create policy "admin write accounts" on cc_accounts for insert with check (cc_is_admin(company_id));
create policy "admin update accounts" on cc_accounts for update using (cc_is_admin(company_id));
create policy "admin delete accounts" on cc_accounts for delete using (cc_is_admin(company_id));

-- clients: module-scoped
create policy "members select clients" on cc_clients for select using (cc_is_member(company_id));
create policy "scoped write clients" on cc_clients for insert with check (cc_has_module(company_id, 'clients'));
create policy "scoped update clients" on cc_clients for update using (cc_has_module(company_id, 'clients'));
create policy "scoped delete clients" on cc_clients for delete using (cc_has_module(company_id, 'clients'));

-- entries (revenue/expenses): module-scoped by type
create policy "members select entries" on cc_entries for select using (cc_is_member(company_id));
create policy "scoped write entries" on cc_entries for insert with check (
  (type = 'revenue' and cc_has_module(company_id, 'revenue')) or (type = 'expense' and cc_has_module(company_id, 'expenses'))
);
create policy "scoped update entries" on cc_entries for update using (
  (type = 'revenue' and cc_has_module(company_id, 'revenue')) or (type = 'expense' and cc_has_module(company_id, 'expenses'))
);
create policy "scoped delete entries" on cc_entries for delete using (
  (type = 'revenue' and cc_has_module(company_id, 'revenue')) or (type = 'expense' and cc_has_module(company_id, 'expenses'))
);

-- assets: module-scoped
create policy "members select assets" on cc_assets for select using (cc_is_member(company_id));
create policy "scoped write assets" on cc_assets for insert with check (cc_has_module(company_id, 'assets'));
create policy "scoped update assets" on cc_assets for update using (cc_has_module(company_id, 'assets'));
create policy "scoped delete assets" on cc_assets for delete using (cc_has_module(company_id, 'assets'));

-- liabilities: module-scoped
create policy "members select liabilities" on cc_liabilities for select using (cc_is_member(company_id));
create policy "scoped write liabilities" on cc_liabilities for insert with check (cc_has_module(company_id, 'liabilities'));
create policy "scoped update liabilities" on cc_liabilities for update using (cc_has_module(company_id, 'liabilities'));
create policy "scoped delete liabilities" on cc_liabilities for delete using (cc_has_module(company_id, 'liabilities'));

-- invoices: module-scoped create + approval workflow
create policy "members select invoices" on cc_invoices for select using (cc_is_member(company_id));
create policy "scoped write invoices" on cc_invoices for insert with check (cc_has_module(company_id, 'invoices'));
create policy "management update invoices" on cc_invoices for update using (cc_can_approve(company_id));
create policy "creator edit pending invoice" on cc_invoices for update
  using (created_by = auth.uid() and approval_status = 'pending')
  with check (created_by = auth.uid() and approval_status = 'pending');
create policy "management delete invoices" on cc_invoices for delete using (cc_can_approve(company_id));
create policy "creator delete pending invoice" on cc_invoices for delete using (created_by = auth.uid() and approval_status = 'pending');

create policy "members select invoice items" on cc_invoice_items for select using (
  cc_is_member((select company_id from cc_invoices where id = invoice_id))
);
create policy "scoped write invoice items" on cc_invoice_items for insert with check (
  cc_has_module((select company_id from cc_invoices where id = invoice_id), 'invoices')
);
create policy "scoped update invoice items" on cc_invoice_items for update using (
  cc_can_approve((select company_id from cc_invoices where id = invoice_id))
  or exists (select 1 from cc_invoices i where i.id = invoice_id and i.created_by = auth.uid() and i.approval_status = 'pending')
);
create policy "scoped delete invoice items" on cc_invoice_items for delete using (
  cc_can_approve((select company_id from cc_invoices where id = invoice_id))
  or exists (select 1 from cc_invoices i where i.id = invoice_id and i.created_by = auth.uid() and i.approval_status = 'pending')
);

-- credit notes: module-scoped create + approval workflow (mirrors invoices)
create policy "members select credit notes" on cc_credit_notes for select using (cc_is_member(company_id));
create policy "scoped write credit notes" on cc_credit_notes for insert with check (cc_has_module(company_id, 'credit_notes'));
create policy "management update credit notes" on cc_credit_notes for update using (cc_can_approve(company_id));
create policy "creator edit pending credit note" on cc_credit_notes for update
  using (created_by = auth.uid() and approval_status = 'pending')
  with check (created_by = auth.uid() and approval_status = 'pending');
create policy "management delete credit notes" on cc_credit_notes for delete using (cc_can_approve(company_id));
create policy "creator delete pending credit note" on cc_credit_notes for delete using (created_by = auth.uid() and approval_status = 'pending');

create policy "members select credit note items" on cc_credit_note_items for select using (
  cc_is_member((select company_id from cc_credit_notes where id = credit_note_id))
);
create policy "scoped write credit note items" on cc_credit_note_items for insert with check (
  cc_has_module((select company_id from cc_credit_notes where id = credit_note_id), 'credit_notes')
);
create policy "scoped update credit note items" on cc_credit_note_items for update using (
  cc_can_approve((select company_id from cc_credit_notes where id = credit_note_id))
  or exists (select 1 from cc_credit_notes c where c.id = credit_note_id and c.created_by = auth.uid() and c.approval_status = 'pending')
);
create policy "scoped delete credit note items" on cc_credit_note_items for delete using (
  cc_can_approve((select company_id from cc_credit_notes where id = credit_note_id))
  or exists (select 1 from cc_credit_notes c where c.id = credit_note_id and c.created_by = auth.uid() and c.approval_status = 'pending')
);

-- employees / payroll / employee tasks: module-scoped ('payroll')
create policy "members select employees" on cc_employees for select using (cc_is_member(company_id));
create policy "scoped write employees" on cc_employees for insert with check (cc_has_module(company_id, 'payroll'));
create policy "scoped update employees" on cc_employees for update using (cc_has_module(company_id, 'payroll'));
create policy "scoped delete employees" on cc_employees for delete using (cc_has_module(company_id, 'payroll'));

create policy "members select payroll" on cc_payroll_payments for select using (cc_is_member(company_id));
create policy "scoped write payroll" on cc_payroll_payments for insert with check (cc_has_module(company_id, 'payroll'));
create policy "scoped update payroll" on cc_payroll_payments for update using (cc_has_module(company_id, 'payroll'));
create policy "scoped delete payroll" on cc_payroll_payments for delete using (cc_has_module(company_id, 'payroll'));

create policy "members select employee tasks" on cc_employee_tasks for select using (cc_is_member(company_id));
create policy "scoped write employee tasks" on cc_employee_tasks for insert with check (cc_has_module(company_id, 'payroll'));
create policy "scoped update employee tasks" on cc_employee_tasks for update using (cc_has_module(company_id, 'payroll'));
create policy "scoped delete employee tasks" on cc_employee_tasks for delete using (cc_has_module(company_id, 'payroll'));

-- ============ BUDGET VS ACTUAL ============
create table if not exists cc_budgets (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  tag text not null,
  type text not null default 'expense' check (type in ('revenue','expense')),
  monthly_amount numeric not null,
  created_at timestamptz default now(),
  unique (company_id, tag, type)
);
alter table cc_budgets enable row level security;
create policy "members select budgets" on cc_budgets for select using (cc_is_member(company_id));
create policy "admin write budgets" on cc_budgets for insert with check (cc_is_admin(company_id));
create policy "admin update budgets" on cc_budgets for update using (cc_is_admin(company_id));
create policy "admin delete budgets" on cc_budgets for delete using (cc_is_admin(company_id));

-- ============ SIGNED FINANCIAL STATEMENTS ============
create table if not exists cc_financial_statements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  period_label text not null,
  file_path text not null,
  file_name text,
  notes text,
  uploaded_by uuid references auth.users(id),
  created_at timestamptz default now()
);
alter table cc_financial_statements enable row level security;
create policy "members select financial statements" on cc_financial_statements for select using (cc_is_member(company_id));
create policy "admin write financial statements" on cc_financial_statements for insert with check (cc_is_admin(company_id));
create policy "admin delete financial statements" on cc_financial_statements for delete using (cc_is_admin(company_id));

-- storage bucket for signed financials (private) — path convention: <company_id>/<filename>
insert into storage.buckets (id, name, public)
values ('financials', 'financials', false)
on conflict (id) do nothing;

create policy "members view financials files" on storage.objects for select
  using (bucket_id = 'financials' and cc_is_member((storage.foldername(name))[1]::uuid));
create policy "admin upload financials files" on storage.objects for insert
  with check (bucket_id = 'financials' and cc_is_admin((storage.foldername(name))[1]::uuid));
create policy "admin delete financials files" on storage.objects for delete
  using (bucket_id = 'financials' and cc_is_admin((storage.foldername(name))[1]::uuid));

-- ============ SCENARIO PLANNER (what-if: supplier comparisons, loans, general) ============
create table if not exists cc_scenarios (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  name text not null,
  category text not null default 'general' check (category in ('general','supplier','loan')),
  discount_rate numeric not null default 10,
  period_unit text not null default 'month' check (period_unit in ('month','quarter','year')),
  params jsonb not null default '{}'::jsonb,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table cc_scenarios enable row level security;
create policy "management select scenarios" on cc_scenarios for select using (cc_is_admin(company_id) or cc_can_approve(company_id));
create policy "management write scenarios" on cc_scenarios for insert with check (cc_is_admin(company_id) or cc_can_approve(company_id));
create policy "management update scenarios" on cc_scenarios for update using (cc_is_admin(company_id) or cc_can_approve(company_id));
create policy "management delete scenarios" on cc_scenarios for delete using (cc_is_admin(company_id) or cc_can_approve(company_id));

create table if not exists cc_scenario_cashflows (
  id uuid primary key default gen_random_uuid(),
  scenario_id uuid not null references cc_scenarios(id) on delete cascade,
  period_number integer not null,
  label text,
  amount numeric not null default 0,
  created_at timestamptz not null default now()
);
alter table cc_scenario_cashflows enable row level security;
create policy "management select scenario cashflows" on cc_scenario_cashflows for select using (
  exists (select 1 from cc_scenarios s where s.id = scenario_id and (cc_is_admin(s.company_id) or cc_can_approve(s.company_id)))
);
create policy "management write scenario cashflows" on cc_scenario_cashflows for insert with check (
  exists (select 1 from cc_scenarios s where s.id = scenario_id and (cc_is_admin(s.company_id) or cc_can_approve(s.company_id)))
);
create policy "management update scenario cashflows" on cc_scenario_cashflows for update using (
  exists (select 1 from cc_scenarios s where s.id = scenario_id and (cc_is_admin(s.company_id) or cc_can_approve(s.company_id)))
);
create policy "management delete scenario cashflows" on cc_scenario_cashflows for delete using (
  exists (select 1 from cc_scenarios s where s.id = scenario_id and (cc_is_admin(s.company_id) or cc_can_approve(s.company_id)))
);
-- Wave 22: Supplier Invoices (AP subledger), customer invoice payment
-- allocation, supplier credit notes, invoice-linked accrual entries, and
-- company invoice branding (logo). Idempotent — safe to run more than once.

-- ============ SUPPLIERS ============
create table if not exists cc_suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  address text,
  created_at timestamptz default now()
);

-- ============ SUPPLIER INVOICES (bills) ============
create table if not exists cc_supplier_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  supplier_id uuid references cc_suppliers(id) on delete set null,
  bill_number text not null,
  issue_date date not null default current_date,
  due_date date,
  status text not null default 'unpaid' check (status in ('unpaid','partially_paid','paid')),
  -- splits Cost of Sales from Operating Expenses, same convention as cc_entries
  expense_category text not null default 'operating' check (expense_category in ('cost_of_sales','operating')),
  notes text,
  created_by uuid references auth.users(id),
  approval_status text not null default 'approved' check (approval_status in ('pending','approved','rejected')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  rejection_note text,
  created_at timestamptz default now()
);

create table if not exists cc_supplier_invoice_items (
  id uuid primary key default gen_random_uuid(),
  supplier_invoice_id uuid not null references cc_supplier_invoices(id) on delete cascade,
  description text not null,
  quantity numeric not null default 1,
  unit_price numeric not null default 0,
  vat_applicable boolean not null default true
);

-- actual cash paid against a supplier invoice — feeds Cash Flow and the AP balance
create table if not exists cc_supplier_invoice_payments (
  id uuid primary key default gen_random_uuid(),
  supplier_invoice_id uuid not null references cc_supplier_invoices(id) on delete cascade,
  company_id uuid not null references cc_companies(id) on delete cascade,
  payment_date date not null default current_date,
  amount numeric not null,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

-- ============ SUPPLIER CREDIT NOTES (mirrors customer credit notes) ============
create table if not exists cc_supplier_credit_notes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  supplier_id uuid references cc_suppliers(id) on delete set null,
  supplier_invoice_id uuid references cc_supplier_invoices(id) on delete set null,
  credit_note_number text not null,
  issue_date date not null default current_date,
  reason text,
  status text not null default 'draft' check (status in ('draft','issued')),
  approval_status text not null default 'approved' check (approval_status in ('pending','approved','rejected')),
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  rejection_note text,
  notes text,
  created_at timestamptz default now()
);

create table if not exists cc_supplier_credit_note_items (
  id uuid primary key default gen_random_uuid(),
  supplier_credit_note_id uuid not null references cc_supplier_credit_notes(id) on delete cascade,
  description text not null,
  quantity numeric not null default 1,
  unit_price numeric not null default 0,
  vat_applicable boolean not null default true
);

-- ============ CUSTOMER INVOICE PAYMENTS (accounts receivable subledger) ============
create table if not exists cc_invoice_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references cc_invoices(id) on delete cascade,
  company_id uuid not null references cc_companies(id) on delete cascade,
  payment_date date not null default current_date,
  amount numeric not null,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

-- ============ ACCRUAL LINKAGE: revenue/expense entries auto-created from invoices ============
-- When set, the entry is an accrual recognized at invoice issue/approval time, not an
-- actual cash movement — Cash Flow and the Balance Sheet's cash figure exclude it and
-- use the real cc_invoice_payments / cc_supplier_invoice_payments instead (same pattern
-- already used to exclude non-cash depreciation).
alter table cc_entries add column if not exists source_invoice_id uuid references cc_invoices(id) on delete cascade;
alter table cc_entries add column if not exists source_supplier_invoice_id uuid references cc_supplier_invoices(id) on delete cascade;

-- ============ COMPANY INVOICE BRANDING ============
alter table cc_companies add column if not exists logo_data_url text;

-- ============ ROW LEVEL SECURITY ============
alter table cc_suppliers enable row level security;
alter table cc_supplier_invoices enable row level security;
alter table cc_supplier_invoice_items enable row level security;
alter table cc_supplier_invoice_payments enable row level security;
alter table cc_supplier_credit_notes enable row level security;
alter table cc_supplier_credit_note_items enable row level security;
alter table cc_invoice_payments enable row level security;

-- suppliers: module-scoped ('supplier_invoices')
drop policy if exists "members select suppliers" on cc_suppliers;
create policy "members select suppliers" on cc_suppliers for select using (cc_is_member(company_id));
drop policy if exists "scoped write suppliers" on cc_suppliers;
create policy "scoped write suppliers" on cc_suppliers for insert with check (cc_has_module(company_id, 'supplier_invoices'));
drop policy if exists "scoped update suppliers" on cc_suppliers;
create policy "scoped update suppliers" on cc_suppliers for update using (cc_has_module(company_id, 'supplier_invoices'));
drop policy if exists "scoped delete suppliers" on cc_suppliers;
create policy "scoped delete suppliers" on cc_suppliers for delete using (cc_has_module(company_id, 'supplier_invoices'));

-- supplier invoices: module-scoped create + approval workflow (mirrors cc_invoices)
drop policy if exists "members select supplier invoices" on cc_supplier_invoices;
create policy "members select supplier invoices" on cc_supplier_invoices for select using (cc_is_member(company_id));
drop policy if exists "scoped write supplier invoices" on cc_supplier_invoices;
create policy "scoped write supplier invoices" on cc_supplier_invoices for insert with check (cc_has_module(company_id, 'supplier_invoices'));
drop policy if exists "management update supplier invoices" on cc_supplier_invoices;
create policy "management update supplier invoices" on cc_supplier_invoices for update using (cc_can_approve(company_id));
drop policy if exists "creator edit pending supplier invoice" on cc_supplier_invoices;
create policy "creator edit pending supplier invoice" on cc_supplier_invoices for update
  using (created_by = auth.uid() and approval_status = 'pending')
  with check (created_by = auth.uid() and approval_status = 'pending');
drop policy if exists "management delete supplier invoices" on cc_supplier_invoices;
create policy "management delete supplier invoices" on cc_supplier_invoices for delete using (cc_can_approve(company_id));
drop policy if exists "creator delete pending supplier invoice" on cc_supplier_invoices;
create policy "creator delete pending supplier invoice" on cc_supplier_invoices for delete using (created_by = auth.uid() and approval_status = 'pending');

drop policy if exists "members select supplier invoice items" on cc_supplier_invoice_items;
create policy "members select supplier invoice items" on cc_supplier_invoice_items for select using (
  cc_is_member((select company_id from cc_supplier_invoices where id = supplier_invoice_id))
);
drop policy if exists "scoped write supplier invoice items" on cc_supplier_invoice_items;
create policy "scoped write supplier invoice items" on cc_supplier_invoice_items for insert with check (
  cc_has_module((select company_id from cc_supplier_invoices where id = supplier_invoice_id), 'supplier_invoices')
);
drop policy if exists "scoped update supplier invoice items" on cc_supplier_invoice_items;
create policy "scoped update supplier invoice items" on cc_supplier_invoice_items for update using (
  cc_can_approve((select company_id from cc_supplier_invoices where id = supplier_invoice_id))
  or exists (select 1 from cc_supplier_invoices b where b.id = supplier_invoice_id and b.created_by = auth.uid() and b.approval_status = 'pending')
);
drop policy if exists "scoped delete supplier invoice items" on cc_supplier_invoice_items;
create policy "scoped delete supplier invoice items" on cc_supplier_invoice_items for delete using (
  cc_can_approve((select company_id from cc_supplier_invoices where id = supplier_invoice_id))
  or exists (select 1 from cc_supplier_invoices b where b.id = supplier_invoice_id and b.created_by = auth.uid() and b.approval_status = 'pending')
);

-- supplier invoice payments: module-scoped, plain CRUD (no approval workflow — same as payroll payments)
drop policy if exists "members select supplier invoice payments" on cc_supplier_invoice_payments;
create policy "members select supplier invoice payments" on cc_supplier_invoice_payments for select using (cc_is_member(company_id));
drop policy if exists "scoped write supplier invoice payments" on cc_supplier_invoice_payments;
create policy "scoped write supplier invoice payments" on cc_supplier_invoice_payments for insert with check (cc_has_module(company_id, 'supplier_invoices'));
drop policy if exists "scoped update supplier invoice payments" on cc_supplier_invoice_payments;
create policy "scoped update supplier invoice payments" on cc_supplier_invoice_payments for update using (cc_has_module(company_id, 'supplier_invoices'));
drop policy if exists "scoped delete supplier invoice payments" on cc_supplier_invoice_payments;
create policy "scoped delete supplier invoice payments" on cc_supplier_invoice_payments for delete using (cc_has_module(company_id, 'supplier_invoices'));

-- supplier credit notes: module-scoped create + approval workflow (mirrors cc_credit_notes)
drop policy if exists "members select supplier credit notes" on cc_supplier_credit_notes;
create policy "members select supplier credit notes" on cc_supplier_credit_notes for select using (cc_is_member(company_id));
drop policy if exists "scoped write supplier credit notes" on cc_supplier_credit_notes;
create policy "scoped write supplier credit notes" on cc_supplier_credit_notes for insert with check (cc_has_module(company_id, 'supplier_invoices'));
drop policy if exists "management update supplier credit notes" on cc_supplier_credit_notes;
create policy "management update supplier credit notes" on cc_supplier_credit_notes for update using (cc_can_approve(company_id));
drop policy if exists "creator edit pending supplier credit note" on cc_supplier_credit_notes;
create policy "creator edit pending supplier credit note" on cc_supplier_credit_notes for update
  using (created_by = auth.uid() and approval_status = 'pending')
  with check (created_by = auth.uid() and approval_status = 'pending');
drop policy if exists "management delete supplier credit notes" on cc_supplier_credit_notes;
create policy "management delete supplier credit notes" on cc_supplier_credit_notes for delete using (cc_can_approve(company_id));
drop policy if exists "creator delete pending supplier credit note" on cc_supplier_credit_notes;
create policy "creator delete pending supplier credit note" on cc_supplier_credit_notes for delete using (created_by = auth.uid() and approval_status = 'pending');

drop policy if exists "members select supplier credit note items" on cc_supplier_credit_note_items;
create policy "members select supplier credit note items" on cc_supplier_credit_note_items for select using (
  cc_is_member((select company_id from cc_supplier_credit_notes where id = supplier_credit_note_id))
);
drop policy if exists "scoped write supplier credit note items" on cc_supplier_credit_note_items;
create policy "scoped write supplier credit note items" on cc_supplier_credit_note_items for insert with check (
  cc_has_module((select company_id from cc_supplier_credit_notes where id = supplier_credit_note_id), 'supplier_invoices')
);
drop policy if exists "scoped update supplier credit note items" on cc_supplier_credit_note_items;
create policy "scoped update supplier credit note items" on cc_supplier_credit_note_items for update using (
  cc_can_approve((select company_id from cc_supplier_credit_notes where id = supplier_credit_note_id))
  or exists (select 1 from cc_supplier_credit_notes c where c.id = supplier_credit_note_id and c.created_by = auth.uid() and c.approval_status = 'pending')
);
drop policy if exists "scoped delete supplier credit note items" on cc_supplier_credit_note_items;
create policy "scoped delete supplier credit note items" on cc_supplier_credit_note_items for delete using (
  cc_can_approve((select company_id from cc_supplier_credit_notes where id = supplier_credit_note_id))
  or exists (select 1 from cc_supplier_credit_notes c where c.id = supplier_credit_note_id and c.created_by = auth.uid() and c.approval_status = 'pending')
);

-- customer invoice payments: module-scoped ('invoices'), plain CRUD
drop policy if exists "members select invoice payments" on cc_invoice_payments;
create policy "members select invoice payments" on cc_invoice_payments for select using (cc_is_member(company_id));
drop policy if exists "scoped write invoice payments" on cc_invoice_payments;
create policy "scoped write invoice payments" on cc_invoice_payments for insert with check (cc_has_module(company_id, 'invoices'));
drop policy if exists "scoped update invoice payments" on cc_invoice_payments;
create policy "scoped update invoice payments" on cc_invoice_payments for update using (cc_has_module(company_id, 'invoices'));
drop policy if exists "scoped delete invoice payments" on cc_invoice_payments;
create policy "scoped delete invoice payments" on cc_invoice_payments for delete using (cc_has_module(company_id, 'invoices'));

-- ---------- verify ----------
select tablename, count(*) as policy_count
from pg_policies
where tablename in ('cc_suppliers','cc_supplier_invoices','cc_supplier_invoice_items','cc_supplier_invoice_payments','cc_supplier_credit_notes','cc_supplier_credit_note_items','cc_invoice_payments')
group by tablename
order by tablename;

-- ============ WAVE 23: VAT REGISTRATION STATUS & COMPANY ADDRESS ============
-- Whether the company is registered for VAT gates whether VAT can be charged on
-- customer-facing documents (invoices, credit notes) — see weAreVatRegistered()
-- in app code. Supplier documents are unaffected (VAT reflects the supplier's
-- own registration status, which we don't track). Company address is required
-- on tax invoices by SARS.
alter table cc_companies add column if not exists vat_registered boolean not null default true;
alter table cc_companies add column if not exists address text;

-- ============ WAVE 24: PAYE/UIF/SDL, leave balances, payslip breakdown, IRP5 ============

-- Employee tax profile fields
alter table cc_employees add column if not exists id_number text;
alter table cc_employees add column if not exists tax_number text;
alter table cc_employees add column if not exists date_of_birth date;
alter table cc_employees add column if not exists travel_allowance numeric not null default 0;
alter table cc_employees add column if not exists retirement_contribution numeric not null default 0;
alter table cc_employees add column if not exists medical_aid_contribution numeric not null default 0;
alter table cc_employees add column if not exists medical_aid_dependants integer not null default 0;

-- Payslip breakdown columns on cc_payroll_payments (in addition to existing gross/deductions/net)
alter table cc_payroll_payments add column if not exists basic_salary numeric not null default 0;
alter table cc_payroll_payments add column if not exists travel_allowance numeric not null default 0;
alter table cc_payroll_payments add column if not exists bonus numeric not null default 0;
alter table cc_payroll_payments add column if not exists commission numeric not null default 0;
alter table cc_payroll_payments add column if not exists retirement_deduction numeric not null default 0;
alter table cc_payroll_payments add column if not exists medical_deduction numeric not null default 0;
alter table cc_payroll_payments add column if not exists paye numeric not null default 0;
alter table cc_payroll_payments add column if not exists uif_employee numeric not null default 0;
alter table cc_payroll_payments add column if not exists uif_employer numeric not null default 0;
alter table cc_payroll_payments add column if not exists medical_credit numeric not null default 0;
alter table cc_payroll_payments add column if not exists other_deduction numeric not null default 0;
alter table cc_payroll_payments add column if not exists other_deduction_note text;

-- Leave balances: one row per employee per leave type, set/adjusted directly by an admin
create table if not exists cc_leave_balances (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  employee_id uuid not null references cc_employees(id) on delete cascade,
  leave_type text not null check (leave_type in ('annual','sick','compassionate','study')),
  balance_days numeric not null default 0,
  updated_at timestamptz default now(),
  unique(employee_id, leave_type)
);

-- Leave entries: an audit log of leave taken (or balance adjustments), decrementing/adjusting the balance
create table if not exists cc_leave_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  employee_id uuid not null references cc_employees(id) on delete cascade,
  leave_type text not null check (leave_type in ('annual','sick','compassionate','study')),
  start_date date not null,
  end_date date not null,
  days numeric not null,
  notes text,
  created_by uuid,
  created_at timestamptz default now()
);

alter table cc_leave_balances enable row level security;
alter table cc_leave_entries enable row level security;

drop policy if exists "members select leave balances" on cc_leave_balances;
create policy "members select leave balances" on cc_leave_balances for select using (cc_is_member(company_id));
drop policy if exists "admin write leave balances" on cc_leave_balances;
create policy "admin write leave balances" on cc_leave_balances for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update leave balances" on cc_leave_balances;
create policy "admin update leave balances" on cc_leave_balances for update using (cc_is_admin(company_id));
drop policy if exists "admin delete leave balances" on cc_leave_balances;
create policy "admin delete leave balances" on cc_leave_balances for delete using (cc_is_admin(company_id));

drop policy if exists "members select leave entries" on cc_leave_entries;
create policy "members select leave entries" on cc_leave_entries for select using (cc_is_member(company_id));
drop policy if exists "admin write leave entries" on cc_leave_entries;
create policy "admin write leave entries" on cc_leave_entries for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update leave entries" on cc_leave_entries;
create policy "admin update leave entries" on cc_leave_entries for update using (cc_is_admin(company_id));
drop policy if exists "admin delete leave entries" on cc_leave_entries;
create policy "admin delete leave entries" on cc_leave_entries for delete using (cc_is_admin(company_id));

-- ---------- verify ----------
select tablename, count(*) as policy_count from pg_policies where tablename in ('cc_leave_balances','cc_leave_entries') group by tablename order by tablename;

-- ============ WAVE 25: task notes + restricted tab access + employee-linked logins ============

-- Link a login (cc_company_members) to a payroll employee record, so a restricted staff
-- member can be shown just their own tasks on the Tasks tab.
alter table cc_company_members add column if not exists employee_id uuid references cc_employees(id) on delete set null;

-- An append-only note log against a task (employees can add notes as they work through it).
create table if not exists cc_task_notes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  task_id uuid not null references cc_employee_tasks(id) on delete cascade,
  author_email text,
  note text not null,
  created_at timestamptz default now()
);
alter table cc_task_notes enable row level security;

drop policy if exists "members select task notes" on cc_task_notes;
create policy "members select task notes" on cc_task_notes for select using (cc_is_member(company_id));
drop policy if exists "members insert task notes" on cc_task_notes;
create policy "members insert task notes" on cc_task_notes for insert with check (cc_is_member(company_id));
drop policy if exists "author or admin delete task notes" on cc_task_notes;
create policy "author or admin delete task notes" on cc_task_notes for delete using (
  cc_is_admin(company_id) or author_email = auth.jwt() ->> 'email'
);

-- Returns the employee_id linked to the calling user's active membership of a company, or
-- null if their login isn't linked to an employee record. Used to scope a restricted staff
-- member's Tasks-tab access to just their own tasks.
create or replace function cc_my_employee_id(target_company_id uuid)
returns uuid
language sql
security definer
stable
as $$
  select employee_id from cc_company_members
  where company_id = target_company_id and user_id = auth.uid() and status = 'active'
  limit 1;
$$;

-- Additive to the existing "scoped update employee tasks" (payroll-module) policy: lets an
-- employee update the status of their own task even without payroll module access.
drop policy if exists "own task status update" on cc_employee_tasks;
create policy "own task status update" on cc_employee_tasks for update using (
  employee_id = cc_my_employee_id(company_id)
);

-- ---------- verify ----------
select tablename, count(*) as policy_count from pg_policies where tablename in ('cc_task_notes','cc_employee_tasks') group by tablename order by tablename;

-- ============ WAVE 26: bulk IRP5 export for SARS e@syFile Employer ============

-- SARS statutory reference numbers + payroll contact person, needed on the e@syFile
-- employer header block of the bulk IRP5 import CSV.
alter table cc_companies add column if not exists paye_reference_number text;
alter table cc_companies add column if not exists sdl_reference_number text;
alter table cc_companies add column if not exists uif_reference_number text;
alter table cc_companies add column if not exists contact_first_name text;
alter table cc_companies add column if not exists contact_surname text;
alter table cc_companies add column if not exists contact_email text;
alter table cc_companies add column if not exists contact_phone text;

-- Surname / first names split, needed for the employee identification fields on the
-- IRP5 certificate block of the e@syFile import CSV (existing "name" field stays as-is
-- for display elsewhere in the app).
alter table cc_employees add column if not exists surname text;
alter table cc_employees add column if not exists first_names text;

-- ---------- verify ----------
select column_name from information_schema.columns where table_name = 'cc_companies' and column_name in ('paye_reference_number','sdl_reference_number','uif_reference_number','contact_first_name','contact_surname','contact_email','contact_phone');
select column_name from information_schema.columns where table_name = 'cc_employees' and column_name in ('surname','first_names');

-- ============ WAVE 27: attachments, audit log, CSV export/import, bank reconciliation, VAT201/reg-number quick wins ============

-- ---------- Quick wins ----------
-- Company registration number field already existed on cc_companies; VAT category for VAT201 period scoping.
alter table cc_companies add column if not exists vat_category text not null default 'A' check (vat_category in ('A','B'));

-- ---------- Document/receipt attachments ----------
-- storage bucket for receipts/documents attached to revenue, expense, invoice and supplier-invoice records.
insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

drop policy if exists "members view attachment files" on storage.objects;
create policy "members view attachment files" on storage.objects for select
  using (bucket_id = 'documents' and cc_is_member((storage.foldername(name))[1]::uuid));
drop policy if exists "members upload attachment files" on storage.objects;
create policy "members upload attachment files" on storage.objects for insert
  with check (bucket_id = 'documents' and cc_is_member((storage.foldername(name))[1]::uuid));
drop policy if exists "admin delete attachment files" on storage.objects;
create policy "admin delete attachment files" on storage.objects for delete
  using (bucket_id = 'documents' and cc_is_admin((storage.foldername(name))[1]::uuid));

create table if not exists cc_attachments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  entity_type text not null check (entity_type in ('revenue','expense','invoice','supplier_invoice')),
  entity_id uuid not null,
  file_path text not null,
  file_name text not null,
  uploaded_by text,
  created_at timestamptz default now()
);
alter table cc_attachments enable row level security;

drop policy if exists "members select attachments" on cc_attachments;
create policy "members select attachments" on cc_attachments for select using (cc_is_member(company_id));
drop policy if exists "members insert attachments" on cc_attachments;
create policy "members insert attachments" on cc_attachments for insert with check (cc_is_member(company_id));
drop policy if exists "admin delete attachments" on cc_attachments;
create policy "admin delete attachments" on cc_attachments for delete using (cc_is_admin(company_id));

-- ---------- Activity/audit log ----------
create table if not exists cc_audit_log (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  user_email text,
  action text not null check (action in ('create','update','delete')),
  entity_type text not null,
  entity_id uuid,
  summary text,
  created_at timestamptz default now()
);
alter table cc_audit_log enable row level security;

drop policy if exists "admin select audit log" on cc_audit_log;
create policy "admin select audit log" on cc_audit_log for select using (cc_is_admin(company_id));
drop policy if exists "members insert audit log" on cc_audit_log;
create policy "members insert audit log" on cc_audit_log for insert with check (cc_is_member(company_id));

-- ---------- Bank statement import + reconciliation ----------
create table if not exists cc_bank_transactions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  tx_date date not null,
  description text,
  amount numeric not null,
  status text not null default 'unmatched' check (status in ('unmatched','matched','ignored')),
  matched_entry_type text,
  matched_entry_id uuid,
  created_at timestamptz default now()
);
alter table cc_bank_transactions enable row level security;

drop policy if exists "members select bank transactions" on cc_bank_transactions;
create policy "members select bank transactions" on cc_bank_transactions for select using (cc_is_member(company_id));
drop policy if exists "members insert bank transactions" on cc_bank_transactions;
create policy "members insert bank transactions" on cc_bank_transactions for insert with check (cc_is_member(company_id));
drop policy if exists "members update bank transactions" on cc_bank_transactions;
create policy "members update bank transactions" on cc_bank_transactions for update using (cc_is_member(company_id));
drop policy if exists "admin delete bank transactions" on cc_bank_transactions;
create policy "admin delete bank transactions" on cc_bank_transactions for delete using (cc_is_admin(company_id));

-- ---------- verify ----------
select column_name from information_schema.columns where table_name = 'cc_companies' and column_name in ('vat_category');
select tablename, count(*) as policy_count from pg_policies where tablename in ('cc_attachments','cc_audit_log','cc_bank_transactions') group by tablename order by tablename;
select id, public from storage.buckets where id = 'documents';

-- ============ WAVE 28: supplier credit note attachments + accounting period lock ============

-- ---------- Supplier credit notes can now carry attachments too (documents received from suppliers) ----------
alter table cc_attachments drop constraint if exists cc_attachments_entity_type_check;
alter table cc_attachments add constraint cc_attachments_entity_type_check
  check (entity_type in ('revenue','expense','invoice','supplier_invoice','supplier_credit_note'));

-- ---------- Accounting period lock ----------
-- Single "locked through" cutoff date per company (Xero/QuickBooks-style closing date).
-- Anything dated on or before it can't be created or deleted for the core transaction tables.
alter table cc_companies add column if not exists locked_through_date date;

create or replace function cc_period_locked(target_company_id uuid, tx_date date)
returns boolean
language sql
security definer
stable
as $$
  select coalesce(
    (select locked_through_date >= tx_date from cc_companies where id = target_company_id),
    false
  );
$$;

-- Restrictive policies AND with whatever permissive policy already granted access, so none
-- of the existing (multiple, overlapping) insert/update/delete policies need to change.
-- Only INSERT and DELETE are gated — approvals, status changes, and payments on records that
-- already exist are left alone, since those aren't backdating or removing historical postings.

drop policy if exists "period lock blocks insert" on cc_entries;
create policy "period lock blocks insert" on cc_entries as restrictive for insert
  with check (not cc_period_locked(company_id, entry_date));
drop policy if exists "period lock blocks delete" on cc_entries;
create policy "period lock blocks delete" on cc_entries as restrictive for delete
  using (not cc_period_locked(company_id, entry_date));

drop policy if exists "period lock blocks insert" on cc_invoices;
create policy "period lock blocks insert" on cc_invoices as restrictive for insert
  with check (not cc_period_locked(company_id, issue_date));
drop policy if exists "period lock blocks delete" on cc_invoices;
create policy "period lock blocks delete" on cc_invoices as restrictive for delete
  using (not cc_period_locked(company_id, issue_date));

drop policy if exists "period lock blocks insert" on cc_credit_notes;
create policy "period lock blocks insert" on cc_credit_notes as restrictive for insert
  with check (not cc_period_locked(company_id, issue_date));
drop policy if exists "period lock blocks delete" on cc_credit_notes;
create policy "period lock blocks delete" on cc_credit_notes as restrictive for delete
  using (not cc_period_locked(company_id, issue_date));

drop policy if exists "period lock blocks insert" on cc_supplier_invoices;
create policy "period lock blocks insert" on cc_supplier_invoices as restrictive for insert
  with check (not cc_period_locked(company_id, issue_date));
drop policy if exists "period lock blocks delete" on cc_supplier_invoices;
create policy "period lock blocks delete" on cc_supplier_invoices as restrictive for delete
  using (not cc_period_locked(company_id, issue_date));

drop policy if exists "period lock blocks insert" on cc_supplier_credit_notes;
create policy "period lock blocks insert" on cc_supplier_credit_notes as restrictive for insert
  with check (not cc_period_locked(company_id, issue_date));
drop policy if exists "period lock blocks delete" on cc_supplier_credit_notes;
create policy "period lock blocks delete" on cc_supplier_credit_notes as restrictive for delete
  using (not cc_period_locked(company_id, issue_date));

-- ---------- verify ----------
select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'cc_attachments'::regclass and contype = 'c';
select column_name from information_schema.columns where table_name = 'cc_companies' and column_name = 'locked_through_date';
select tablename, policyname, permissive, cmd from pg_policies where policyname like 'period lock%' order by tablename, cmd;

-- ============ WAVE 29: accounting + payroll + compliance expansion ============
-- Quotes, simple stock/inventory + auto cost-of-sales, multi-currency invoicing/credit notes,
-- client statement of account, company car + employer loan fringe benefits, logbook-substantiated
-- travel allowance, COIDA Return of Earnings tracking, monthly EMP201 tracking, and a
-- Provisional Tax (company income tax) estimate + due-date tracker.

-- ---------- cc_companies: new company-level settings ----------
alter table cc_companies add column if not exists coida_registration_number text;
alter table cc_companies add column if not exists financial_year_end_month integer not null default 2 check (financial_year_end_month between 1 and 12);
alter table cc_companies add column if not exists official_interest_rate_pct numeric not null default 8.00;

-- ---------- Multi-currency invoicing/credit notes (foreign-currency line items, ZAR books) ----------
alter table cc_invoices add column if not exists currency text not null default 'ZAR' check (currency in ('ZAR','USD','GBP','EUR'));
alter table cc_invoices add column if not exists exchange_rate numeric not null default 1;
alter table cc_credit_notes add column if not exists currency text not null default 'ZAR' check (currency in ('ZAR','USD','GBP','EUR'));
alter table cc_credit_notes add column if not exists exchange_rate numeric not null default 1;

-- ---------- Simple stock/inventory ----------
create table if not exists cc_stock_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  name text not null,
  sku text,
  unit_cost numeric not null default 0,
  qty_on_hand numeric not null default 0,
  created_at timestamptz default now()
);

alter table cc_invoice_items add column if not exists stock_item_id uuid references cc_stock_items(id) on delete set null;
alter table cc_supplier_invoice_items add column if not exists stock_item_id uuid references cc_stock_items(id) on delete set null;

-- ---------- Quotes (quote-to-invoice flow) ----------
create table if not exists cc_quotes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  client_id uuid references cc_clients(id) on delete set null,
  quote_number text not null,
  issue_date date not null default current_date,
  expiry_date date,
  status text not null default 'draft' check (status in ('draft','sent','accepted','declined','expired','converted')),
  notes text,
  converted_invoice_id uuid references cc_invoices(id) on delete set null,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

create table if not exists cc_quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references cc_quotes(id) on delete cascade,
  description text not null,
  quantity numeric not null default 1,
  unit_price numeric not null default 0,
  vat_applicable boolean not null default true
);

-- ---------- Payroll: fringe benefits (company car, low/no-interest loan) + travel logbook ----------
alter table cc_employees add column if not exists travel_logbook_qualifies boolean not null default false;
alter table cc_employees add column if not exists has_company_car boolean not null default false;
alter table cc_employees add column if not exists car_determined_value numeric not null default 0;
alter table cc_employees add column if not exists car_has_maintenance_plan boolean not null default false;
alter table cc_employees add column if not exists loan_balance numeric not null default 0;
alter table cc_employees add column if not exists loan_interest_rate_charged numeric not null default 0;

alter table cc_payroll_payments add column if not exists car_fringe_benefit numeric not null default 0;
alter table cc_payroll_payments add column if not exists loan_fringe_benefit numeric not null default 0;

-- ---------- Monthly EMP201 tracking ----------
create table if not exists cc_emp201_submissions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  period_month text not null, -- 'YYYY-MM'
  paye numeric not null default 0,
  uif_employee numeric not null default 0,
  uif_employer numeric not null default 0,
  sdl numeric not null default 0,
  submitted boolean not null default false,
  submitted_date date,
  created_at timestamptz default now(),
  unique (company_id, period_month)
);

-- ---------- COIDA Return of Earnings (W.As.8) tracking ----------
create table if not exists cc_coida_returns (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  tax_year_label integer not null, -- e.g. 2027 = assessment year 1 Mar 2026 - 28/29 Feb 2027
  projected_earnings_next_year numeric,
  submitted boolean not null default false,
  submitted_date date,
  created_at timestamptz default now(),
  unique (company_id, tax_year_label)
);

-- ---------- Provisional Tax (company income tax estimate + due-date tracker) ----------
create table if not exists cc_provisional_tax (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  tax_year_end_year integer not null, -- calendar year the financial year ends in
  period_number integer not null check (period_number in (1,2)),
  due_date date,
  estimated_tax numeric not null default 0,
  paid boolean not null default false,
  paid_date date,
  created_at timestamptz default now(),
  unique (company_id, tax_year_end_year, period_number)
);

-- ============ ROW LEVEL SECURITY ============
alter table cc_stock_items enable row level security;
alter table cc_quotes enable row level security;
alter table cc_quote_items enable row level security;
alter table cc_emp201_submissions enable row level security;
alter table cc_coida_returns enable row level security;
alter table cc_provisional_tax enable row level security;

-- cc_stock_items: module-scoped, same shape as cc_assets/cc_liabilities
drop policy if exists "members select stock items" on cc_stock_items;
create policy "members select stock items" on cc_stock_items for select using (cc_is_member(company_id));
drop policy if exists "scoped write stock items" on cc_stock_items;
create policy "scoped write stock items" on cc_stock_items for insert with check (cc_has_module(company_id, 'stock'));
drop policy if exists "scoped update stock items" on cc_stock_items;
create policy "scoped update stock items" on cc_stock_items for update using (cc_has_module(company_id, 'stock'));
drop policy if exists "scoped delete stock items" on cc_stock_items;
create policy "scoped delete stock items" on cc_stock_items for delete using (cc_has_module(company_id, 'stock'));

-- cc_quotes: module-scoped. Pre-transaction documents (no approval workflow, no period lock —
-- unlike invoices/credit notes, a quote never posts to the books until it's converted).
drop policy if exists "members select quotes" on cc_quotes;
create policy "members select quotes" on cc_quotes for select using (cc_is_member(company_id));
drop policy if exists "scoped write quotes" on cc_quotes;
create policy "scoped write quotes" on cc_quotes for insert with check (cc_has_module(company_id, 'quotes'));
drop policy if exists "scoped update quotes" on cc_quotes;
create policy "scoped update quotes" on cc_quotes for update using (cc_has_module(company_id, 'quotes'));
drop policy if exists "scoped delete quotes" on cc_quotes;
create policy "scoped delete quotes" on cc_quotes for delete using (cc_has_module(company_id, 'quotes'));

drop policy if exists "members select quote items" on cc_quote_items;
create policy "members select quote items" on cc_quote_items for select using (
  cc_is_member((select company_id from cc_quotes where id = quote_id))
);
drop policy if exists "scoped write quote items" on cc_quote_items;
create policy "scoped write quote items" on cc_quote_items for insert with check (
  cc_has_module((select company_id from cc_quotes where id = quote_id), 'quotes')
);
drop policy if exists "scoped update quote items" on cc_quote_items;
create policy "scoped update quote items" on cc_quote_items for update using (
  cc_has_module((select company_id from cc_quotes where id = quote_id), 'quotes')
);
drop policy if exists "scoped delete quote items" on cc_quote_items;
create policy "scoped delete quote items" on cc_quote_items for delete using (
  cc_has_module((select company_id from cc_quotes where id = quote_id), 'quotes')
);

-- cc_emp201_submissions / cc_coida_returns / cc_provisional_tax: management-only compliance
-- tracking, matching the Payroll/Reports panels which are only shown to isAdmin()/canApprove().
drop policy if exists "admin select emp201" on cc_emp201_submissions;
create policy "admin select emp201" on cc_emp201_submissions for select using (cc_is_admin(company_id));
drop policy if exists "admin write emp201" on cc_emp201_submissions;
create policy "admin write emp201" on cc_emp201_submissions for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update emp201" on cc_emp201_submissions;
create policy "admin update emp201" on cc_emp201_submissions for update using (cc_is_admin(company_id));
drop policy if exists "admin delete emp201" on cc_emp201_submissions;
create policy "admin delete emp201" on cc_emp201_submissions for delete using (cc_is_admin(company_id));

drop policy if exists "admin select coida" on cc_coida_returns;
create policy "admin select coida" on cc_coida_returns for select using (cc_is_admin(company_id));
drop policy if exists "admin write coida" on cc_coida_returns;
create policy "admin write coida" on cc_coida_returns for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update coida" on cc_coida_returns;
create policy "admin update coida" on cc_coida_returns for update using (cc_is_admin(company_id));
drop policy if exists "admin delete coida" on cc_coida_returns;
create policy "admin delete coida" on cc_coida_returns for delete using (cc_is_admin(company_id));

drop policy if exists "management select provisional tax" on cc_provisional_tax;
create policy "management select provisional tax" on cc_provisional_tax for select using (cc_is_admin(company_id) or cc_can_approve(company_id));
drop policy if exists "admin write provisional tax" on cc_provisional_tax;
create policy "admin write provisional tax" on cc_provisional_tax for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update provisional tax" on cc_provisional_tax;
create policy "admin update provisional tax" on cc_provisional_tax for update using (cc_is_admin(company_id));
drop policy if exists "admin delete provisional tax" on cc_provisional_tax;
create policy "admin delete provisional tax" on cc_provisional_tax for delete using (cc_is_admin(company_id));

-- ---------- verify ----------
select table_name from information_schema.tables where table_name in
  ('cc_stock_items','cc_quotes','cc_quote_items','cc_emp201_submissions','cc_coida_returns','cc_provisional_tax')
  order by table_name;
select column_name from information_schema.columns where table_name = 'cc_companies' and column_name in
  ('coida_registration_number','financial_year_end_month','official_interest_rate_pct');
select column_name from information_schema.columns where table_name = 'cc_invoices' and column_name in ('currency','exchange_rate');
select column_name from information_schema.columns where table_name = 'cc_credit_notes' and column_name in ('currency','exchange_rate');
select column_name from information_schema.columns where table_name = 'cc_invoice_items' and column_name = 'stock_item_id';
select column_name from information_schema.columns where table_name = 'cc_supplier_invoice_items' and column_name = 'stock_item_id';
select column_name from information_schema.columns where table_name = 'cc_employees' and column_name in
  ('travel_logbook_qualifies','has_company_car','car_determined_value','car_has_maintenance_plan','loan_balance','loan_interest_rate_charged');
select column_name from information_schema.columns where table_name = 'cc_payroll_payments' and column_name in ('car_fringe_benefit','loan_fringe_benefit');
select tablename, policyname, cmd from pg_policies where tablename in
  ('cc_stock_items','cc_quotes','cc_quote_items','cc_emp201_submissions','cc_coida_returns','cc_provisional_tax')
  order by tablename, cmd;

-- ============ WAVE 30: service-provider (no inventory) toggle ============
-- A company-level setting so a pure service provider (nothing to stock) can turn off the
-- Stock tab and the stock-item column on Invoice/Supplier Invoice line items app-wide.
-- Defaults to true so every existing company keeps seeing Stock exactly as before.

alter table cc_companies add column if not exists tracks_inventory boolean not null default true;

-- ---------- verify ----------
select column_name, data_type, column_default from information_schema.columns
  where table_name = 'cc_companies' and column_name = 'tracks_inventory';
-- ============ WAVE 31: Settings tab (company name/trading-as, PAYE/SDL/UIF registered toggles) ============
-- The Settings tab (relocated from Team) can now edit the company name, and a new "Trading as"
-- field, plus PAYE/SDL/UIF "registered" toggles mirroring the existing VAT-registered toggle.
-- Those three toggles are visibility-only: they show/hide their reference-number field on
-- Settings and have no effect on how PAYE/SDL/UIF are calculated or displayed elsewhere.
-- No new RLS is needed — these are columns on the already-covered cc_companies table.

alter table cc_companies add column if not exists trading_as text;
alter table cc_companies add column if not exists paye_registered boolean not null default true;
alter table cc_companies add column if not exists sdl_registered boolean not null default true;
alter table cc_companies add column if not exists uif_registered boolean not null default true;

-- ---------- verify ----------
select column_name, data_type, column_default from information_schema.columns
  where table_name = 'cc_companies' and column_name in ('trading_as','paye_registered','sdl_registered','uif_registered')
  order by column_name;

-- ============ WAVE 32: capture-time attachments + bank reconciliation <-> invoices/bills ============

-- ---------- Attachments: customer Credit Notes can now carry attachments too ----------
-- (Revenue/Expenses/Invoices/Supplier Invoices/Supplier Credit Notes already could.)
alter table cc_attachments drop constraint if exists cc_attachments_entity_type_check;
alter table cc_attachments add constraint cc_attachments_entity_type_check
  check (entity_type in ('revenue','expense','invoice','credit_note','supplier_invoice','supplier_credit_note'));

-- ---------- Bank reconciliation: track the payment record a match created ----------
-- When a bank statement line is matched to an Invoice or Supplier Invoice, matchBankTransaction()
-- now also books a payment against it (cc_invoice_payments / cc_supplier_invoice_payments). This
-- column lets unmatchBankTransaction() clean that payment back up again, rather than leaving an
-- orphaned payment behind after an Unmatch.
alter table cc_bank_transactions add column if not exists linked_payment_id uuid;

-- ---------- verify ----------
select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'cc_attachments'::regclass and contype = 'c';
select column_name, data_type from information_schema.columns where table_name = 'cc_bank_transactions' and column_name = 'linked_payment_id';

-- ============ WAVE 34: Dashboard Bank Feed shortcut, entry Source labels, loan repayments ============

-- ---------- Loan/liability repayments (principal/interest split) ----------
-- Mirrors cc_invoice_payments / cc_supplier_invoice_payments: a subledger of actual cash paid
-- against a Liability (typically a loan), split into principal (reduces the liability's balance,
-- not a P&L event) and interest (posted as a new Expense entry, tagged 'liability-payment', since
-- only interest is P&L-relevant for a loan repayment).
create table if not exists cc_liability_payments (
  id uuid primary key default gen_random_uuid(),
  liability_id uuid not null references cc_liabilities(id) on delete cascade,
  company_id uuid not null references cc_companies(id) on delete cascade,
  payment_date date not null default current_date,
  principal_amount numeric not null default 0,
  interest_amount numeric not null default 0,
  -- set when the interest portion was posted as an Expense entry, so deleting this payment can
  -- clean that entry back up again (mirrors cc_bank_transactions.linked_payment_id).
  interest_entry_id uuid references cc_entries(id) on delete set null,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

alter table cc_liability_payments enable row level security;

drop policy if exists "members select liability payments" on cc_liability_payments;
create policy "members select liability payments" on cc_liability_payments for select using (cc_is_member(company_id));
drop policy if exists "scoped write liability payments" on cc_liability_payments;
create policy "scoped write liability payments" on cc_liability_payments for insert with check (cc_has_module(company_id, 'liabilities'));
drop policy if exists "scoped update liability payments" on cc_liability_payments;
create policy "scoped update liability payments" on cc_liability_payments for update using (cc_has_module(company_id, 'liabilities'));
drop policy if exists "scoped delete liability payments" on cc_liability_payments;
create policy "scoped delete liability payments" on cc_liability_payments for delete using (cc_has_module(company_id, 'liabilities'));

-- ---------- verify ----------
select table_name from information_schema.tables where table_name = 'cc_liability_payments';
select tablename, policyname, cmd from pg_policies where tablename = 'cc_liability_payments' order by cmd;

-- ============ WAVE 35: Manual Journals (true double-entry adjustments) ============
-- A journal has 2+ lines, each a debit or credit against Revenue, Expenses, an Asset or a
-- Liability; the app enforces total debits = total credits before posting. Revenue/Expense
-- lines create a new cc_entries row (tagged 'manual-journal'); Asset/Liability lines directly
-- adjust that record's value/amount (they're simple balances here, not itemized ledgers).
-- Owner/Management only (cc_is_admin); everyone who can see the tab can view journals.
create table if not exists cc_manual_journals (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  journal_date date not null default current_date,
  description text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

create table if not exists cc_manual_journal_lines (
  id uuid primary key default gen_random_uuid(),
  journal_id uuid not null references cc_manual_journals(id) on delete cascade,
  company_id uuid references cc_companies(id) on delete cascade,
  category text not null check (category in ('revenue','expense','asset','liability')),
  side text not null check (side in ('debit','credit')),
  amount numeric not null check (amount > 0),
  -- the delta actually applied (positive=increase, negative=decrease) — lets a journal deletion
  -- reverse an asset/liability adjustment exactly, and shows debit/credit intent either way.
  signed_amount numeric not null,
  target_asset_id uuid references cc_assets(id) on delete set null,
  target_liability_id uuid references cc_liabilities(id) on delete set null,
  memo text,
  -- the cc_entries row this line created (revenue/expense lines only), so deleting the journal
  -- can clean that entry back up too (mirrors cc_bank_transactions.linked_payment_id).
  entry_id uuid references cc_entries(id) on delete set null,
  created_at timestamptz default now()
);

alter table cc_manual_journals enable row level security;
create policy "members select manual journals" on cc_manual_journals for select using (cc_is_member(company_id));
create policy "admin write manual journals" on cc_manual_journals for insert with check (cc_is_admin(company_id));
create policy "admin delete manual journals" on cc_manual_journals for delete using (cc_is_admin(company_id));

alter table cc_manual_journal_lines enable row level security;
create policy "members select manual journal lines" on cc_manual_journal_lines for select using (cc_is_member(company_id));
create policy "admin write manual journal lines" on cc_manual_journal_lines for insert with check (cc_is_admin(company_id));
create policy "admin delete manual journal lines" on cc_manual_journal_lines for delete using (cc_is_admin(company_id));

-- Manual Journals can carry attachments too, same as every other capture-time entity.
alter table cc_attachments drop constraint if exists cc_attachments_entity_type_check;
alter table cc_attachments add constraint cc_attachments_entity_type_check
  check (entity_type in ('revenue','expense','invoice','credit_note','supplier_invoice','supplier_credit_note','manual_journal'));

-- ---------- verify ----------
select table_name from information_schema.tables where table_name in ('cc_manual_journals','cc_manual_journal_lines');
select tablename, policyname, cmd from pg_policies where tablename in ('cc_manual_journals','cc_manual_journal_lines') order by tablename, cmd;
select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'cc_attachments'::regclass and contype = 'c';

-- ============ WAVE 40: Chart of Accounts + derived General Ledger ============
-- The general ledger itself is DERIVED in the app from existing records (entries, invoices, bills,
-- payroll, payments, assets, liabilities, manual journals) — nothing is double-posted. This table
-- only stores each company's chart of accounts: the default set seeded on first open (system_key
-- links a row to the ledger's built-in account), which admins can rename/renumber. Custom accounts
-- (system_key null) are reserved for manual journals to post against in a later update.
create table if not exists cc_chart_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  system_key text,
  code text not null,
  name text not null,
  type text not null check (type in ('asset','liability','equity','revenue','expense')),
  is_active boolean not null default true,
  created_at timestamptz default now(),
  unique (company_id, code)
);

alter table cc_chart_accounts enable row level security;
create policy "members select chart accounts" on cc_chart_accounts for select using (cc_is_member(company_id));
create policy "admin insert chart accounts" on cc_chart_accounts for insert with check (cc_is_admin(company_id));
create policy "admin update chart accounts" on cc_chart_accounts for update using (cc_is_admin(company_id));
create policy "admin delete chart accounts" on cc_chart_accounts for delete using (cc_is_admin(company_id));

-- Wave 41: manual journals can post to any chart account (incl. custom accounts)
alter table public.cc_manual_journal_lines add column if not exists account_key text;
alter table public.cc_manual_journal_lines add column if not exists account_id uuid references public.cc_chart_accounts(id) on delete set null;
alter table public.cc_manual_journal_lines drop constraint if exists cc_manual_journal_lines_category_check;
alter table public.cc_manual_journal_lines add constraint cc_manual_journal_lines_category_check check (category in ('revenue','expense','asset','liability','ledger'));
alter table public.cc_chart_accounts add column if not exists is_current boolean not null default true;

-- ============ WAVE 42: maker-checker, year-end close ============
-- Company setting: when on, manual journals and manually-entered payments are saved as 'pending'
-- and only count once someone other than the person who entered them approves.
alter table public.cc_companies add column if not exists maker_checker boolean not null default false;

alter table public.cc_manual_journals add column if not exists approval_status text not null default 'approved' check (approval_status in ('pending','approved','rejected')), add column if not exists approved_by uuid, add column if not exists approved_at timestamptz, add column if not exists rejection_note text, add column if not exists kind text, add column if not exists fy_end date;
alter table public.cc_invoice_payments add column if not exists approval_status text not null default 'approved' check (approval_status in ('pending','approved','rejected')), add column if not exists approved_by uuid, add column if not exists approved_at timestamptz, add column if not exists rejection_note text;
alter table public.cc_supplier_invoice_payments add column if not exists approval_status text not null default 'approved' check (approval_status in ('pending','approved','rejected')), add column if not exists approved_by uuid, add column if not exists approved_at timestamptz, add column if not exists rejection_note text;
alter table public.cc_liability_payments add column if not exists approval_status text not null default 'approved' check (approval_status in ('pending','approved','rejected')), add column if not exists approved_by uuid, add column if not exists approved_at timestamptz, add column if not exists rejection_note text;

-- Database-level guard: a pending item can't be approved by the user who entered it (when the setting is on).
create or replace function public.cc_maker_checker_guard() returns trigger language plpgsql set search_path = public as $fn$ begin if tg_op = 'UPDATE' and old.approval_status = 'pending' and new.approval_status = 'approved' and old.created_by is not null and old.created_by = auth.uid() and exists (select 1 from public.cc_companies c where c.id = new.company_id and c.maker_checker) then raise exception 'Maker-checker: the person who entered this cannot approve it.'; end if; return new; end $fn$;
drop trigger if exists cc_manual_journals_maker_checker on public.cc_manual_journals;
create trigger cc_manual_journals_maker_checker before update on public.cc_manual_journals for each row execute function public.cc_maker_checker_guard();
drop trigger if exists cc_invoice_payments_maker_checker on public.cc_invoice_payments;
create trigger cc_invoice_payments_maker_checker before update on public.cc_invoice_payments for each row execute function public.cc_maker_checker_guard();
drop trigger if exists cc_supplier_invoice_payments_maker_checker on public.cc_supplier_invoice_payments;
create trigger cc_supplier_invoice_payments_maker_checker before update on public.cc_supplier_invoice_payments for each row execute function public.cc_maker_checker_guard();
drop trigger if exists cc_liability_payments_maker_checker on public.cc_liability_payments;
create trigger cc_liability_payments_maker_checker before update on public.cc_liability_payments for each row execute function public.cc_maker_checker_guard();
