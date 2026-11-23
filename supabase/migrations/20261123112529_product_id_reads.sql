-- Retrieve selected label/save products by primary key; do not scan the whole archive.
CREATE OR REPLACE FUNCTION laundry_private.products_query(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare identity jsonb; result jsonb; rows jsonb; total bigint; lim int; offst int;
begin
 identity:=laundry_private.laundry_authenticated('version','{}');
 if p ? 'revision' and (p->>'revision')::bigint<>(identity->>'revision')::bigint then raise exception 'REVISION_CONFLICT';end if;
 if p->>'mode'='lookup' then
  result:=laundry_private.tag_lookup(p->>'code');
  return jsonb_build_object('rows',case when result is null then '[]'::jsonb else jsonb_build_array(result) end,'revision',identity->'revision');
 end if;
 if p->>'mode'='meta' then
  return jsonb_build_object('revision',identity->'revision','total',(select count(*) from public.laundry_products),'clients',coalesce((select jsonb_object_agg(name,stats) from (select data->>'client' name,jsonb_build_object('total',count(*),'rent',count(*) filter(where data->>'rental'='true'),'owned',count(*) filter(where data->>'rental'='false'),'unknown',count(*) filter(where data->>'rental' is null)) stats from public.laundry_products where data->>'client' is not null group by data->>'client') q),'{}'),'facets',coalesce((select jsonb_object_agg(k,vals) from (select k,jsonb_agg(v order by v) vals from (select distinct x.key k,x.value v from public.laundry_products g cross join lateral (values ('client',g.data->>'client'),('type',g.data->>'type'),('size',g.data->>'size'),('color',g.data->>'color'),('dept',g.data->>'dept')) x(key,value) where x.value<>'') a group by k) b),'{}'),'rawKeys',coalesce((select jsonb_agg(k order by k) from (select distinct jsonb_object_keys(coalesce(data->'raw','{}')) k from public.laundry_products) q),'[]'));
 end if;
 lim:=greatest(1,least(1000,coalesce((p->>'limit')::int,50)));offst:=greatest(0,coalesce((p->>'offset')::int,0));
 if p ? 'ids' then
  if jsonb_typeof(p->'ids') is distinct from 'array' then raise exception 'INVALID_PRODUCT_IDS';end if;
  with matched as materialized (
   select g.id,g.data,coalesce(g.created_at,laundry_private.product_legacy_created(g.data)) as created_at
   from (select distinct jsonb_array_elements_text(p->'ids') id) requested
   join public.laundry_products g on g.id=requested.id
   where laundry_private.product_matches(g.data,p-'ids')
  ), paged as (select * from matched order by created_at desc nulls last,id offset offst limit lim)
  select (select count(*) from matched),coalesce((select jsonb_agg(case when p->>'mode'='ids' then to_jsonb(id) else data end order by created_at desc nulls last,id) from paged),'[]') into total,rows;
  return jsonb_build_object('rows',rows,'total',total,'revision',identity->'revision');
 end if;
 with matched as materialized (select g.id,g.data,coalesce(g.created_at,laundry_private.product_legacy_created(g.data)) as created_at from public.laundry_products g where laundry_private.product_matches(g.data,p)), paged as (select * from matched order by created_at desc nulls last,id offset offst limit lim)
 select (select count(*) from matched),coalesce((select jsonb_agg(case when p->>'mode'='ids' then to_jsonb(id) else data end order by created_at desc nulls last,id) from paged),'[]') into total,rows;
 return jsonb_build_object('rows',rows,'total',total,'revision',identity->'revision');
end $function$

