-- Wave 61: banking details on invoices, draft invoices, invoice currencies
-- Banking details live on the company's bank accounts; one can be marked as the default shown on invoices.
alter table cc_accounts add column if not exists bank_name text;
alter table cc_accounts add column if not exists account_holder text;
alter table cc_accounts add column if not exists account_number text;
alter table cc_accounts add column if not exists branch_code text;
alter table cc_accounts add column if not exists swift_code text;
alter table cc_accounts add column if not exists show_on_invoices boolean not null default false;
-- Which account's details an invoice shows (null = the company default), or none at all.
alter table cc_invoices add column if not exists bank_account_id uuid references cc_accounts(id) on delete set null;
alter table cc_invoices add column if not exists hide_bank_details boolean not null default false;
-- Drafts: an unapproved invoice with no submitted_at has not been sent for approval yet. Existing and
-- newly inserted rows default to "submitted", so only an explicit "Save as draft" creates a draft.
alter table cc_invoices add column if not exists submitted_at timestamptz default now();
-- The app offers nine currencies; the database only allowed four, so e.g. an AUD invoice failed to save.
alter table cc_invoices drop constraint if exists cc_invoices_currency_check;
alter table cc_invoices add constraint cc_invoices_currency_check check (currency in ('ZAR','USD','GBP','EUR','AUD','CAD','CHF','CNY','JPY'));
alter table cc_credit_notes drop constraint if exists cc_credit_notes_currency_check;
alter table cc_credit_notes add constraint cc_credit_notes_currency_check check (currency in ('ZAR','USD','GBP','EUR','AUD','CAD','CHF','CNY','JPY'));
-- Each invoice / credit note line can go to its own sales (revenue) account; null = Sales Revenue (4000).
alter table cc_invoice_items add column if not exists account_key text;
alter table cc_credit_note_items add column if not exists account_key text;
alter table cc_quote_items add column if not exists account_key text;
-- The colour used on invoices (table header row, totals highlight, accents). Null = the app's violet.
alter table cc_companies add column if not exists invoice_color text check (invoice_color is null or invoice_color ~ '^#[0-9a-fA-F]{6}$');
-- Invoice template fields (letterhead tagline and website, client contact / VAT / reference / group / payment
-- terms, supplier registration and payment terms, per-invoice customer ref, billing period and payment terms,
-- and a second "details" line on each invoice line).
alter table cc_companies add column if not exists tagline text;
alter table cc_companies add column if not exists website text;
alter table cc_clients add column if not exists contact_person text;
alter table cc_clients add column if not exists vat_number text;
alter table cc_clients add column if not exists account_ref text;
alter table cc_clients add column if not exists client_group text;
alter table cc_clients add column if not exists payment_method text check (payment_method is null or payment_method in ('eft','debit_order','card','cash'));
alter table cc_clients add column if not exists payment_terms_days integer check (payment_terms_days is null or payment_terms_days between 0 and 365);
alter table cc_suppliers add column if not exists registration_number text;
alter table cc_suppliers add column if not exists vat_number text;
alter table cc_suppliers add column if not exists contact_person text;
alter table cc_suppliers add column if not exists payment_method text check (payment_method is null or payment_method in ('eft','debit_order','card','cash'));
alter table cc_suppliers add column if not exists payment_terms_days integer check (payment_terms_days is null or payment_terms_days between 0 and 365);
alter table cc_invoices add column if not exists customer_ref text;
alter table cc_invoices add column if not exists billing_period text;
alter table cc_invoices add column if not exists payment_method text check (payment_method is null or payment_method in ('eft','debit_order','card','cash'));
alter table cc_invoices add column if not exists payment_terms text;
alter table cc_invoice_items add column if not exists details text;
alter table cc_quote_items add column if not exists details text;

-- Quotes follow the invoice template and flow: customer reference, when the client accepted or declined,
-- the reason for a decline, and when the quote was sent.
alter table public.cc_quotes add column if not exists customer_ref text;
alter table public.cc_quotes add column if not exists responded_at timestamptz;
alter table public.cc_quotes add column if not exists decline_reason text;
alter table public.cc_quotes add column if not exists sent_at timestamptz;
