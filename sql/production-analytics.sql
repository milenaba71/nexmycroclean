-- Capture operational history through the existing authenticated RPC.
-- No new public API, grants or data backfill; existing authorization remains intact.
begin;
do $patch$
declare src text; old text; replacement text;
begin
 select pg_get_functiondef('laundry_private.production(text,jsonb)'::regprocedure) into src;
 if position('analytics_capture_v1' in src)=0 then
 old:=$needle$jsonb_build_object('at',now(),'actor',email,'status',state,'note',note)$needle$;
 replacement:=$new$jsonb_build_object('at',now(),'actor',email,'status',state,'note',note,'blocking',case when state='closed' then false else coalesce((p_payload->>'blocking')::boolean,(target->>'blocking')::boolean,true) end)$new$;
 if position(old in src)=0 then raise exception 'ANALYTICS_TICKET_PATCH_TARGET_MISSING';end if;
 src:=replace(src,old,replacement);
 old:=$needle$target:=target||jsonb_build_object('status','running','startedAt',now(),'startedBy',email);$needle$;
 replacement:=$new$
    -- analytics_capture_v1: freeze production standard on first start, never a selling price.
    if not (target ? 'standardSnapshot') and coalesce(target->'sessions','[]')='[]'::jsonb
       and not exists(select 1 from jsonb_array_elements(coalesce(target->'events','[]')) e where e->>'action'='start') then
     target:=target||jsonb_build_object('standardSnapshot',jsonb_build_object('at',now(),'quantity',(target->>'quantity')::numeric,'type',typ,'machine',(select value from jsonb_array_elements(d->'machines') where value->>'id'=machine_id)));
    end if;
    target:=target||jsonb_build_object('status','running','startedAt',now(),'startedBy',email);$new$;
 if position(old in src)=0 then raise exception 'ANALYTICS_START_PATCH_TARGET_MISSING';end if;
 src:=replace(src,old,replacement);execute src;
 end if;
 select pg_get_functiondef('laundry_private.production_validate(jsonb)'::regprocedure) into src;
 if position('PRESERVE_STANDARD_SNAPSHOT' in src)=0 then
 old:=$needle$if old_t is null then
   if t->>'status'<>'pending'$needle$;
 replacement:=$new$if old_t->'standardSnapshot' is distinct from t->'standardSnapshot' then raise exception 'PRESERVE_STANDARD_SNAPSHOT';end if;
  if old_t is null then
   if t->>'status'<>'pending'$new$;
 if position(old in src)=0 then raise exception 'ANALYTICS_VALIDATOR_PATCH_TARGET_MISSING';end if;
 src:=replace(src,old,replacement);execute src;
 end if;
end;$patch$;
commit;
