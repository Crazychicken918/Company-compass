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
  useful_life_months integer,
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
