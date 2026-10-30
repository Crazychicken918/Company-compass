-- Wave 65: an Items list (products and services) with their own revenue and cost-of-sales accounts.
-- Stock items become items of type 'stock'; services and non-stock products are new types.
alter table public.cc_stock_items add column if not exists item_type text not null default 'stock';
alter table public.cc_stock_items drop constraint if exists cc_stock_items_item_type_check;
alter table public.cc_stock_items add constraint cc_stock_items_item_type_check check (item_type in ('stock','non_stock','service'));
alter table public.cc_stock_items add column if not exists description text;
alter table public.cc_stock_items add column if not exists sale_price numeric not null default 0;
alter table public.cc_stock_items add column if not exists sale_vat boolean not null default true;
alter table public.cc_stock_items add column if not exists revenue_account_key text;
alter table public.cc_stock_items add column if not exists cos_account_key text;
alter table public.cc_stock_items add column if not exists active boolean not null default true;
-- The account an automatic entry is booked to (e.g. the cost of sales of a stock item when it is sold).
alter table public.cc_entries add column if not exists account_key text;
