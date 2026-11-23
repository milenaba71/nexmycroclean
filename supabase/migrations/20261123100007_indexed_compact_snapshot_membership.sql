-- Preserve the exact compact snapshot while joining requested identifiers by primary key.
DO $migration$
DECLARE definition text;
old_sql text := 'from public.laundry_products g where g.id=any(ids);';
new_sql text := 'from (select distinct unnest(ids) as id) selected join public.laundry_products g on g.id=selected.id;';
BEGIN
 definition:=pg_get_functiondef('laundry_private.snapshot_products()'::regprocedure);
 IF position(old_sql in definition)=0 THEN RAISE EXCEPTION 'Unexpected snapshot_products implementation'; END IF;
 EXECUTE replace(definition,old_sql,new_sql);
END $migration$;
