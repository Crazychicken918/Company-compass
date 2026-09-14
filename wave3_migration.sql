-- Company Compass: Wave 3 — Scenario Planner (what-if scenarios: supplier
-- comparisons, loan NPV/IRR, and general scenarios), with generated cash
-- flow line items per scenario.
-- Idempotent — safe to run multiple times.

-- ---------- scenarios ----------
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
drop policy if exists "management select scenarios" on cc_scenarios;
create policy "management select scenarios" on cc_scenarios for select using (cc_is_admin(company_id) or cc_can_approve(company_id));
drop policy if exists "management write scenarios" on cc_scenarios;
create policy "management write scenarios" on cc_scenarios for insert with check (cc_is_admin(company_id) or cc_can_approve(company_id));
drop policy if exists "management update scenarios" on cc_scenarios;
create policy "management update scenarios" on cc_scenarios for update using (cc_is_admin(company_id) or cc_can_approve(company_id));
drop policy if exists "management delete scenarios" on cc_scenarios;
create policy "management delete scenarios" on cc_scenarios for delete using (cc_is_admin(company_id) or cc_can_approve(company_id));

-- ---------- generated cash flow lines per scenario ----------
create table if not exists cc_scenario_cashflows (
  id uuid primary key default gen_random_uuid(),
  scenario_id uuid not null references cc_scenarios(id) on delete cascade,
  period_number integer not null,
  label text,
  amount numeric not null default 0,
  created_at timestamptz not null default now()
);
alter table cc_scenario_cashflows enable row level security;
drop policy if exists "management select scenario cashflows" on cc_scenario_cashflows;
create policy "management select scenario cashflows" on cc_scenario_cashflows for select using (
  exists (select 1 from cc_scenarios s where s.id = scenario_id and (cc_is_admin(s.company_id) or cc_can_approve(s.company_id)))
);
drop policy if exists "management write scenario cashflows" on cc_scenario_cashflows;
create policy "management write scenario cashflows" on cc_scenario_cashflows for insert with check (
  exists (select 1 from cc_scenarios s where s.id = scenario_id and (cc_is_admin(s.company_id) or cc_can_approve(s.company_id)))
);
drop policy if exists "management update scenario cashflows" on cc_scenario_cashflows;
create policy "management update scenario cashflows" on cc_scenario_cashflows for update using (
  exists (select 1 from cc_scenarios s where s.id = scenario_id and (cc_is_admin(s.company_id) or cc_can_approve(s.company_id)))
);
drop policy if exists "management delete scenario cashflows" on cc_scenario_cashflows;
create policy "management delete scenario cashflows" on cc_scenario_cashflows for delete using (
  exists (select 1 from cc_scenarios s where s.id = scenario_id and (cc_is_admin(s.company_id) or cc_can_approve(s.company_id)))
);

-- ---------- verify ----------
select table_name, column_name from information_schema.columns
where table_name in ('cc_scenarios','cc_scenario_cashflows')
order by table_name, ordinal_position;
