-- Company Compass: idempotent repair script.
-- Safe to run any number of times — recreates every function and RLS policy
-- from scratch so nothing partially-applied is left in a broken state.
-- Run this in the Supabase SQL Editor for the Company Compass project.

-- ============ HELPER FUNCTIONS ============

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

-- ============ MAKE SURE THE EMPLOYEE TASKS TABLE EXISTS ============

create table if not exists cc_employee_tasks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  employee_id uuid not null references cc_employees(id) on delete cascade,
  description text not null,
  status text not null default 'in_progress' check (status in ('todo','in_progress','done')),
  created_at timestamptz default now()
);

-- ============ MAKE SURE RLS IS ON ============

alter table cc_companies enable row level security;
alter table cc_company_members enable row level security;
alter table cc_accounts enable row level security;
alter table cc_clients enable row level security;
alter table cc_entries enable row level security;
alter table cc_assets enable row level security;
alter table cc_liabilities enable row level security;
alter table cc_invoices enable row level security;
alter table cc_invoice_items enable row level security;
alter table cc_employees enable row level security;
alter table cc_payroll_payments enable row level security;
alter table cc_employee_tasks enable row level security;

-- ============ cc_companies ============

drop policy if exists "members can view company" on cc_companies;
create policy "members can view company" on cc_companies for select
  using (cc_is_member(id) or owner_id = auth.uid());

drop policy if exists "owner can insert company" on cc_companies;
create policy "owner can insert company" on cc_companies for insert
  with check (owner_id = auth.uid());

drop policy if exists "admin can update company" on cc_companies;
create policy "admin can update company" on cc_companies for update
  using (cc_is_admin(id));

-- ============ cc_company_members ============
-- (fixed: the insert "first member" check now correctly scopes to the
-- company being inserted for, instead of accidentally matching any row
-- in the whole table)

drop policy if exists "members can view membership" on cc_company_members;
create policy "members can view membership" on cc_company_members for select
  using (cc_is_member(company_id) or email = auth.jwt() ->> 'email');

drop policy if exists "admin can manage members insert" on cc_company_members;
create policy "admin can manage members insert" on cc_company_members for insert
  with check (
    cc_is_admin(company_id)
    or not exists (select 1 from cc_company_members m where m.company_id = cc_company_members.company_id)
  );

drop policy if exists "admin can manage members update" on cc_company_members;
create policy "admin can manage members update" on cc_company_members for update
  using (cc_is_admin(company_id) or user_id = auth.uid());

drop policy if exists "admin can manage members delete" on cc_company_members;
create policy "admin can manage members delete" on cc_company_members for delete
  using (cc_is_admin(company_id));

-- ============ generic member/admin policies for the rest ============

drop policy if exists "members select accounts" on cc_accounts;
create policy "members select accounts" on cc_accounts for select using (cc_is_member(company_id));
drop policy if exists "admin write accounts" on cc_accounts;
create policy "admin write accounts" on cc_accounts for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update accounts" on cc_accounts;
create policy "admin update accounts" on cc_accounts for update using (cc_is_admin(company_id));
drop policy if exists "admin delete accounts" on cc_accounts;
create policy "admin delete accounts" on cc_accounts for delete using (cc_is_admin(company_id));

drop policy if exists "members select clients" on cc_clients;
create policy "members select clients" on cc_clients for select using (cc_is_member(company_id));
drop policy if exists "admin write clients" on cc_clients;
create policy "admin write clients" on cc_clients for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update clients" on cc_clients;
create policy "admin update clients" on cc_clients for update using (cc_is_admin(company_id));
drop policy if exists "admin delete clients" on cc_clients;
create policy "admin delete clients" on cc_clients for delete using (cc_is_admin(company_id));

drop policy if exists "members select entries" on cc_entries;
create policy "members select entries" on cc_entries for select using (cc_is_member(company_id));
drop policy if exists "admin write entries" on cc_entries;
create policy "admin write entries" on cc_entries for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update entries" on cc_entries;
create policy "admin update entries" on cc_entries for update using (cc_is_admin(company_id));
drop policy if exists "admin delete entries" on cc_entries;
create policy "admin delete entries" on cc_entries for delete using (cc_is_admin(company_id));

drop policy if exists "members select assets" on cc_assets;
create policy "members select assets" on cc_assets for select using (cc_is_member(company_id));
drop policy if exists "admin write assets" on cc_assets;
create policy "admin write assets" on cc_assets for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update assets" on cc_assets;
create policy "admin update assets" on cc_assets for update using (cc_is_admin(company_id));
drop policy if exists "admin delete assets" on cc_assets;
create policy "admin delete assets" on cc_assets for delete using (cc_is_admin(company_id));

drop policy if exists "members select liabilities" on cc_liabilities;
create policy "members select liabilities" on cc_liabilities for select using (cc_is_member(company_id));
drop policy if exists "admin write liabilities" on cc_liabilities;
create policy "admin write liabilities" on cc_liabilities for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update liabilities" on cc_liabilities;
create policy "admin update liabilities" on cc_liabilities for update using (cc_is_admin(company_id));
drop policy if exists "admin delete liabilities" on cc_liabilities;
create policy "admin delete liabilities" on cc_liabilities for delete using (cc_is_admin(company_id));

drop policy if exists "members select invoices" on cc_invoices;
create policy "members select invoices" on cc_invoices for select using (cc_is_member(company_id));
drop policy if exists "admin write invoices" on cc_invoices;
create policy "admin write invoices" on cc_invoices for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update invoices" on cc_invoices;
create policy "admin update invoices" on cc_invoices for update using (cc_is_admin(company_id));
drop policy if exists "admin delete invoices" on cc_invoices;
create policy "admin delete invoices" on cc_invoices for delete using (cc_is_admin(company_id));

drop policy if exists "members select invoice items" on cc_invoice_items;
create policy "members select invoice items" on cc_invoice_items for select using (
  cc_is_member((select company_id from cc_invoices where id = invoice_id))
);
drop policy if exists "admin write invoice items" on cc_invoice_items;
create policy "admin write invoice items" on cc_invoice_items for insert with check (
  cc_is_admin((select company_id from cc_invoices where id = invoice_id))
);
drop policy if exists "admin update invoice items" on cc_invoice_items;
create policy "admin update invoice items" on cc_invoice_items for update using (
  cc_is_admin((select company_id from cc_invoices where id = invoice_id))
);
drop policy if exists "admin delete invoice items" on cc_invoice_items;
create policy "admin delete invoice items" on cc_invoice_items for delete using (
  cc_is_admin((select company_id from cc_invoices where id = invoice_id))
);

drop policy if exists "members select employees" on cc_employees;
create policy "members select employees" on cc_employees for select using (cc_is_member(company_id));
drop policy if exists "admin write employees" on cc_employees;
create policy "admin write employees" on cc_employees for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update employees" on cc_employees;
create policy "admin update employees" on cc_employees for update using (cc_is_admin(company_id));
drop policy if exists "admin delete employees" on cc_employees;
create policy "admin delete employees" on cc_employees for delete using (cc_is_admin(company_id));

drop policy if exists "members select payroll" on cc_payroll_payments;
create policy "members select payroll" on cc_payroll_payments for select using (cc_is_member(company_id));
drop policy if exists "admin write payroll" on cc_payroll_payments;
create policy "admin write payroll" on cc_payroll_payments for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update payroll" on cc_payroll_payments;
create policy "admin update payroll" on cc_payroll_payments for update using (cc_is_admin(company_id));
drop policy if exists "admin delete payroll" on cc_payroll_payments;
create policy "admin delete payroll" on cc_payroll_payments for delete using (cc_is_admin(company_id));

drop policy if exists "members select employee tasks" on cc_employee_tasks;
create policy "members select employee tasks" on cc_employee_tasks for select using (cc_is_member(company_id));
drop policy if exists "admin write employee tasks" on cc_employee_tasks;
create policy "admin write employee tasks" on cc_employee_tasks for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update employee tasks" on cc_employee_tasks;
create policy "admin update employee tasks" on cc_employee_tasks for update using (cc_is_admin(company_id));
drop policy if exists "admin delete employee tasks" on cc_employee_tasks;
create policy "admin delete employee tasks" on cc_employee_tasks for delete using (cc_is_admin(company_id));

-- ============================================================
-- Company Compass: RBAC upgrade
-- Adds a "staff" role with per-module permissions, plus an
-- approval workflow for Invoices and the new Credit Notes module.
-- Idempotent — safe to run multiple times.
-- ============================================================

-- ---------- roles + permissions ----------
alter table cc_company_members drop constraint if exists cc_company_members_role_check;
alter table cc_company_members add constraint cc_company_members_role_check check (role in ('owner','admin','viewer','staff'));
alter table cc_company_members add column if not exists permissions jsonb not null default '{}'::jsonb;
-- permissions shape for role='staff': { "modules": ["invoices","credit_notes"], "can_approve": false }

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

-- ---------- cc_entries (revenue/expenses), module-scoped by type ----------
drop policy if exists "admin write entries" on cc_entries;
drop policy if exists "admin update entries" on cc_entries;
drop policy if exists "admin delete entries" on cc_entries;
drop policy if exists "scoped write entries" on cc_entries;
create policy "scoped write entries" on cc_entries for insert with check (
  (type = 'revenue' and cc_has_module(company_id, 'revenue')) or (type = 'expense' and cc_has_module(company_id, 'expenses'))
);
drop policy if exists "scoped update entries" on cc_entries;
create policy "scoped update entries" on cc_entries for update using (
  (type = 'revenue' and cc_has_module(company_id, 'revenue')) or (type = 'expense' and cc_has_module(company_id, 'expenses'))
);
drop policy if exists "scoped delete entries" on cc_entries;
create policy "scoped delete entries" on cc_entries for delete using (
  (type = 'revenue' and cc_has_module(company_id, 'revenue')) or (type = 'expense' and cc_has_module(company_id, 'expenses'))
);

-- ---------- cc_assets ----------
drop policy if exists "admin write assets" on cc_assets;
drop policy if exists "admin update assets" on cc_assets;
drop policy if exists "admin delete assets" on cc_assets;
drop policy if exists "scoped write assets" on cc_assets;
create policy "scoped write assets" on cc_assets for insert with check (cc_has_module(company_id, 'assets'));
drop policy if exists "scoped update assets" on cc_assets;
create policy "scoped update assets" on cc_assets for update using (cc_has_module(company_id, 'assets'));
drop policy if exists "scoped delete assets" on cc_assets;
create policy "scoped delete assets" on cc_assets for delete using (cc_has_module(company_id, 'assets'));

-- ---------- cc_liabilities ----------
drop policy if exists "admin write liabilities" on cc_liabilities;
drop policy if exists "admin update liabilities" on cc_liabilities;
drop policy if exists "admin delete liabilities" on cc_liabilities;
drop policy if exists "scoped write liabilities" on cc_liabilities;
create policy "scoped write liabilities" on cc_liabilities for insert with check (cc_has_module(company_id, 'liabilities'));
drop policy if exists "scoped update liabilities" on cc_liabilities;
create policy "scoped update liabilities" on cc_liabilities for update using (cc_has_module(company_id, 'liabilities'));
drop policy if exists "scoped delete liabilities" on cc_liabilities;
create policy "scoped delete liabilities" on cc_liabilities for delete using (cc_has_module(company_id, 'liabilities'));

-- ---------- cc_clients ----------
drop policy if exists "admin write clients" on cc_clients;
drop policy if exists "admin update clients" on cc_clients;
drop policy if exists "admin delete clients" on cc_clients;
drop policy if exists "scoped write clients" on cc_clients;
create policy "scoped write clients" on cc_clients for insert with check (cc_has_module(company_id, 'clients'));
drop policy if exists "scoped update clients" on cc_clients;
create policy "scoped update clients" on cc_clients for update using (cc_has_module(company_id, 'clients'));
drop policy if exists "scoped delete clients" on cc_clients;
create policy "scoped delete clients" on cc_clients for delete using (cc_has_module(company_id, 'clients'));

-- ---------- cc_employees / cc_payroll_payments / cc_employee_tasks ----------
drop policy if exists "admin write employees" on cc_employees;
drop policy if exists "admin update employees" on cc_employees;
drop policy if exists "admin delete employees" on cc_employees;
drop policy if exists "scoped write employees" on cc_employees;
create policy "scoped write employees" on cc_employees for insert with check (cc_has_module(company_id, 'payroll'));
drop policy if exists "scoped update employees" on cc_employees;
create policy "scoped update employees" on cc_employees for update using (cc_has_module(company_id, 'payroll'));
drop policy if exists "scoped delete employees" on cc_employees;
create policy "scoped delete employees" on cc_employees for delete using (cc_has_module(company_id, 'payroll'));

drop policy if exists "admin write payroll" on cc_payroll_payments;
drop policy if exists "admin update payroll" on cc_payroll_payments;
drop policy if exists "admin delete payroll" on cc_payroll_payments;
drop policy if exists "scoped write payroll" on cc_payroll_payments;
create policy "scoped write payroll" on cc_payroll_payments for insert with check (cc_has_module(company_id, 'payroll'));
drop policy if exists "scoped update payroll" on cc_payroll_payments;
create policy "scoped update payroll" on cc_payroll_payments for update using (cc_has_module(company_id, 'payroll'));
drop policy if exists "scoped delete payroll" on cc_payroll_payments;
create policy "scoped delete payroll" on cc_payroll_payments for delete using (cc_has_module(company_id, 'payroll'));

drop policy if exists "admin write employee tasks" on cc_employee_tasks;
drop policy if exists "admin update employee tasks" on cc_employee_tasks;
drop policy if exists "admin delete employee tasks" on cc_employee_tasks;
drop policy if exists "scoped write employee tasks" on cc_employee_tasks;
create policy "scoped write employee tasks" on cc_employee_tasks for insert with check (cc_has_module(company_id, 'payroll'));
drop policy if exists "scoped update employee tasks" on cc_employee_tasks;
create policy "scoped update employee tasks" on cc_employee_tasks for update using (cc_has_module(company_id, 'payroll'));
drop policy if exists "scoped delete employee tasks" on cc_employee_tasks;
create policy "scoped delete employee tasks" on cc_employee_tasks for delete using (cc_has_module(company_id, 'payroll'));

-- ---------- cc_invoices: module-scoped create + approval workflow ----------
alter table cc_invoices add column if not exists created_by uuid references auth.users(id);
alter table cc_invoices add column if not exists approval_status text not null default 'approved' check (approval_status in ('pending','approved','rejected'));
alter table cc_invoices add column if not exists approved_by uuid references auth.users(id);
alter table cc_invoices add column if not exists approved_at timestamptz;
alter table cc_invoices add column if not exists rejection_note text;

drop policy if exists "admin write invoices" on cc_invoices;
drop policy if exists "admin update invoices" on cc_invoices;
drop policy if exists "admin delete invoices" on cc_invoices;
drop policy if exists "scoped write invoices" on cc_invoices;
create policy "scoped write invoices" on cc_invoices for insert with check (cc_has_module(company_id, 'invoices'));
drop policy if exists "management update invoices" on cc_invoices;
create policy "management update invoices" on cc_invoices for update using (cc_can_approve(company_id));
drop policy if exists "creator edit pending invoice" on cc_invoices;
create policy "creator edit pending invoice" on cc_invoices for update
  using (created_by = auth.uid() and approval_status = 'pending')
  with check (created_by = auth.uid() and approval_status = 'pending');
drop policy if exists "management delete invoices" on cc_invoices;
create policy "management delete invoices" on cc_invoices for delete using (cc_can_approve(company_id));
drop policy if exists "creator delete pending invoice" on cc_invoices;
create policy "creator delete pending invoice" on cc_invoices for delete using (created_by = auth.uid() and approval_status = 'pending');

drop policy if exists "admin write invoice items" on cc_invoice_items;
drop policy if exists "admin update invoice items" on cc_invoice_items;
drop policy if exists "admin delete invoice items" on cc_invoice_items;
drop policy if exists "scoped write invoice items" on cc_invoice_items;
create policy "scoped write invoice items" on cc_invoice_items for insert with check (
  cc_has_module((select company_id from cc_invoices where id = invoice_id), 'invoices')
);
drop policy if exists "scoped update invoice items" on cc_invoice_items;
create policy "scoped update invoice items" on cc_invoice_items for update using (
  cc_can_approve((select company_id from cc_invoices where id = invoice_id))
  or exists (select 1 from cc_invoices i where i.id = invoice_id and i.created_by = auth.uid() and i.approval_status = 'pending')
);
drop policy if exists "scoped delete invoice items" on cc_invoice_items;
create policy "scoped delete invoice items" on cc_invoice_items for delete using (
  cc_can_approve((select company_id from cc_invoices where id = invoice_id))
  or exists (select 1 from cc_invoices i where i.id = invoice_id and i.created_by = auth.uid() and i.approval_status = 'pending')
);

-- ---------- cc_credit_notes (new module) ----------
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
alter table cc_credit_notes enable row level security;
alter table cc_credit_note_items enable row level security;

drop policy if exists "members select credit notes" on cc_credit_notes;
create policy "members select credit notes" on cc_credit_notes for select using (cc_is_member(company_id));
drop policy if exists "scoped write credit notes" on cc_credit_notes;
create policy "scoped write credit notes" on cc_credit_notes for insert with check (cc_has_module(company_id, 'credit_notes'));
drop policy if exists "management update credit notes" on cc_credit_notes;
create policy "management update credit notes" on cc_credit_notes for update using (cc_can_approve(company_id));
drop policy if exists "creator edit pending credit note" on cc_credit_notes;
create policy "creator edit pending credit note" on cc_credit_notes for update
  using (created_by = auth.uid() and approval_status = 'pending')
  with check (created_by = auth.uid() and approval_status = 'pending');
drop policy if exists "management delete credit notes" on cc_credit_notes;
create policy "management delete credit notes" on cc_credit_notes for delete using (cc_can_approve(company_id));
drop policy if exists "creator delete pending credit note" on cc_credit_notes;
create policy "creator delete pending credit note" on cc_credit_notes for delete using (created_by = auth.uid() and approval_status = 'pending');

drop policy if exists "members select credit note items" on cc_credit_note_items;
create policy "members select credit note items" on cc_credit_note_items for select using (
  cc_is_member((select company_id from cc_credit_notes where id = credit_note_id))
);
drop policy if exists "scoped write credit note items" on cc_credit_note_items;
create policy "scoped write credit note items" on cc_credit_note_items for insert with check (
  cc_has_module((select company_id from cc_credit_notes where id = credit_note_id), 'credit_notes')
);
drop policy if exists "scoped update credit note items" on cc_credit_note_items;
create policy "scoped update credit note items" on cc_credit_note_items for update using (
  cc_can_approve((select company_id from cc_credit_notes where id = credit_note_id))
  or exists (select 1 from cc_credit_notes c where c.id = credit_note_id and c.created_by = auth.uid() and c.approval_status = 'pending')
);
drop policy if exists "scoped delete credit note items" on cc_credit_note_items;
create policy "scoped delete credit note items" on cc_credit_note_items for delete using (
  cc_can_approve((select company_id from cc_credit_notes where id = credit_note_id))
  or exists (select 1 from cc_credit_notes c where c.id = credit_note_id and c.created_by = auth.uid() and c.approval_status = 'pending')
);

-- ---------- Reports: P&L / Balance Sheet columns (idempotent) ----------
alter table cc_entries add column if not exists expense_category text not null default 'operating' check (expense_category in ('cost_of_sales','operating'));
alter table cc_assets add column if not exists is_current boolean not null default false;
alter table cc_liabilities add column if not exists is_current boolean not null default false;

-- ---------- Wave 2: cash flow, AR/AP aging, recurring invoices, budget vs
-- actual, fixed asset register + depreciation, signed financials (idempotent) ----------
alter table cc_invoices add column if not exists is_recurring boolean not null default false;
alter table cc_invoices add column if not exists recurrence_frequency text check (recurrence_frequency in ('weekly','monthly','quarterly','annually'));
alter table cc_invoices add column if not exists recurrence_next_date date;
alter table cc_invoices add column if not exists recurrence_end_date date;

alter table cc_liabilities add column if not exists due_date date;

alter table cc_assets add column if not exists purchase_date date;
alter table cc_assets add column if not exists useful_life_months integer;
alter table cc_assets add column if not exists residual_value numeric not null default 0;
alter table cc_assets add column if not exists accumulated_depreciation numeric not null default 0;
alter table cc_assets add column if not exists last_depreciation_run date;

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
drop policy if exists "members select budgets" on cc_budgets;
create policy "members select budgets" on cc_budgets for select using (cc_is_member(company_id));
drop policy if exists "admin write budgets" on cc_budgets;
create policy "admin write budgets" on cc_budgets for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update budgets" on cc_budgets;
create policy "admin update budgets" on cc_budgets for update using (cc_is_admin(company_id));
drop policy if exists "admin delete budgets" on cc_budgets;
create policy "admin delete budgets" on cc_budgets for delete using (cc_is_admin(company_id));

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
drop policy if exists "members select financial statements" on cc_financial_statements;
create policy "members select financial statements" on cc_financial_statements for select using (cc_is_member(company_id));
drop policy if exists "admin write financial statements" on cc_financial_statements;
create policy "admin write financial statements" on cc_financial_statements for insert with check (cc_is_admin(company_id));
drop policy if exists "admin delete financial statements" on cc_financial_statements;
create policy "admin delete financial statements" on cc_financial_statements for delete using (cc_is_admin(company_id));

insert into storage.buckets (id, name, public)
values ('financials', 'financials', false)
on conflict (id) do nothing;

drop policy if exists "members view financials files" on storage.objects;
create policy "members view financials files" on storage.objects for select
  using (bucket_id = 'financials' and cc_is_member((storage.foldername(name))[1]::uuid));
drop policy if exists "admin upload financials files" on storage.objects;
create policy "admin upload financials files" on storage.objects for insert
  with check (bucket_id = 'financials' and cc_is_admin((storage.foldername(name))[1]::uuid));
drop policy if exists "admin delete financials files" on storage.objects;
create policy "admin delete financials files" on storage.objects for delete
  using (bucket_id = 'financials' and cc_is_admin((storage.foldername(name))[1]::uuid));

-- ---------- verify ----------
select tablename, count(*) as policy_count
from pg_policies
where tablename like 'cc_%'
group by tablename
order by tablename;
