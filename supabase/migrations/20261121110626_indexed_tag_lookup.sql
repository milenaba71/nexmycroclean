-- Preserve lookup precedence and lifecycle checks; prefilter fallback matches with
-- the existing GIN index instead of walking every product for an unknown barcode.
SET lock_timeout = '2s';
DO $migration$
DECLARE definition text;
old_query text := $old$select g.data into result from public.laundry_products g where lower(coalesce(nullif(g.data->>'barcode',''),g.id))=lower(code_value) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]')) a where lower(a)=lower(code_value)) order by g.id limit 1;$old$;
new_query text := $new$select g.data into result from public.laundry_products g where laundry_private.product_barcode_keys(g.id,g.data) @> array[lower(code_value)] and (lower(coalesce(nullif(g.data->>'barcode',''),g.id))=lower(code_value) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]')) a where lower(a)=lower(code_value))) order by g.id limit 1;$new$;
BEGIN
 definition := pg_get_functiondef('laundry_private.tag_lookup(text)'::regprocedure);
 IF position(old_query in definition)=0 THEN
  RAISE EXCEPTION 'Unexpected tag_lookup implementation; review before migration';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_index WHERE indexrelid='public.laundry_products_barcode_keys_gin'::regclass AND indisvalid) THEN
  RAISE EXCEPTION 'Barcode index must be valid before migration';
 END IF;
 EXECUTE replace(definition,old_query,new_query);
END $migration$;
