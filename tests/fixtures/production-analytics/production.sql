CREATE OR REPLACE FUNCTION laundry_private.production(p_action text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare identity_result jsonb; who jsonb; d jsonb; rev bigint; target jsonb; pos int; alloc jsonb; dep text; typ jsonb; item jsonb; row_data jsonb; sessions jsonb; started timestamptz; day date; a timestamptz; b timestamptz; email text; note text; state text; machine_id text; previous_plan jsonb; next_email text; station_kind text;
begin
 -- user_permission_guard
 if p_action in ('save','plan') then perform laundry_private.require_permission('production_manage');elsif p_action='ticket' then perform laundry_private.require_permission('tickets_manage');elsif p_action='task' then perform laundry_private.require_permission(case when p_payload->>'command' in ('handoff','cancel') then 'production_manage' else 'production_execute' end);end if;
 identity_result:=laundry_private.laundry_authenticated('version','{}');who:=identity_result->'user';email:=who->>'email';
 select data,revision into d,rev from public.laundry_production where id for update;
 if not (d ? 'machineKinds') then d:=jsonb_set(d,'{machineKinds}','[{"id":"decon","name":"Lavaggio e decontaminazione"},{"id":"dry","name":"Lavaggio a secco"},{"id":"water","name":"Lavaggio ad acqua"},{"id":"dryer","name":"Asciugatura"}]'::jsonb);end if;
 if p_action='read' then
  return jsonb_build_object('data',d,'revision',rev,'members',(select coalesce(jsonb_agg(jsonb_build_object('email',m.email,'name',m.name,'role',m.role,'active',m.active) order by m.name),'[]') from public.laundry_members m where m.active and m.role in ('admin','operator') and not exists (select 1 from laundry_private.laundry_super_admin sa where sa.email=m.email)));
 end if;
 if coalesce(who->>'role','') not in ('admin','operator') then raise exception 'FORBIDDEN';end if;
 if (p_payload->>'revision')::bigint is distinct from rev then raise exception 'PRODUCTION_REVISION_CONFLICT';end if;
 if p_action in ('save','plan') then
  perform laundry_private.require_permission('production_manage');
  if p_action='save' and d ? 'machineKinds' and not ((p_payload->'data') ? 'machineKinds') then p_payload:=jsonb_set(p_payload,'{data,machineKinds}',d->'machineKinds');end if;
  perform laundry_private.production_validate(p_payload->'data');
  if p_action='save' and p_payload->'data'->'plan' is distinct from d->'plan' then raise exception 'USE_PLAN_ACTION';end if;
  if p_action='plan' and ((p_payload->'data')-'plan') is distinct from (d-'plan') then raise exception 'PLAN_ONLY';end if;
  previous_plan:=d->'plan';
  d:=p_payload->'data';
  if p_action='plan' and jsonb_typeof(previous_plan)='object' then d:=jsonb_set(d,'{planHistory}',coalesce((select jsonb_agg(value) from jsonb_array_elements(coalesce(d->'planHistory','[]')) where value->>'first' is distinct from previous_plan->>'first'),'[]')||jsonb_build_array(previous_plan));end if;
  if p_action='save' and jsonb_typeof(d->'plan')='object' then d:=jsonb_set(d,'{plan,stale}','true');end if;
 elsif p_action='ticket' then
  select value,ordinality::int-1 into target,pos from jsonb_array_elements(d->'tickets') with ordinality where value->>'id'=p_payload->>'id';
  note:=btrim(coalesce(p_payload->>'note',''));state:=p_payload->>'status';machine_id:=coalesce(target->>'machineId',p_payload->>'machineId');
  if length(note)<3 or length(note)>2000 or coalesce(state,'') not in ('open','working','waiting','resolved','closed') then raise exception 'TICKET_NOTE_REQUIRED';end if;
  if not exists(select 1 from jsonb_array_elements(d->'machines') where value->>'id'=machine_id) then raise exception 'INVALID_MACHINE';end if;
  if target is null then
   if state<>'open' then raise exception 'INVALID_TICKET_STATE';end if;
   target:=jsonb_build_object('id',gen_random_uuid()::text,'machineId',machine_id,'description',note,'createdAt',now(),'createdBy',email,'history','[]');pos:=jsonb_array_length(d->'tickets');
  end if;
  if state='closed' and target->>'status' is distinct from 'resolved' then raise exception 'RESOLVE_BEFORE_CLOSE';end if;
  target:=target||jsonb_build_object('status',state,'blocking',case when state='closed' then false else coalesce((p_payload->>'blocking')::boolean,(target->>'blocking')::boolean,true) end,'updatedAt',now(),'history',coalesce(target->'history','[]')||jsonb_build_array(jsonb_build_object('at',now(),'actor',email,'status',state,'note',note)));
  d:=jsonb_set(d,array['tickets',pos::text],target);
  if jsonb_typeof(d->'plan')='object' then d:=jsonb_set(d,'{plan,stale}','true');end if;
 elsif p_action='task' then
  select value,ordinality::int-1 into target,pos from jsonb_array_elements(d->'tasks') with ordinality where value->>'id'=p_payload->>'id';
  if target is null then raise exception 'TASK_NOT_FOUND';end if;
  select value into alloc from jsonb_array_elements(coalesce(d->'plan'->'allocations','[]')) where value->>'taskId'=target->>'id';
  state:=p_payload->>'command';note:=btrim(coalesce(p_payload->>'note',''));
  if state='cancel' then
   if who->>'role'<>'admin' or target->>'status'<>'pending' or length(note)<3 then raise exception 'INVALID_CANCELLATION';end if;
   target:=target||jsonb_build_object('status','cancelled');
  elsif state='handoff' then
   if not coalesce((who->'permissions'->>'production_manage')::boolean,false) or target->>'status' not in ('pending','paused') or length(note)<3 or coalesce((p_payload->>'remainingMinutes')::numeric,0)<=0 then raise exception 'PAUSE_BEFORE_HANDOFF';end if;
   select value into typ from jsonb_array_elements(d->'types') where value->>'id'=target->>'typeId';
   select value->>'kind' into station_kind from jsonb_array_elements(d->'stations') where value->>'id'=typ->>'station';
   if typ->>'mode'='machine' then raise exception 'COMPLETE_MACHINE_BEFORE_HANDOFF';end if;
   next_email:=p_payload->>'email';
   if not exists(select 1 from jsonb_array_elements(d->'operators') o join public.laundry_members m on m.email=o->>'email' where o->>'email'=next_email and o->>'active' is distinct from 'false' and (o->'skills') ? (typ->>'station') and m.active and m.role in ('admin','operator')) then raise exception 'INVALID_ASSIGNEE';end if;
   target:=target||jsonb_build_object('status','pending','assignee',next_email,'remainingMinutes',(p_payload->>'remainingMinutes')::numeric);
   if jsonb_typeof(d->'plan')='object' then d:=jsonb_set(d,'{plan,stale}','true');end if;
  else
   if coalesce(alloc->>'email','')<>email then raise exception 'TASK_ASSIGNED_TO_OTHER';end if;
   if state='start' then
    if target->>'status' not in ('pending','paused') then raise exception 'INVALID_TASK_TRANSITION';end if;
    if not exists(select 1 from jsonb_array_elements(d->'types') t join jsonb_array_elements(d->'stations') s on s->>'id'=t->>'station' where t->>'id'=target->>'typeId' and s->>'active'='true') then raise exception 'STATION_INACTIVE';end if;
    if target->>'status'='pending' and coalesce((d->'plan'->>'stale')::boolean,false) then raise exception 'REPLAN_REQUIRED';end if;
    if exists(select 1 from jsonb_array_elements(d->'tasks') where value->>'status'='running' and value->>'startedBy'=email) then raise exception 'OPERATOR_ALREADY_BUSY';end if;
    for dep in select jsonb_array_elements_text(target->'dependsOn') loop
     if not exists(select 1 from jsonb_array_elements(d->'tasks') where value->>'id'=dep and value->>'status'='completed') then raise exception 'PREVIOUS_TASK_NOT_COMPLETED';end if;
    end loop;
    select value into typ from jsonb_array_elements(d->'types') where value->>'id'=target->>'typeId';
   select value->>'kind' into station_kind from jsonb_array_elements(d->'stations') where value->>'id'=typ->>'station';
    if station_kind in ('clean','out') then
     for item in select value from jsonb_array_elements(target->'items') loop
      select r into row_data from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r where l.id=(item->>'lotId')::bigint and r->>'code'=item->>'code';
      if coalesce((row_data->>'repair')::boolean,false) or coalesce((row_data->>'rewash')::boolean,false) or coalesce((row_data->>'verify')::boolean,false) or coalesce((row_data->>'relabel')::boolean,false) then raise exception 'OPEN_INTERVENTIONS';end if;
     end loop;
    end if;
    if station_kind='repair' then
     for item in select value from jsonb_array_elements(target->'items') loop
      select r into row_data from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r where l.id=(item->>'lotId')::bigint and r->>'code'=item->>'code';
      if coalesce((row_data->>'washRequired')::boolean,false) and not coalesce((row_data->>'washed')::boolean,false) then raise exception 'REGISTER_WASH_IN_LOT';end if;
     end loop;
    end if;
    machine_id:=alloc->>'machineId';
    if machine_id is not null then
     if exists(select 1 from jsonb_array_elements(d->'tickets') where value->>'machineId'=machine_id and (value->>'blocking')::boolean and value->>'status'<>'closed') or not exists(select 1 from jsonb_array_elements(d->'machines') where value->>'id'=machine_id and value->>'active' is distinct from 'false') then raise exception 'MACHINE_UNAVAILABLE';end if;
     if exists(select 1 from jsonb_array_elements(d->'tasks') t cross join lateral jsonb_array_elements(coalesce(d->'plan'->'allocations','[]')) al where t->>'status' in ('running','paused') and al->>'taskId'=t->>'id' and al->>'machineId'=machine_id and t->>'id'<>target->>'id') then raise exception 'MACHINE_BUSY';end if;
    end if;
    target:=target||jsonb_build_object('status','running','startedAt',now(),'startedBy',email);
   elsif state in ('pause','complete') then
    if target->>'status'<>'running' and not(state='complete' and target->>'status'='paused') then raise exception 'INVALID_TASK_TRANSITION';end if;
    select value into typ from jsonb_array_elements(d->'types') where value->>'id'=target->>'typeId';
   select value->>'kind' into station_kind from jsonb_array_elements(d->'stations') where value->>'id'=typ->>'station';
    if state='complete' then
     for item in select value from jsonb_array_elements(target->'items') loop
      select r into row_data from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r where l.id=(item->>'lotId')::bigint and r->>'code'=item->>'code';
      if station_kind in ('clean','out') and (coalesce((row_data->>'repair')::boolean,false) or coalesce((row_data->>'rewash')::boolean,false) or coalesce((row_data->>'verify')::boolean,false) or coalesce((row_data->>'relabel')::boolean,false)) then raise exception 'OPEN_INTERVENTIONS';end if;
      if station_kind='repair' and coalesce((row_data->>'repair')::boolean,false) then raise exception 'REGISTER_REPAIR_IN_LOT';end if;
      if station_kind='out' and row_data->>'state' is distinct from 'Uscito' then raise exception 'REGISTER_EXIT_IN_LOT';end if;
     end loop;
    end if;
    sessions:=coalesce(target->'sessions','[]');started:=(target->>'startedAt')::timestamptz;
    if target->>'status'='running' and started is not null then
     for day in select generate_series((started at time zone 'Europe/Rome')::date,(now() at time zone 'Europe/Rome')::date,'1 day')::date loop
      a:=greatest(started,day::timestamp at time zone 'Europe/Rome');b:=least(now(),(day+1)::timestamp at time zone 'Europe/Rome');
      sessions:=sessions||jsonb_build_array(jsonb_build_object('email',email,'date',day,'seconds',greatest(0,extract(epoch from b-a)),'from',a,'to',b));
     end loop;
    end if;
    target:=(target-'startedAt'-'startedBy')||jsonb_build_object('sessions',sessions,'status',case when state='pause' then 'paused' else 'completed' end);
    if state='complete' then target:=target||jsonb_build_object('completedAt',now(),'completedBy',email);end if;
   else raise exception 'INVALID_TASK_COMMAND';end if;
  end if;
  target:=target||jsonb_build_object('events',coalesce(target->'events','[]')||jsonb_build_array(jsonb_build_object('at',now(),'actor',email,'action',state,'note',note)));
  d:=jsonb_set(d,array['tasks',pos::text],target);
 else raise exception 'INVALID_ACTION';end if;
 update public.laundry_production set data=d,revision=rev+1 where id;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(email,auth.uid()::text,'production_'||p_action,jsonb_build_object('id',p_payload->>'id','command',p_payload->>'command','revision',rev+1));
 return jsonb_build_object('data',d,'revision',rev+1);
end;$function$
