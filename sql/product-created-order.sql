-- Preserve known historical dates. Never invent dates for undated imports.
create or replace function laundry_private.product_legacy_created(g jsonb)
returns timestamptz language plpgsql immutable set search_path='' as $$
declare value text; d date;
begin
 value:=coalesce(nullif(g#>>'{raw,DATA DI CREAZIONE}',''),nullif(g#>>'{raw,DATA}',''));
 if value !~ '^\d{2}/\d{2}/\d{4}$' then return null; end if;
 d:=to_date(value,'DD/MM/YYYY');
 if to_char(d,'DD/MM/YYYY')<>value then return null; end if;
 return d::timestamp at time zone 'Europe/Rome';
exception when others then return null;
end $$;
revoke all on function laundry_private.product_legacy_created(jsonb) from public,anon,authenticated;
alter table public.laundry_products add column created_at timestamptz;
alter table public.laundry_products alter column created_at set default clock_timestamp();
create or replace function laundry_private.guard_product_created()
returns trigger language plpgsql set search_path='' as $$
begin
 if TG_OP='INSERT' then new.created_at:=clock_timestamp();
 else new.created_at:=coalesce(old.created_at,laundry_private.product_legacy_created(old.data)); end if;
 if new.created_at is not null then
  new.data:=jsonb_set(new.data,'{raw}',coalesce(nullif(new.data->'raw','null'::jsonb),'{}'::jsonb)||jsonb_build_object('DATA DI CREAZIONE',to_char(new.created_at at time zone 'Europe/Rome','DD/MM/YYYY'),'DATA',to_char(new.created_at at time zone 'Europe/Rome','DD/MM/YYYY')));
 elsif TG_OP='UPDATE' then
  new.data:=jsonb_set(new.data,'{raw}',(coalesce(new.data->'raw','{}')-'DATA DI CREAZIONE'-'DATA')||jsonb_strip_nulls(jsonb_build_object('DATA DI CREAZIONE',old.data#>'{raw,DATA DI CREAZIONE}','DATA',old.data#>'{raw,DATA}')));
 end if;
 return new;
end $$;
revoke all on function laundry_private.guard_product_created() from public,anon,authenticated;
create trigger guard_product_created before insert or update on public.laundry_products
for each row execute function laundry_private.guard_product_created();
create index laundry_products_created_order on public.laundry_products(created_at desc nulls last,id);
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('laundry_private.products_query(jsonb)'::regprocedure);
 if position('select g.id,g.data from public.laundry_products g' in definition)=0 or position('order by id offset offst limit lim' in definition)=0 then raise exception 'PRODUCT_QUERY_CHANGED';end if;
 definition:=replace(definition,'select g.id,g.data from public.laundry_products g','select g.id,g.data,coalesce(g.created_at,laundry_private.product_legacy_created(g.data)) as created_at from public.laundry_products g');
 definition:=replace(definition,'order by id offset offst limit lim','order by created_at desc nulls last,id offset offst limit lim');
 definition:=replace(definition,'end order by id) from paged','end order by created_at desc nulls last,id) from paged');
 execute definition;
end $$;
update public.laundry_meta set revision=revision+1 where id;
