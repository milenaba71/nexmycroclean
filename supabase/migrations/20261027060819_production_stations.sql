begin;
update public.laundry_production set data=jsonb_set(data,'{stations}','[{"id": "entry", "name": "Entrata, preparazione e lavaggio", "kind": "entry", "active": true}, {"id": "clean", "name": "Clean room · controllo e piegatura", "kind": "clean", "active": true}, {"id": "repair", "name": "Riparazioni", "kind": "repair", "active": true}, {"id": "out", "name": "Smistamento e controllo uscita", "kind": "out", "active": true}]'::jsonb),revision=revision+1 where id and not(data ? 'stations');
create or replace function laundry_private.production_validate(d jsonb) returns void language plpgsql security invoker set search_path='' as $fn$
declare k text; x jsonb; t jsonb; old_t jsonb; i jsonb; dep text; v numeric; seen text[]; old_data jsonb;
begin
 if octet_length(d::text)>3000000 then raise exception 'PRODUCTION_TOO_LARGE';end if;
 foreach k in array array['stations','operators','overrides','machines','types','calendars','tasks','tickets'] loop
  if jsonb_typeof(d->k) is distinct from 'array' then raise exception 'INVALID_PRODUCTION_ARRAY %',k;end if;
  seen:=array[]::text[];
  for x in select value from jsonb_array_elements(d->k) loop
   if jsonb_typeof(x)<>'object' or nullif(x->>'id','') is null then raise exception 'INVALID_PRODUCTION_ID';end if;
   if x->>'id'=any(seen) then raise exception 'DUPLICATE_PRODUCTION_ID';end if;seen:=array_append(seen,x->>'id');
  end loop;
 end loop;

 if jsonb_array_length(d->'stations')=0 then raise exception 'STATION_REQUIRED';end if;
 if (select count(*) from jsonb_array_elements(d->'stations'))<>(select count(distinct lower(btrim(value->>'name'))) from jsonb_array_elements(d->'stations')) then raise exception 'DUPLICATE_STATION_NAME';end if;
 select data into old_data from public.laundry_production where id;
 for x in select value from jsonb_array_elements(d->'stations') loop
  if nullif(btrim(x->>'name'),'') is null or length(x->>'name')>120 or coalesce(x->>'kind','') not in ('entry','clean','repair','out','other') or jsonb_typeof(x->'active') is distinct from 'boolean' then raise exception 'INVALID_STATION';end if;
  select value into old_t from jsonb_array_elements(coalesce(old_data->'stations','[]')) where value->>'id'=x->>'id';
  if old_t is not null and old_t->>'kind' is distinct from x->>'kind' then raise exception 'STATION_KIND_IMMUTABLE';end if;
 end loop;
 for x in select value from jsonb_array_elements(coalesce(old_data->'stations','[]')) loop
  if not exists(select 1 from jsonb_array_elements(d->'stations') where value->>'id'=x->>'id') and exists(select 1 from jsonb_array_elements(old_data->'tasks') hist_task join jsonb_array_elements(old_data->'types') wt on wt->>'id'=hist_task->>'typeId' where wt->>'station'=x->>'id') then raise exception 'STATION_HAS_HISTORY';end if;
 end loop;
 for x in select value from jsonb_array_elements(d->'overrides') loop
  if not coalesce((x->>'absent')::boolean,false) and not exists(select 1 from jsonb_array_elements(d->'stations') where value->>'id'=x->>'station') then raise exception 'STATION_IN_USE';end if;
 end loop;
 for x in select value from jsonb_array_elements(d->'operators') loop
  if not exists(select 1 from public.laundry_members where email=x->>'email' and (x->>'active'='false' or (active and role in ('admin','operator')))) then raise exception 'INVALID_PRODUCTION_OPERATOR';end if;
  if jsonb_typeof(x->'skills') is distinct from 'array' then raise exception 'INVALID_SKILLS';end if;
  if not exists(select 1 from jsonb_array_elements(d->'stations') where value->>'id'=x->>'station') or exists(select 1 from jsonb_array_elements_text(x->'skills') skill where not exists(select 1 from jsonb_array_elements(d->'stations') where value->>'id'=skill)) then raise exception 'STATION_IN_USE';end if;
 end loop;
 if (select count(*) from jsonb_array_elements(d->'operators'))<>(select count(distinct value->>'email') from jsonb_array_elements(d->'operators')) then raise exception 'DUPLICATE_OPERATOR';end if;
 for x in select value from jsonb_array_elements(d->'types') loop
  if nullif(btrim(x->>'name'),'') is null or not exists(select 1 from jsonb_array_elements(d->'stations') s where s->>'id'=x->>'station') or coalesce(x->>'mode','') not in ('rate','piece','lot','machine') then raise exception 'INVALID_WORK_TYPE';end if;
  if (x->>'value')::numeric<=0 or coalesce((x->>'setup')::numeric,0)<0 or (x->>'operatorMinutes')::numeric<0 then raise exception 'INVALID_WORK_TIME';end if;
 end loop;
 for x in select value from jsonb_array_elements(d->'machines') loop
  if nullif(btrim(x->>'name'),'') is null or coalesce(x->>'kind','') not in ('decon','dry','water','dryer') or (x->>'capacity')::numeric<=0 then raise exception 'INVALID_MACHINE';end if;
 end loop;
 for x in select value from jsonb_array_elements(d->'calendars') loop
  if not exists(select 1 from public.laundry_clients where id=x->>'clientId') then raise exception 'INVALID_CLIENT';end if;
  if nullif(x->>'lotId','') is not null and not exists(select 1 from public.laundry_lots l join public.laundry_clients c on c.data->>'name'=l.data->>'client' where l.id=(x->>'lotId')::bigint and c.id=x->>'clientId') then raise exception 'LOT_CLIENT_MISMATCH';end if;
  if (x->>'quantity')::numeric<=0 then raise exception 'INVALID_QUANTITY';end if;
  if nullif(x->>'arrival','') is null or nullif(x->>'due','') is null or (x->>'due')::timestamp<(x->>'arrival')::timestamp then raise exception 'INVALID_DELIVERY_DATE';end if;
 end loop;
 for t in select value from jsonb_array_elements(d->'tasks') loop
  if coalesce(t->>'status','') not in ('pending','running','paused','completed','cancelled') or coalesce((t->>'quantity')::numeric,0)<=0 then raise exception 'INVALID_TASK';end if;
  if not exists(select 1 from jsonb_array_elements(d->'types') where value->>'id'=t->>'typeId') then raise exception 'INVALID_TASK_TYPE';end if;
  if nullif(t->>'assignee','') is not null and not exists(select 1 from jsonb_array_elements(d->'operators') where value->>'email'=t->>'assignee') then raise exception 'INVALID_ASSIGNEE';end if;
  if jsonb_typeof(t->'items') is distinct from 'array' or jsonb_typeof(t->'dependsOn') is distinct from 'array' then raise exception 'INVALID_TASK_ITEMS';end if;
  for i in select value from jsonb_array_elements(t->'items') loop
   if not exists(select 1 from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r where l.id=(i->>'lotId')::bigint and r->>'code'=i->>'code') then raise exception 'INVALID_TASK_PRODUCT';end if;
  end loop;
  if jsonb_array_length(t->'items')>0 and (t->>'quantity')::int<>jsonb_array_length(t->'items') then raise exception 'TASK_QUANTITY_MISMATCH';end if;
  for dep in select jsonb_array_elements_text(t->'dependsOn') loop
   if dep=t->>'id' or not exists(select 1 from jsonb_array_elements(d->'tasks') where value->>'id'=dep) then raise exception 'INVALID_TASK_DEPENDENCY';end if;
  end loop;
 end loop;
 select data into old_data from public.laundry_production where id;
 -- Operational states and time logs can change only through their dedicated RPC actions.
 for t in select value from jsonb_array_elements(d->'tasks') loop
  select value into old_t from jsonb_array_elements(coalesce(old_data->'tasks','[]')) where value->>'id'=t->>'id';
  if old_t is null then
   if t->>'status'<>'pending' or coalesce(t->'sessions','[]')<>'[]'::jsonb or t ? 'startedAt' then raise exception 'INVALID_NEW_TASK_STATE';end if;
  else
   if old_t->>'status'<>'pending' and old_t is distinct from t then raise exception 'TASK_ALREADY_STARTED';end if;
   if old_t->>'status' is distinct from t->>'status' or old_t->'sessions' is distinct from t->'sessions' or old_t->'startedAt' is distinct from t->'startedAt' then raise exception 'USE_TASK_ACTION';end if;
  end if;
 end loop;
 for old_t in select value from jsonb_array_elements(coalesce(old_data->'tasks','[]')) loop
  if not exists(select 1 from jsonb_array_elements(d->'tasks') where value->>'id'=old_t->>'id') then raise exception 'PRESERVE_TASK_HISTORY';end if;
 end loop;
 if d->'planHistory' is distinct from old_data->'planHistory' then raise exception 'PRESERVE_PLAN_HISTORY';end if;
 if d->'tickets' is distinct from old_data->'tickets' then raise exception 'USE_TICKET_ACTION';end if;
 for old_t in select value from jsonb_array_elements(coalesce(old_data->'machines','[]')) loop
  if not exists(select 1 from jsonb_array_elements(d->'machines') where value->>'id'=old_t->>'id') and (exists(select 1 from jsonb_array_elements(old_data->'tickets') where value->>'machineId'=old_t->>'id') or exists(select 1 from jsonb_array_elements(coalesce(old_data->'plan'->'allocations','[]')) where value->>'machineId'=old_t->>'id') or exists(select 1 from jsonb_array_elements(coalesce(old_data->'planHistory','[]')) p cross join lateral jsonb_array_elements(coalesce(p->'allocations','[]')) a where a->>'machineId'=old_t->>'id')) then raise exception 'MACHINE_HAS_HISTORY';end if;
 end loop;
end;$fn$;
create or replace function laundry_private.production(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare identity_result jsonb; who jsonb; d jsonb; rev bigint; target jsonb; pos int; alloc jsonb; dep text; typ jsonb; item jsonb; row_data jsonb; sessions jsonb; started timestamptz; day date; a timestamptz; b timestamptz; email text; note text; state text; machine_id text; previous_plan jsonb; next_email text; station_kind text;
begin
 identity_result:=laundry_private.laundry_authenticated('version','{}');who:=identity_result->'user';email:=who->>'email';
 select data,revision into d,rev from public.laundry_production where id for update;
 if p_action='read' then
  return jsonb_build_object('data',d,'revision',rev,'members',(select coalesce(jsonb_agg(jsonb_build_object('email',m.email,'name',m.name,'role',m.role,'active',m.active) order by m.name),'[]') from public.laundry_members m where m.active and m.role in ('admin','operator')));
 end if;
 if coalesce(who->>'role','') not in ('admin','operator') then raise exception 'FORBIDDEN';end if;
 if (p_payload->>'revision')::bigint is distinct from rev then raise exception 'PRODUCTION_REVISION_CONFLICT';end if;
 if p_action in ('save','plan') then
  if who->>'role'<>'admin' then raise exception 'FORBIDDEN';end if;
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
   if who->>'role'<>'admin' or target->>'status' not in ('pending','paused') or length(note)<3 or coalesce((p_payload->>'remainingMinutes')::numeric,0)<=0 then raise exception 'PAUSE_BEFORE_HANDOFF';end if;
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
end;$fn$;
commit;
