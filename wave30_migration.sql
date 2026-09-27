-- ============ WAVE 30: service-provider (no inventory) toggle ============
-- A company-level setting so a pure service provider (nothing to stock) can turn off the
-- Stock tab and the stock-item column on Invoice/Supplier Invoice line items app-wide.
-- Defaults to true so every existing company keeps seeing Stock exactly as before.

alter table cc_companies add column if not exists tracks_inventory boolean not null default true;

-- ---------- verify ----------
select column_name, data_type, column_default from information_schema.columns
  where table_name = 'cc_companies' and column_name = 'tracks_inventory';
