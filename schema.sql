-- Company Compass schema
-- Run this in the Supabase SQL Editor for the Company Compass project.
-- Prefix: cc_

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
  role text not null default 'viewer' check (role in ('owner','admin','viewer')),
  status text not null default 'active' check (status in ('pending','active')),
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

-- ============ HELPER FUNCTION ============
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

-- Returns true if the current user is owner/admin of the company.
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
alter table cc_employees enable row level security;
alter table cc_payroll_payments enable row level security;

-- cc_companies
create policy "members can view company" on cc_companies for select
  using (cc_is_member(id));
create policy "owner can insert company" on cc_companies for insert
  with check (owner_id = auth.uid());
create policy "admin can update company" on cc_companies for update
  using (cc_is_admin(id));

-- cc_company_members
create policy "members can view membership" on cc_company_members for select
  using (cc_is_member(company_id) or email = auth.jwt() ->> 'email');
create policy "admin can manage members insert" on cc_company_members for insert
  with check (cc_is_admin(company_id) or not exists (select 1 from cc_company_members where company_id = cc_company_members.company_id));
create policy "admin can manage members update" on cc_company_members for update
  using (cc_is_admin(company_id) or user_id = auth.uid());
create policy "admin can manage members delete" on cc_company_members for delete
  using (cc_is_admin(company_id));

-- generic per-table policies (member = read, admin = write) for financial tables
create policy "members select accounts" on cc_accounts for select using (cc_is_member(company_id));
create policy "admin write accounts" on cc_accounts for insert with check (cc_is_admin(company_id));
create policy "admin update accounts" on cc_accounts for update using (cc_is_admin(company_id));
create policy "admin delete accounts" on cc_accounts for delete using (cc_is_admin(company_id));

create policy "members select clients" on cc_clients for select using (cc_is_member(company_id));
create policy "admin write clients" on cc_clients for insert with check (cc_is_admin(company_id));
create policy "admin update clients" on cc_clients for update using (cc_is_admin(company_id));
create policy "admin delete clients" on cc_clients for delete using (cc_is_admin(company_id));

create policy "members select entries" on cc_entries for select using (cc_is_member(company_id));
create policy "admin write entries" on cc_entries for insert with check (cc_is_admin(company_id));
create policy "admin update entries" on cc_entries for update using (cc_is_admin(company_id));
create policy "admin delete entries" on cc_entries for delete using (cc_is_admin(company_id));

create policy "members select assets" on cc_assets for select using (cc_is_member(company_id));
create policy "admin write assets" on cc_assets for insert with check (cc_is_admin(company_id));
create policy "admin update assets" on cc_assets for update using (cc_is_admin(company_id));
create policy "admin delete assets" on cc_assets for delete using (cc_is_admin(company_id));

create policy "members select liabilities" on cc_liabilities for select using (cc_is_member(company_id));
create policy "admin write liabilities" on cc_liabilities for insert with check (cc_is_admin(company_id));
create policy "admin update liabilities" on cc_liabilities for update using (cc_is_admin(company_id));
create policy "admin delete liabilities" on cc_liabilities for delete using (cc_is_admin(company_id));

create policy "members select invoices" on cc_invoices for select using (cc_is_member(company_id));
create policy "admin write invoices" on cc_invoices for insert with check (cc_is_admin(company_id));
create policy "admin update invoices" on cc_invoices for update using (cc_is_admin(company_id));
create policy "admin delete invoices" on cc_invoices for delete using (cc_is_admin(company_id));

create policy "members select invoice items" on cc_invoice_items for select using (
  cc_is_member((select company_id from cc_invoices where id = invoice_id))
);
create policy "admin write invoice items" on cc_invoice_items for insert with check (
  cc_is_admin((select company_id from cc_invoices where id = invoice_id))
);
create policy "admin update invoice items" on cc_invoice_items for update using (
  cc_is_admin((select company_id from cc_invoices where id = invoice_id))
);
create policy "admin delete invoice items" on cc_invoice_items for delete using (
  cc_is_admin((select company_id from cc_invoices where id = invoice_id))
);

create policy "members select employees" on cc_employees for select using (cc_is_member(company_id));
create policy "admin write employees" on cc_employees for insert with check (cc_is_admin(company_id));
create policy "admin update employees" on cc_employees for update using (cc_is_admin(company_id));
create policy "admin delete employees" on cc_employees for delete using (cc_is_admin(company_id));

create policy "members select payroll" on cc_payroll_payments for select using (cc_is_member(company_id));
create policy "admin write payroll" on cc_payroll_payments for insert with check (cc_is_admin(company_id));
create policy "admin update payroll" on cc_payroll_payments for update using (cc_is_admin(company_id));
create policy "admin delete payroll" on cc_payroll_payments for delete using (cc_is_admin(company_id));

-- ============ EMPLOYEE TASKS (added 2026-09-06) ============

create table if not exists cc_employee_tasks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  employee_id uuid not null references cc_employees(id) on delete cascade,
  description text not null,
  status text not null default 'in_progress' check (status in ('todo','in_progress','done')),
  created_at timestamptz default now()
);

alter table cc_employee_tasks enable row level security;

create policy "members select employee tasks" on cc_employee_tasks for select using (cc_is_member(company_id));
create policy "admin write employee tasks" on cc_employee_tasks for insert with check (cc_is_admin(company_id));
create policy "admin update employee tasks" on cc_employee_tasks for update using (cc_is_admin(company_id));
create policy "admin delete employee tasks" on cc_employee_tasks for delete using (cc_is_admin(company_id));
