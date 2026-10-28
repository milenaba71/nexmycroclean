-- Read-only inventory for review on a sanitized staging restore first.
\set ON_ERROR_STOP on
begin read only;
select version() as postgres_version;
select n.nspname as schema,p.oid::regprocedure as function,
 encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') as source_sha256,
 p.prosecdef as security_definer,p.proconfig as configuration,p.proacl as privileges
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='laundry_private' order by p.oid::regprocedure::text;
select schemaname,tablename,rowsecurity from pg_tables
where schemaname in ('public','laundry_private') and (tablename like 'laundry_%' or schemaname='laundry_private') order by 1,2;
select tgrelid::regclass as table_name,tgname,tgenabled,pg_get_triggerdef(oid)
from pg_trigger where not tgisinternal and tgrelid in ('public.laundry_products'::regclass,'public.laundry_lots'::regclass);
-- Absence of the history is a stop condition, never evidence that nothing ran.
select version from supabase_migrations.schema_migrations order by version;
commit;
