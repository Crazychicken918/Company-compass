-- ============ WAVE 31: Settings tab (company name/trading-as, PAYE/SDL/UIF registered toggles) ============
-- The Settings tab (relocated from Team) can now edit the company name, and a new "Trading as"
-- field, plus PAYE/SDL/UIF "registered" toggles mirroring the existing VAT-registered toggle.
-- Those three toggles are visibility-only: they show/hide their reference-number field on
-- Settings and have no effect on how PAYE/SDL/UIF are calculated or displayed elsewhere.
-- No new RLS is needed — these are columns on the already-covered cc_companies table.

alter table cc_companies add column if not exists trading_as text;
alter table cc_companies add column if not exists paye_registered boolean not null default true;
alter table cc_companies add column if not exists sdl_registered boolean not null default true;
alter table cc_companies add column if not exists uif_registered boolean not null default true;

-- ---------- verify ----------
select column_name, data_type, column_default from information_schema.columns
  where table_name = 'cc_companies' and column_name in ('trading_as','paye_registered','sdl_registered','uif_registered')
  order by column_name;
