-- Wave 56: "Pay now" links on invoices (Yoco online payments)
-- The owner's Yoco secret key lives here. RLS is on with NO policies, so the app (anon/authenticated
-- roles) can never read it; only the edge functions (service role) can. The app writes it and reads
-- its status through the two security-definer functions below, which check for management access.
create table if not exists cc_payment_settings (
  company_id uuid primary key references cc_companies(id) on delete cascade,
  provider text not null default 'yoco',
  secret_key text,
  webhook_id text,
  webhook_secret text,
  enabled boolean not null default false,
  mode text,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table cc_payment_settings enable row level security;

create or replace function cc_payment_status(p_company uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not cc_is_member(p_company) then null else coalesce(
    (select jsonb_build_object('provider', provider, 'enabled', enabled, 'has_key', secret_key is not null,
        'has_webhook', webhook_secret is not null, 'mode', mode,
        'key_hint', case when secret_key is null then null else left(secret_key, 8) || '…' || right(secret_key, 4) end,
        'updated_at', updated_at)
     from cc_payment_settings where company_id = p_company),
    jsonb_build_object('enabled', false, 'has_key', false, 'has_webhook', false)) end;
$$;

create or replace function cc_set_payment_settings(p_company uuid, p_secret_key text, p_webhook_secret text, p_enabled boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not cc_is_admin(p_company) then raise exception 'Only management can change payment settings'; end if;
  insert into cc_payment_settings (company_id, secret_key, webhook_secret, enabled, mode, updated_at, updated_by)
  values (p_company, nullif(trim(p_secret_key), ''), nullif(trim(p_webhook_secret), ''), coalesce(p_enabled, false),
          case when p_secret_key like 'sk_test%' then 'test' when p_secret_key like 'sk_live%' then 'live' end, now(), auth.uid())
  on conflict (company_id) do update set
    secret_key = coalesce(nullif(trim(p_secret_key), ''), cc_payment_settings.secret_key),
    webhook_secret = coalesce(nullif(trim(p_webhook_secret), ''), cc_payment_settings.webhook_secret),
    webhook_id = case when nullif(trim(p_secret_key), '') is not null and p_secret_key is distinct from cc_payment_settings.secret_key then null else cc_payment_settings.webhook_id end,
    enabled = coalesce(p_enabled, cc_payment_settings.enabled),
    mode = case when nullif(trim(p_secret_key), '') is null then cc_payment_settings.mode
                when p_secret_key like 'sk_test%' then 'test' when p_secret_key like 'sk_live%' then 'live' else cc_payment_settings.mode end,
    updated_at = now(), updated_by = auth.uid();
end;
$$;

create or replace function cc_clear_payment_settings(p_company uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not cc_is_admin(p_company) then raise exception 'Only management can change payment settings'; end if;
  update cc_payment_settings set secret_key = null, webhook_secret = null, webhook_id = null, enabled = false, mode = null,
    updated_at = now(), updated_by = auth.uid() where company_id = p_company;
  update cc_payment_links set status = 'cancelled' where company_id = p_company and status = 'open';
end;
$$;

revoke all on function cc_payment_status(uuid) from public, anon;
revoke all on function cc_set_payment_settings(uuid, text, text, boolean) from public, anon;
revoke all on function cc_clear_payment_settings(uuid) from public, anon;
grant execute on function cc_payment_status(uuid) to authenticated;
grant execute on function cc_set_payment_settings(uuid, text, text, boolean) to authenticated;
grant execute on function cc_clear_payment_settings(uuid) to authenticated;

create table if not exists cc_payment_links (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  invoice_id uuid not null,
  provider text not null default 'yoco',
  checkout_id text,
  url text,
  amount numeric not null,
  status text not null default 'open' check (status in ('open','paid','cancelled','expired')),
  payment_ref text,
  created_by uuid,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create unique index if not exists cc_payment_links_checkout_uniq on cc_payment_links(checkout_id) where checkout_id is not null;
create index if not exists cc_payment_links_company_idx on cc_payment_links(company_id, invoice_id);
alter table cc_payment_links enable row level security;
drop policy if exists "payment_links_select" on cc_payment_links;
create policy "payment_links_select" on cc_payment_links for select using (cc_is_member(company_id));
drop policy if exists "payment_links_update" on cc_payment_links;
create policy "payment_links_update" on cc_payment_links for update using (cc_has_module(company_id, 'invoices')) with check (cc_has_module(company_id, 'invoices'));
-- (links are created and marked paid only by the payment-link / yoco-webhook edge functions)
