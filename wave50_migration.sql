-- Wave 50: bank rules
create table if not exists cc_bank_rules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  name text,
  match_text text not null,
  direction text not null default 'any' check (direction in ('in','out','any')),
  amount_min numeric,
  amount_max numeric,
  action text not null default 'entry' check (action in ('entry','ignore')),
  description text,
  expense_category text default 'operating',
  vat_applicable boolean not null default false,
  tags text[] not null default '{}',
  auto_apply boolean not null default true,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists cc_bank_rules_company_idx on cc_bank_rules(company_id);
alter table cc_bank_rules enable row level security;
drop policy if exists "bank_rules_select" on cc_bank_rules;
create policy "bank_rules_select" on cc_bank_rules for select using (cc_is_member(company_id));
drop policy if exists "bank_rules_insert" on cc_bank_rules;
create policy "bank_rules_insert" on cc_bank_rules for insert with check (cc_has_module(company_id, 'revenue') or cc_has_module(company_id, 'expenses'));
drop policy if exists "bank_rules_update" on cc_bank_rules;
create policy "bank_rules_update" on cc_bank_rules for update using (cc_has_module(company_id, 'revenue') or cc_has_module(company_id, 'expenses')) with check (cc_has_module(company_id, 'revenue') or cc_has_module(company_id, 'expenses'));
drop policy if exists "bank_rules_delete" on cc_bank_rules;
create policy "bank_rules_delete" on cc_bank_rules for delete using (cc_has_module(company_id, 'revenue') or cc_has_module(company_id, 'expenses'));
