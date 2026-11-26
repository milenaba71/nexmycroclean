-- Extend existing tickets; keep their audit, permissions, revision and blocking rules.
create function laundry_private.maintenance_fields(p jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare k text; v text; result jsonb:='{}';
begin
 if jsonb_typeof(p) is distinct from 'object' then raise exception 'INVALID_MAINTENANCE';end if;
 for k in select jsonb_object_keys(p) loop
  if k not in ('kind','component','errorCode','cause','work','parts','nextDate') or jsonb_typeof(p->k)<>'string' then raise exception 'INVALID_MAINTENANCE';end if;
  v:=btrim(p->>k);
  if length(v)>(case when k in ('cause','work','parts') then 1000 else 120 end) then raise exception 'INVALID_MAINTENANCE';end if;
  if k='kind' and v not in ('','fault','planned','test') then raise exception 'INVALID_MAINTENANCE';end if;
  if k='nextDate' and v<>'' then
   if v !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'INVALID_MAINTENANCE';end if;
   perform v::date;
  end if;
  result:=result||jsonb_build_object(k,v);
 end loop;
 return result;
end $$;
revoke all on function laundry_private.maintenance_fields(jsonb) from public,anon,authenticated;

do $patch$
declare src text; needle text:='  target:=target||jsonb_build_object(''status'',state,''blocking''';
begin
 src:=pg_get_functiondef('laundry_private.production(text,jsonb)'::regprocedure);
 if position(needle in src)=0 or position('maintenance_fields' in src)>0 then raise exception 'PRODUCTION_SOURCE_CHANGED';end if;
 src:=replace(src,needle,E'  if p_payload ? ''maintenance'' then target:=target||jsonb_build_object(''maintenance'',coalesce(target->''maintenance'',''{}'')||laundry_private.maintenance_fields(p_payload->''maintenance''));end if;\n'||needle);
 needle:='''status'',state,''note'',note,''blocking''';
 if position(needle in src)=0 then raise exception 'TICKET_HISTORY_SOURCE_CHANGED';end if;
 src:=replace(src,needle,'''status'',state,''note'',note,''maintenance'',coalesce(target->''maintenance'',''{}''),''blocking''');
 -- jsonb_build_object otherwise stores the literal string "[]" as the first history item.
 src:=replace(src,'''createdBy'',email,''history'',''[]'')','''createdBy'',email,''history'',''[]''::jsonb)');
 execute src;
end $patch$;

-- Dedicated read, without production's FOR UPDATE and without operators, clients or lots.
create function laundry_private.maintenance_history() returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb;
begin
 perform public.laundry_assistant_quota(false); -- Existing access + active session check, no consumption.
 select data into d from public.laundry_production where id;
 return jsonb_build_object('asOf',statement_timestamp(),
  'machines',coalesce((select jsonb_agg(jsonb_build_object('id',m->>'id','name',m->>'name','active',m->'active')) from jsonb_array_elements(coalesce(d->'machines','[]')) m),'[]'),
  'tickets',coalesce((select jsonb_agg(jsonb_build_object('id',t->>'id','machineId',t->>'machineId','description',t->>'description','status',t->>'status','blocking',t->'blocking','createdAt',t->'createdAt','updatedAt',t->'updatedAt','archived',t->'archived','maintenance',coalesce(t->'maintenance','{}'),
    'history',coalesce((select jsonb_agg(jsonb_build_object('at',h->'at','status',h->'status','note',h->'note','blocking',h->'blocking')) from jsonb_array_elements(coalesce(t->'history','[]')) h where jsonb_typeof(h)='object'),'[]'))) from jsonb_array_elements(coalesce(d->'tickets','[]')) t),'[]'));
end $$;
revoke all on function laundry_private.maintenance_history() from public,anon,authenticated;
grant execute on function laundry_private.maintenance_history() to authenticated;
create function public.laundry_maintenance_history() returns jsonb
language sql security invoker set search_path='' as $$select laundry_private.maintenance_history()$$;
revoke all on function public.laundry_maintenance_history() from public,anon,authenticated;
grant execute on function public.laundry_maintenance_history() to authenticated;
