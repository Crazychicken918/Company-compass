-- Wave 64: invoice discounts. The invoice keeps the discount the user chose (a % of the invoice or a Rand
-- amount); the discount itself is stored as negative "discount" lines, one per sales account and VAT
-- treatment, so every total, VAT figure, balance and report already includes it.
alter table public.cc_invoices add column if not exists discount_type text;
alter table public.cc_invoices drop constraint if exists cc_invoices_discount_type_check;
alter table public.cc_invoices add constraint cc_invoices_discount_type_check check (discount_type is null or discount_type in ('percent','amount'));
alter table public.cc_invoices add column if not exists discount_value numeric;
alter table public.cc_invoice_items add column if not exists is_discount boolean not null default false;
