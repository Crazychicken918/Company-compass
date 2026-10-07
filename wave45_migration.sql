
-- ============================================================
-- Wave 45: company tax computation adjustments
-- ============================================================
create table if not exists cc_tax_adjustments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  fy_end date not null,
  kind text not null check (kind in ('addback','deduction','assessed_loss')),
  label text not null,
  amount numeric not null,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);
alter table cc_tax_adjustments enable row level security;
drop policy if exists "members select tax adjustments" on cc_tax_adjustments;
create policy "members select tax adjustments" on cc_tax_adjustments for select using (cc_is_member(company_id));
drop policy if exists "admin insert tax adjustments" on cc_tax_adjustments;
create policy "admin insert tax adjustments" on cc_tax_adjustments for insert with check (cc_is_admin(company_id));
drop policy if exists "admin update tax adjustments" on cc_tax_adjustments;
create policy "admin update tax adjustments" on cc_tax_adjustments for update using (cc_is_admin(company_id));
drop policy if exists "admin delete tax adjustments" on cc_tax_adjustments;
create policy "admin delete tax adjustments" on cc_tax_adjustments for delete using (cc_is_admin(company_id));
