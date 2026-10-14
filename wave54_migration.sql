-- Wave 54: recurring bills, purchase orders, foreign-currency prepayments
alter table cc_supplier_invoices add column if not exists is_recurring boolean not null default false;
alter table cc_supplier_invoices add column if not exists recurrence_frequency text;
alter table cc_supplier_invoices add column if not exists recurrence_next_date date;
alter table cc_supplier_invoices add column if not exists recurrence_end_date date;

alter table cc_party_credits add column if not exists currency text not null default 'ZAR';
alter table cc_party_credits add column if not exists foreign_amount numeric;
alter table cc_party_credits add column if not exists exchange_rate numeric not null default 1;
alter table cc_credit_allocations add column if not exists foreign_amount numeric;
alter table cc_credit_allocations add column if not exists cleared_amount numeric;

create table if not exists cc_purchase_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references cc_companies(id) on delete cascade,
  supplier_id uuid not null,
  po_number text not null,
  order_date date not null,
  expected_date date,
  status text not null default 'draft' check (status in ('draft','sent','billed','cancelled')),
  currency text not null default 'ZAR',
  exchange_rate numeric not null default 1,
  notes text,
  bill_id uuid,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists cc_purchase_orders_company_idx on cc_purchase_orders(company_id);
alter table cc_purchase_orders enable row level security;
drop policy if exists "po_select" on cc_purchase_orders;
create policy "po_select" on cc_purchase_orders for select using (cc_is_member(company_id));
drop policy if exists "po_insert" on cc_purchase_orders;
create policy "po_insert" on cc_purchase_orders for insert with check (cc_has_module(company_id, 'supplier_invoices'));
drop policy if exists "po_update" on cc_purchase_orders;
create policy "po_update" on cc_purchase_orders for update using (cc_has_module(company_id, 'supplier_invoices')) with check (cc_has_module(company_id, 'supplier_invoices'));
drop policy if exists "po_delete" on cc_purchase_orders;
create policy "po_delete" on cc_purchase_orders for delete using (cc_is_admin(company_id));

create table if not exists cc_purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references cc_purchase_orders(id) on delete cascade,
  description text not null,
  quantity numeric not null default 1,
  unit_price numeric not null default 0,
  vat_applicable boolean not null default false,
  stock_item_id uuid
);
create index if not exists cc_purchase_order_items_po_idx on cc_purchase_order_items(purchase_order_id);
alter table cc_purchase_order_items enable row level security;
drop policy if exists "po_items_select" on cc_purchase_order_items;
create policy "po_items_select" on cc_purchase_order_items for select using (exists (select 1 from cc_purchase_orders p where p.id = purchase_order_id and cc_is_member(p.company_id)));
drop policy if exists "po_items_write" on cc_purchase_order_items;
create policy "po_items_write" on cc_purchase_order_items for all using (exists (select 1 from cc_purchase_orders p where p.id = purchase_order_id and cc_has_module(p.company_id, 'supplier_invoices'))) with check (exists (select 1 from cc_purchase_orders p where p.id = purchase_order_id and cc_has_module(p.company_id, 'supplier_invoices')));
