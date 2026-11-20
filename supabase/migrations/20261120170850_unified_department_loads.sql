-- Reuse the existing atomic group workflow for each supported wash department.
DO $migration$
DECLARE definition text;
BEGIN
 definition:=pg_get_functiondef('laundry_private.wash_batch_control(text,jsonb)'::regprocedure);
 IF position('machine_kind<>''water''' in definition)=0 OR position('value->>''kind''=''water''' in definition)=0 THEN
  RAISE EXCEPTION 'Unexpected combined-load implementation; review before migration';
 END IF;
 definition:=replace(definition,'machine_kind<>''water''','machine_kind NOT IN (''water'',''decon'',''dry'')');
 definition:=replace(definition,'first_id:=ids[1];','first_id:=ids[1];
 IF (SELECT count(DISTINCT machine_kind) FROM public.laundry_wash_batches WHERE id=ANY(ids))<>1 THEN
  RAISE EXCEPTION ''CART_PROGRAMS_DIFFERENT'';
 END IF;');
 definition:=replace(definition,'value->>''kind''=''water''','value->>''kind''=(SELECT machine_kind FROM public.laundry_wash_batches WHERE id=first_id)');
 EXECUTE definition;
END $migration$;
