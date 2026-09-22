-- ============ WAVE 27: attachments, audit log, CSV export/import, bank reconciliation, VAT201/reg-number quick wins ============

-- ---------- Quick wins ----------
-- Company registration number field already existed on cc_companies; VAT category for VAT201 period scoping.
alter table cc_companies add column if not exists vat_category text not null default 'A' check (vat_category in ('A','B'));

-- ---------- Document/receipt attachments ----------
-- storage bucket for receipts/documents attached to revenue, expense, invoice and supplier-invoice records.
insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

create policy "members view attachment files" on storage.objects for select
  using (bucket_id = 'documents' and cc_is_member((storage.foldername(name))[1]::uuid));
create policy "members upload attachment files" on storage.objects for insert
  with check (bucket_id = 'documents' and cc_is_member((storage.foldername(name))[1]::uuid));
create policy "admin delete attachment files" on storage.objects for delete
  using (bucket_id = 'documents' and cc_is_admin((storage.foldername(name))[1]::uuid));

create table if not exists cc_attachments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  entity_type text not null check (entity_type in ('revenue','expense','invoice','supplier_invoice')),
  entity_id uuid not null,
  file_path text not null,
  file_name text not null,
  uploaded_by text,
  created_at timestamptz default now()
);
alter table cc_attachments enable row level security;

create policy "members select attachments" on cc_attachments for select using (cc_is_member(company_id));
create policy "members insert attachments" on cc_attachments for insert with check (cc_is_member(company_id));
create policy "admin delete attachments" on cc_attachments for delete using (cc_is_admin(company_id));

-- ---------- Activity/audit log ----------
create table if not exists cc_audit_log (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  user_email text,
  action text not null check (action in ('create','update','delete')),
  entity_type text not null,
  entity_id uuid,
  summary text,
  created_at timestamptz default now()
);
alter table cc_audit_log enable row level security;

create policy "admin select audit log" on cc_audit_log for select using (cc_is_admin(company_id));
create policy "members insert audit log" on cc_audit_log for insert with check (cc_is_member(company_id));

-- ---------- Bank statement import + reconciliation ----------
create table if not exists cc_bank_transactions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  tx_date date not null,
  description text,
  amount numeric not null,
  status text not null default 'unmatched' check (status in ('unmatched','matched','ignored')),
  matched_entry_type text,
  matched_entry_id uuid,
  created_at timestamptz default now()
);
alter table cc_bank_transactions enable row level security;

create policy "members select bank transactions" on cc_bank_transactions for select using (cc_is_member(company_id));
create policy "members insert bank transactions" on cc_bank_transactions for insert with check (cc_is_member(company_id));
create policy "members update bank transactions" on cc_bank_transactions for update using (cc_is_member(company_id));
create policy "admin delete bank transactions" on cc_bank_transactions for delete using (cc_is_admin(company_id));

-- ---------- verify ----------
select column_name from information_schema.columns where table_name = 'cc_companies' and column_name in ('vat_category');
select tablename, count(*) as policy_count from pg_policies where tablename = 'cc_attachments' group by tablename;
select tablename, count(*) as policy_count from pg_policies where tablename = 'cc_audit_log' group by tablename;
select tablename, count(*) as policy_count from pg_policies where tablename = 'cc_bank_transactions' group by tablename;
select id, public from storage.buckets where id = 'documents';
