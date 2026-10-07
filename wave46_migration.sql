-- Wave 46: foreign-exchange gains/losses and invoice emailing
alter table cc_supplier_invoices add column if not exists currency text not null default 'ZAR';
alter table cc_supplier_invoices add column if not exists exchange_rate numeric not null default 1;
alter table cc_invoice_payments add column if not exists foreign_amount numeric;
alter table cc_supplier_invoice_payments add column if not exists foreign_amount numeric;
alter table cc_invoices add column if not exists emailed_at timestamptz;
alter table cc_invoices add column if not exists emailed_to text;

create table if not exists cc_fx_rates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  rate_date date not null,
  currency text not null,
  rate numeric not null check (rate > 0),
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (company_id, rate_date, currency)
);
alter table cc_fx_rates enable row level security;
drop policy if exists "fx_rates_select" on cc_fx_rates;
create policy "fx_rates_select" on cc_fx_rates for select using (cc_is_member(company_id));
drop policy if exists "fx_rates_insert" on cc_fx_rates;
create policy "fx_rates_insert" on cc_fx_rates for insert with check (cc_is_admin(company_id));
drop policy if exists "fx_rates_update" on cc_fx_rates;
create policy "fx_rates_update" on cc_fx_rates for update using (cc_is_admin(company_id)) with check (cc_is_admin(company_id));
drop policy if exists "fx_rates_delete" on cc_fx_rates;
create policy "fx_rates_delete" on cc_fx_rates for delete using (cc_is_admin(company_id));
