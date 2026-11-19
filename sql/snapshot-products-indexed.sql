-- Preserve snapshot membership; select lot/request ids by the primary key instead
-- of evaluating settings and scanning every product on every floor request.
create or replace function laundry_private.snapshot_products() returns jsonb
language plpgsql stable set search_path='' as $fn$
declare ids text[]; scope jsonb; result jsonb;
begin
 if current_setting('laundry.compact_snapshot',true) is distinct from 'on' then
  select coalesce(jsonb_agg(g.data order by g.id),'[]'::jsonb) into result from public.laundry_products g;
  return result;
 end if;
 scope:=nullif(current_setting('laundry.product_scope',true),'')::jsonb;
 select array_agg(distinct code) into ids from (
  select jsonb_array_elements_text(coalesce(nullif(current_setting('laundry.product_ids',true),''),'[]')::jsonb) code
  union select r->>'code' from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r
 ) selected;
 if scope is null then
  select coalesce(jsonb_agg(g.data order by g.id),'[]'::jsonb) into result from public.laundry_products g where g.id=any(ids);
 else
  select coalesce(jsonb_agg(g.data order by g.id),'[]'::jsonb) into result from public.laundry_products g where g.id=any(ids) or laundry_private.product_matches(g.data,scope);
 end if;
 return result;
end $fn$;
revoke all on function laundry_private.snapshot_products() from public,anon,authenticated;
do $patch$
declare definition text; original text;
begin
 definition:=pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure);
 original:=$old$coalesce((select jsonb_agg(g.data order by g.id) from public.laundry_products g where current_setting('laundry.compact_snapshot',true) is distinct from 'on' or g.id in (select jsonb_array_elements_text(coalesce(nullif(current_setting('laundry.product_ids',true),''),'[]')::jsonb)) or (nullif(current_setting('laundry.product_scope',true),'') is not null and laundry_private.product_matches(g.data,current_setting('laundry.product_scope',true)::jsonb)) or g.id in (select r->>'code' from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r)),'[]'::jsonb)$old$;
 if strpos(definition,original)=0 then raise exception 'SNAPSHOT_PATCH_SOURCE_MISMATCH';end if;
 execute replace(definition,original,'laundry_private.snapshot_products()');
end $patch$;
