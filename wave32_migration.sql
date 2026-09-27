-- ============ WAVE 32: capture-time attachments + bank reconciliation <-> invoices/bills ============

-- ---------- Attachments: customer Credit Notes can now carry attachments too ----------
-- (Revenue/Expenses/Invoices/Supplier Invoices/Supplier Credit Notes already could.)
alter table cc_attachments drop constraint if exists cc_attachments_entity_type_check;
alter table cc_attachments add constraint cc_attachments_entity_type_check
  check (entity_type in ('revenue','expense','invoice','credit_note','supplier_invoice','supplier_credit_note'));

-- ---------- Bank reconciliation: track the payment record a match created ----------
-- When a bank statement line is matched to an Invoice or Supplier Invoice, matchBankTransaction()
-- now also books a payment against it (cc_invoice_payments / cc_supplier_invoice_payments). This
-- column lets unmatchBankTransaction() clean that payment back up again, rather than leaving an
-- orphaned payment behind after an Unmatch.
alter table cc_bank_transactions add column if not exists linked_payment_id uuid;

-- ---------- verify ----------
select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'cc_attachments'::regclass and contype = 'c';
select column_name, data_type from information_schema.columns where table_name = 'cc_bank_transactions' and column_name = 'linked_payment_id';
