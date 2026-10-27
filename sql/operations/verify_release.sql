-- Read-only post-deployment verification, never performs application writes.
-- psql -X -v ON_ERROR_STOP=1 -f sql/operations/verify_release.sql
\set ON_ERROR_STOP on
begin read only;
do $verify$
declare expected record; actual text;
begin
 if not exists(select 1 from supabase_migrations.schema_migrations where version='20261027090941') then raise exception 'RELEASE_HISTORY_MISSING';end if;
 if not exists(select 1 from laundry_private.core_release where version='20261027090941') then raise exception 'CORE_RELEASE_MISSING';end if;
 for expected in select key,value from laundry_private.core_release r cross join lateral jsonb_each_text(r.function_hashes) loop
  select encode(sha256(convert_to(pg_get_functiondef(to_regprocedure(expected.key)),'UTF8')),'hex') into actual;
  if actual is distinct from expected.value then raise exception 'FUNCTION_DRIFT: %',expected.key;end if;
 end loop;
 if has_function_privilege('anon','public.laundry_app(text,jsonb)','EXECUTE')
  or has_function_privilege('authenticated','laundry_private.laundry_core(jsonb,text,jsonb)','EXECUTE')
  or has_function_privilege('authenticated','laundry_private.designate_super_admin(uuid,text)','EXECUTE') then raise exception 'UNSAFE_FUNCTION_PRIVILEGES';end if;
 if not exists(select 1 from laundry_private.laundry_super_admin sa join auth.users u on u.id=sa.confirmed_user_id and lower(u.email)=sa.email join public.laundry_members m on m.email=sa.email where sa.confirmed_at is not null and m.active and m.role='admin' and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and (u.banned_until is null or u.banned_until<=now())) then raise exception 'EXPLICIT_SUPER_ADMIN_DESIGNATION_REQUIRED';end if;
 if not exists(select 1 from pg_trigger where tgrelid='public.laundry_lots'::regclass and tgname='validate_lot_flow' and tgenabled='O') then raise exception 'LOT_GUARD_MISSING';end if;
 if not exists(select 1 from pg_trigger where tgrelid='public.laundry_products'::regclass and tgname='guard_product_barcode' and tgenabled='O') then raise exception 'BARCODE_GUARD_MISSING';end if;
end;$verify$;
select version,installed_at from laundry_private.core_release;
commit;
