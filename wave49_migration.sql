-- Wave 49: prepayments (customer deposits received / supplier prepayments paid) and their allocation
create table if not exists cc_party_credits (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  party_type text not null check (party_type in ('client','supplier')),
  party_id uuid not null,
  credit_date date not null,
  amount numeric not null check (amount > 0),
  reference text,
  notes text,
  bank_transaction_id uuid,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists cc_party_credits_company_idx on cc_party_credits(company_id, party_type, party_id);
alter table cc_party_credits enable row level security;
drop policy if exists "party_credits_select" on cc_party_credits;
create policy "party_credits_select" on cc_party_credits for select using (cc_is_member(company_id));
drop policy if exists "party_credits_insert" on cc_party_credits;
create policy "party_credits_insert" on cc_party_credits for insert with check (
  (party_type = 'client' and cc_has_module(company_id, 'invoices')) or (party_type = 'supplier' and cc_has_module(company_id, 'supplier_invoices')));
drop policy if exists "party_credits_delete" on cc_party_credits;
create policy "party_credits_delete" on cc_party_credits for delete using (cc_is_admin(company_id));

create table if not exists cc_credit_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  credit_id uuid not null references cc_party_credits(id) on delete cascade,
  kind text not null check (kind in ('invoice','bill','refund')),
  doc_id uuid,
  alloc_date date not null,
  amount numeric not null check (amount > 0),
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists cc_credit_allocations_company_idx on cc_credit_allocations(company_id, credit_id);
alter table cc_credit_allocations enable row level security;
drop policy if exists "credit_alloc_select" on cc_credit_allocations;
create policy "credit_alloc_select" on cc_credit_allocations for select using (cc_is_member(company_id));
drop policy if exists "credit_alloc_insert" on cc_credit_allocations;
create policy "credit_alloc_insert" on cc_credit_allocations for insert with check (cc_has_module(company_id, 'invoices') or cc_has_module(company_id, 'supplier_invoices'));
drop policy if exists "credit_alloc_delete" on cc_credit_allocations;
create policy "credit_alloc_delete" on cc_credit_allocations for delete using (cc_has_module(company_id, 'invoices') or cc_has_module(company_id, 'supplier_invoices'));
