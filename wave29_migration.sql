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
