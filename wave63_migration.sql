-- Wave 63: commission-based workers (no PAYE, UIF or SDL), commission rules per client (once-off or
-- rolling; % of invoiced, % of received, or a fixed amount), and the expense account each payslip goes to.
alter table public.cc_employees add column if not exists worker_type text not null default 'employee';
alter table public.cc_employees drop constraint if exists cc_employees_worker_type_check;
alter table public.cc_employees add constraint cc_employees_worker_type_check check (worker_type in ('employee','commission'));
alter table public.cc_employees add column if not exists expense_account_key text;

alter table public.cc_payroll_payments add column if not exists worker_type text not null default 'employee';
alter table public.cc_payroll_payments add column if not exists expense_account_key text;
alter table public.cc_payroll_payments add column if not exists commission_lines jsonb;
alter table public.cc_payroll_payments add column if not exists period_start date;
alter table public.cc_payroll_payments add column if not exists period_end date;

create table if not exists public.cc_commission_rules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.cc_companies(id) on delete cascade,
  employee_id uuid not null references public.cc_employees(id) on delete cascade,
  client_id uuid references public.cc_clients(id) on delete set null,
  description text,
  basis text not null default 'invoiced' check (basis in ('invoiced','received','fixed')),
  rate numeric not null default 0 check (rate >= 0 and rate <= 100),
  amount numeric not null default 0 check (amount >= 0),
  recurrence text not null default 'rolling' check (recurrence in ('once','rolling')),
  start_date date not null default current_date,
  end_date date,
  active boolean not null default true,
  used_payslip_id uuid references public.cc_payroll_payments(id) on delete set null,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists cc_commission_rules_emp_idx on public.cc_commission_rules(employee_id);
alter table public.cc_commission_rules enable row level security;
drop policy if exists "members select commission rules" on public.cc_commission_rules;
create policy "members select commission rules" on public.cc_commission_rules for select using (cc_is_member(company_id));
drop policy if exists "scoped insert commission rules" on public.cc_commission_rules;
create policy "scoped insert commission rules" on public.cc_commission_rules for insert with check (cc_has_module(company_id, 'payroll'));
drop policy if exists "scoped update commission rules" on public.cc_commission_rules;
create policy "scoped update commission rules" on public.cc_commission_rules for update using (cc_has_module(company_id, 'payroll'));
drop policy if exists "scoped delete commission rules" on public.cc_commission_rules;
create policy "scoped delete commission rules" on public.cc_commission_rules for delete using (cc_has_module(company_id, 'payroll'));
