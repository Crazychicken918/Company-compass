-- Wave 51: automatic overdue invoice reminders
alter table cc_companies add column if not exists reminders_enabled boolean not null default false;
alter table cc_companies add column if not exists reminder_days integer[] not null default '{7,14,30}';
alter table cc_companies add column if not exists reminder_note text;
alter table cc_clients add column if not exists no_reminders boolean not null default false;
create table if not exists cc_reminder_log (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  invoice_id uuid not null,
  client_id uuid,
  stage integer not null default 0,
  trigger text not null default 'auto',
  sent_to text,
  status text not null default 'pending' check (status in ('pending','sent','failed')),
  error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
-- one automatic reminder per invoice per stage, however often the job runs
create unique index if not exists cc_reminder_log_auto_stage on cc_reminder_log(invoice_id, stage) where trigger = 'auto';
create index if not exists cc_reminder_log_company_idx on cc_reminder_log(company_id, created_at desc);
alter table cc_reminder_log enable row level security;
drop policy if exists "reminder_log_select" on cc_reminder_log;
create policy "reminder_log_select" on cc_reminder_log for select using (cc_is_member(company_id));
-- (rows are written only by the send-reminders edge function with the service role)

-- daily schedule: 07:00 South African time (05:00 UTC)
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;
select cron.unschedule('cc-send-reminders') where exists (select 1 from cron.job where jobname = 'cc-send-reminders');
select cron.schedule('cc-send-reminders', '0 5 * * *', $$
  select net.http_post(
    url := 'https://fejcuijyskosvdxkgupo.supabase.co/functions/v1/send-reminders',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
$$);
