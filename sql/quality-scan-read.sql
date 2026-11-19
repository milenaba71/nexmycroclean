-- Read only the scanned garment. Final exit writes still run quality_exit_guard.
-- Keep ordinary quality screens, reports and recording unchanged.
do $patch$
declare definition text; marker text := ' -- Same lock order as normal lot writes, preventing a release racing an exit.';
begin
 definition:=pg_get_functiondef('laundry_private.quality_control(text,jsonb)'::regprocedure);
 if strpos(definition,marker)=0 then raise exception 'QUALITY_SCAN_PATCH_SOURCE_MISMATCH';end if;
 if strpos(definition,'-- Single-code scan preflight')>0 then raise exception 'QUALITY_SCAN_PATCH_ALREADY_APPLIED';end if;
 definition:=replace(definition,marker,$insert$
 -- Single-code scan preflight: a read never holds the global write lock.
 if p_action='read' and p ? 'scan_code' then
  code:=p->>'scan_code';
  if coalesce(length(code),0) not between 1 and 200 then raise exception 'INVALID_BARCODE';end if;
  select jsonb_build_object('lot_id',q.id,'enabled',coalesce(c.required,false),
   'eligible',coalesce((select jsonb_agg(r->>'code') from jsonb_array_elements(q.data->'rows') r where r->>'code'=code and laundry_private.quality_row_ready_for_lot(q.id,r)),'[]'::jsonb),
   'released',coalesce((select jsonb_agg(r->>'code') from jsonb_array_elements(q.data->'rows') r where r->>'code'=code and laundry_private.quality_released(q.id,r)),'[]'::jsonb))
  into result from public.laundry_lots q left join public.laundry_lot_quality c on c.lot_id=q.id where q.id=lid;
  if not found then raise exception 'LOT_NOT_FOUND';end if;
  return result;
 end if;
$insert$||marker);
 execute definition;
end $patch$;
