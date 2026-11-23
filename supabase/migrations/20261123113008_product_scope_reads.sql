CREATE INDEX IF NOT EXISTS laundry_products_client_filter ON public.laundry_products ((data->>'client'));
CREATE INDEX IF NOT EXISTS laundry_products_rental_filter ON public.laundry_products ((data->>'rental'));
CREATE INDEX IF NOT EXISTS laundry_products_effective_order ON public.laundry_products ((coalesce(created_at,laundry_private.product_legacy_created(data))) DESC NULLS LAST,id);
CREATE OR REPLACE FUNCTION laundry_private.products_query(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare identity jsonb; result jsonb; rows jsonb; total bigint; lim int; offst int; where_sql text; advanced boolean;
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

 advanced:=coalesce(p->>'query','')<>''
  or exists(select 1 from jsonb_each_text(coalesce(p->'filters','{}')) f where f.value<>'')
  or jsonb_array_length(coalesce(p->'rules','[]'))>0;
 if not advanced then
  -- Only fixed SQL fragments; filter values stay bound parameters.
  where_sql:='true';
  if p ? 'client' then
   where_sql:=where_sql||case when p->>'client' is null then ' and g.data->>''client'' is null' else ' and g.data->>''client''=$1->>''client''' end;
  end if;
  if p->>'prop'='rent' then where_sql:=where_sql||' and g.data->>''rental''=''true''';
  elsif p->>'prop'='client' then where_sql:=where_sql||' and g.data->>''rental''=''false''';
  elsif p->>'prop'='unknown' then where_sql:=where_sql||' and coalesce(g.data->>''rental'','''')=''''';
  end if;
  execute 'select count(*) from public.laundry_products g where '||where_sql into total using p;
  execute 'select coalesce(jsonb_agg(case when $1->>''mode''=''ids'' then to_jsonb(id) else data end order by created_at desc nulls last,id),''[]''::jsonb)
   from (select g.id,g.data,coalesce(g.created_at,laundry_private.product_legacy_created(g.data)) created_at
    from public.laundry_products g where '||where_sql||'
    order by coalesce(g.created_at,laundry_private.product_legacy_created(g.data)) desc nulls last,g.id offset $2 limit $3) paged'
   into rows using p,offst,lim;
  return jsonb_build_object('rows',rows,'total',total,'revision',identity->'revision');
 end if;
 with matched as materialized (select g.id,g.data,coalesce(g.created_at,laundry_private.product_legacy_created(g.data)) as created_at from public.laundry_products g where laundry_private.product_matches(g.data,p)), paged as (select * from matched order by created_at desc nulls last,id offset offst limit lim)
 select (select count(*) from matched),coalesce((select jsonb_agg(case when p->>'mode'='ids' then to_jsonb(id) else data end order by created_at desc nulls last,id) from paged),'[]') into total,rows;
 return jsonb_build_object('rows',rows,'total',total,'revision',identity->'revision');
end $function$

