-- ============ WAVE 28: supplier credit note attachments + accounting period lock ============

-- ---------- Supplier credit notes can now carry attachments too (documents received from suppliers) ----------
alter table cc_attachments drop constraint if exists cc_attachments_entity_type_check;
alter table cc_attachments add constraint cc_attachments_entity_type_check
  check (entity_type in ('revenue','expense','invoice','supplier_invoice','supplier_credit_note'));

-- ---------- Accounting period lock ----------
-- Single "locked through" cutoff date per company (Xero/QuickBooks-style closing date).
-- Anything dated on or before it can't be created or deleted for the core transaction tables.
alter table cc_companies add column if not exists locked_through_date date;

create or replace function cc_period_locked(target_company_id uuid, tx_date date)
returns boolean
language sql
security definer
stable
as $$
  select coalesce(
    (select locked_through_date >= tx_date from cc_companies where id = target_company_id),
    false
  );
$$;

-- Restrictive policies AND with whatever permissive policy already granted access, so none
-- of the existing (multiple, overlapping) insert/update/delete policies need to change.
-- Only INSERT and DELETE are gated — approvals, status changes, and payments on records that
-- already exist are left alone, since those aren't backdating or removing historical postings.

drop policy if exists "period lock blocks insert" on cc_entries;
create policy "period lock blocks insert" on cc_entries as restrictive for insert
  with check (not cc_period_locked(company_id, entry_date));
drop policy if exists "period lock blocks delete" on cc_entries;
create policy "period lock blocks delete" on cc_entries as restrictive for delete
  using (not cc_period_locked(company_id, entry_date));

drop policy if exists "period lock blocks insert" on cc_invoices;
create policy "period lock blocks insert" on cc_invoices as restrictive for insert
  with check (not cc_period_locked(company_id, issue_date));
drop policy if exists "period lock blocks delete" on cc_invoices;
create policy "period lock blocks delete" on cc_invoices as restrictive for delete
  using (not cc_period_locked(company_id, issue_date));

drop policy if exists "period lock blocks insert" on cc_credit_notes;
create policy "period lock blocks insert" on cc_credit_notes as restrictive for insert
  with check (not cc_period_locked(company_id, issue_date));
drop policy if exists "period lock blocks delete" on cc_credit_notes;
create policy "period lock blocks delete" on cc_credit_notes as restrictive for delete
  using (not cc_period_locked(company_id, issue_date));

drop policy if exists "period lock blocks insert" on cc_supplier_invoices;
create policy "period lock blocks insert" on cc_supplier_invoices as restrictive for insert
  with check (not cc_period_locked(company_id, issue_date));
drop policy if exists "period lock blocks delete" on cc_supplier_invoices;
create policy "period lock blocks delete" on cc_supplier_invoices as restrictive for delete
  using (not cc_period_locked(company_id, issue_date));

drop policy if exists "period lock blocks insert" on cc_supplier_credit_notes;
create policy "period lock blocks insert" on cc_supplier_credit_notes as restrictive for insert
  with check (not cc_period_locked(company_id, issue_date));
drop policy if exists "period lock blocks delete" on cc_supplier_credit_notes;
create policy "period lock blocks delete" on cc_supplier_credit_notes as restrictive for delete
  using (not cc_period_locked(company_id, issue_date));

-- ---------- verify ----------
select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'cc_attachments'::regclass and contype = 'c';
select column_name from information_schema.columns where table_name = 'cc_companies' and column_name = 'locked_through_date';
select tablename, policyname, permissive, cmd from pg_policies where policyname like 'period lock%' order by tablename, cmd;
