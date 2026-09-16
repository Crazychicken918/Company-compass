-- Company Compass: Wave 5 — depreciation method on the Fixed Asset Register
-- (straight-line or reducing balance, chosen per fixed asset), plus the
-- non-cash depreciation fix on the Cash Flow Statement and the Debtors/
-- Creditors tab split (those two are index.html-only, no schema change).
-- Idempotent — safe to run multiple times.

alter table cc_assets add column if not exists depreciation_method text default 'straight_line' check (depreciation_method is null or depreciation_method in ('straight_line','reducing_balance'));
alter table cc_assets add column if not exists depreciation_rate numeric;

-- ---------- verify ----------
select column_name, data_type, column_default from information_schema.columns
where table_name = 'cc_assets' and column_name in ('depreciation_method','depreciation_rate')
order by column_name;
