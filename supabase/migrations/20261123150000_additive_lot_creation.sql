-- Permit additive lot creation while other operators scan.
-- Keep the meta row lock, authorization, input validation and edit conflict checks.
DO $migration$
DECLARE definition text; original text := $old$ if (p_payload->>'revision')::bigint is distinct from rev then raise exception 'REVISION_CONFLICT';end if;$old$; replacement text := $new$ -- Additive lot creation allocates its ID under the meta lock; unrelated scans cannot overwrite it.
 if p_action<>'lot_create' and (p_payload->>'revision')::bigint is distinct from rev then raise exception 'REVISION_CONFLICT';end if;$new$;
BEGIN
 definition := pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure);
 IF position(replacement in definition)>0 THEN RETURN; END IF;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN
  RAISE EXCEPTION 'Unexpected laundry_core revision guard; migration not applied';
 END IF;
 EXECUTE replace(definition,original,replacement);
END;
$migration$;
