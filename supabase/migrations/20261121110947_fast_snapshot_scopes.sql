-- Fast paths for the exact scopes emitted by productsScreenScope.
-- Arbitrary filters keep using product_matches; IDs from every lot remain included.
SET lock_timeout = '2s';
DO $migration$
DECLARE definition text;
old_block text := $old$ else
  select coalesce(jsonb_agg(g.data order by g.id),'[]'::jsonb) into result from public.laundry_products g where g.id=any(ids) or laundry_private.product_matches(g.data,scope);
 end if;$old$;
new_block text := $new$ elsif scope='{}'::jsonb then
  select coalesce(jsonb_agg(g.data order by g.id),'[]'::jsonb) into result from public.laundry_products g;
 elsif scope='{"prop":"rent"}'::jsonb then
  select coalesce(jsonb_agg(g.data order by g.id),'[]'::jsonb) into result from public.laundry_products g where g.id=any(ids) or g.data->>'rental'='true';
 elsif jsonb_typeof(scope)='object' and scope ? 'client' and scope-'client'='{}'::jsonb then
  select coalesce(jsonb_agg(g.data order by g.id),'[]'::jsonb) into result from public.laundry_products g where g.id=any(ids) or (g.data->>'client' is not distinct from scope->>'client');
 else
  select coalesce(jsonb_agg(g.data order by g.id),'[]'::jsonb) into result from public.laundry_products g where g.id=any(ids) or laundry_private.product_matches(g.data,scope);
 end if;$new$;
BEGIN
 definition:=pg_get_functiondef('laundry_private.snapshot_products()'::regprocedure);
 IF position(old_block in definition)=0 THEN RAISE EXCEPTION 'Unexpected snapshot_products implementation'; END IF;
 EXECUTE replace(definition,old_block,new_block);
END $migration$;
