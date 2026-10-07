
-- ============================================================
-- Wave 44: VAT payments, asset disposals, bad debts, recurring/reversing journals
-- ============================================================
create table if not exists cc_vat_payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  payment_date date not null default current_date,
  amount numeric not null,              -- positive = paid to SARS, negative = refund received
  period_start date,
  period_end date,
  reference text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);
alter table cc_vat_payments enable row level security;
drop policy if exists "members select vat payments" on cc_vat_payments;
create policy "members select vat payments" on cc_vat_payments for select using (cc_is_member(company_id));
drop policy if exists "admin insert vat payments" on cc_vat_payments;
create policy "admin insert vat payments" on cc_vat_payments for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update vat payments" on cc_vat_payments;
create policy "admin update vat payments" on cc_vat_payments for update using (cc_is_admin(company_id));
drop policy if exists "admin delete vat payments" on cc_vat_payments;
create policy "admin delete vat payments" on cc_vat_payments for delete using (cc_is_admin(company_id));

create table if not exists cc_invoice_writeoffs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  invoice_id uuid not null references cc_invoices(id) on delete cascade,
  write_off_date date not null default current_date,
  amount numeric not null,
  vat_adjust boolean not null default false,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);
alter table cc_invoice_writeoffs enable row level security;
drop policy if exists "members select invoice writeoffs" on cc_invoice_writeoffs;
create policy "members select invoice writeoffs" on cc_invoice_writeoffs for select using (cc_is_member(company_id));
drop policy if exists "scoped write invoice writeoffs" on cc_invoice_writeoffs;
create policy "scoped write invoice writeoffs" on cc_invoice_writeoffs for insert with check (cc_has_module(company_id, 'invoices'));
drop policy if exists "scoped update invoice writeoffs" on cc_invoice_writeoffs;
create policy "scoped update invoice writeoffs" on cc_invoice_writeoffs for update using (cc_has_module(company_id, 'invoices'));
drop policy if exists "scoped delete invoice writeoffs" on cc_invoice_writeoffs;
create policy "scoped delete invoice writeoffs" on cc_invoice_writeoffs for delete using (cc_has_module(company_id, 'invoices'));

alter table cc_assets add column if not exists disposed_date date, add column if not exists disposal_proceeds numeric not null default 0, add column if not exists disposal_vat boolean not null default false, add column if not exists disposal_note text;
alter table cc_manual_journals add column if not exists auto_reverse boolean not null default false, add column if not exists reverse_date date, add column if not exists recur_monthly boolean not null default false, add column if not exists recur_until date;
