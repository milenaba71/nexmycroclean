-- Archive closed tickets without changing their status, interventions or analytics.
do $migration$
declare d text; anchor text; ending text;
begin
 d:=pg_get_functiondef('laundry_private.production(text,jsonb)'::regprocedure);
 if position('-- ticket_archive_v1' in d)>0 then return;end if;
 anchor:=$a$  note:=btrim(coalesce(p_payload->>'note',''));state:=p_payload->>'status';machine_id:=coalesce(target->>'machineId',p_payload->>'machineId');$a$;
 ending:=$a$  if jsonb_typeof(d->'plan')='object' then d:=jsonb_set(d,'{plan,stale}','true');end if;
 elsif p_action='task' then$a$;
 if position(anchor in d)=0 or position(ending in d)=0 then raise exception 'TICKET_ARCHIVE_SOURCE_CHANGED';end if;
 d:=replace(d,anchor,$a$  -- ticket_archive_v1
  if p_payload->>'command' in ('archive','restore') then
   if target is null then raise exception 'TICKET_NOT_FOUND';end if;
   if target->>'status' is distinct from 'closed' then raise exception 'CLOSE_BEFORE_ARCHIVE';end if;
   if coalesce((target->>'archived')::boolean,false) is distinct from (p_payload->>'command'='archive') then
    target:=target||jsonb_build_object('archived',p_payload->>'command'='archive','updatedAt',now(),
     'archiveEvents',coalesce(target->'archiveEvents','[]')||jsonb_build_array(jsonb_build_object('at',now(),'actor',email,'action',p_payload->>'command')));
    if p_payload->>'command'='archive' then
     target:=target||jsonb_build_object('archivedAt',now(),'archivedBy',email);
    else target:=target-'archivedAt'-'archivedBy';end if;
    d:=jsonb_set(d,array['tickets',pos::text],target);
   end if;
  else
   if coalesce((target->>'archived')::boolean,false) then raise exception 'TICKET_ARCHIVED';end if;
$a$||anchor);
 d:=replace(d,ending,$a$  if jsonb_typeof(d->'plan')='object' then d:=jsonb_set(d,'{plan,stale}','true');end if;
  end if;
 elsif p_action='task' then$a$);
 execute d;
end;$migration$;
