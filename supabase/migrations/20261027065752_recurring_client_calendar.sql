begin;
create table laundry_private.client_schedules(id uuid primary key default gen_random_uuid(), client_id text not null references public.laundry_clients(id), revision bigint not null default 1, data jsonb not null);
alter table laundry_private.client_schedules enable row level security;
revoke all on laundry_private.client_schedules from public,anon,authenticated;
create function laundry_private.refresh_client_calendar() returns void language plpgsql security definer set search_path='' as $$
declare d jsonb; result jsonb:='[]'; original jsonb; r record; day date; today date:=(now() at time zone 'Europe/Rome')::date; e jsonb; old_e jsonb; event_id text; active_ids text[]:='{}';
begin
 select data into d from public.laundry_production where id for update;
 original:=d->'calendars';
 -- Preserve past appointments, linked lots and individually modified/cancelled dates.
 for e in select value from jsonb_array_elements(original) loop
  if e->>'recurrenceId' is null or (e->>'sourceDate')::date<today or nullif(e->>'lotId','') is not null or coalesce((e->>'exception')::boolean,false) or e->>'arrival' is distinct from e->>'generatedArrival' or e->>'due' is distinct from e->>'generatedDue' then result:=result||jsonb_build_array(e);end if;
 end loop;
 for r in select s.* from laundry_private.client_schedules s join public.laundry_clients c on c.id=s.client_id where s.data->>'active'='true' and c.data->>'active' is distinct from 'false' loop
  for day in select generate_series(greatest(today,(r.data->>'start')::date),least(today+83,coalesce(nullif(r.data->>'end','')::date,today+83)),interval '1 day')::date loop
   if extract(dow from day)::int<>(r.data->>'weekday')::int then continue;end if;
   event_id:='rec:'||r.id::text||':'||day::text;
   if exists(select 1 from jsonb_array_elements(result) where value->>'id'=event_id or (value->>'recurrenceId' is null and value->>'clientId'=r.client_id and value->>'arrival'=day::text||'T'||(r.data->>'arrivalTime'))) then continue;end if;
   e:=jsonb_build_object('id',event_id,'clientId',r.client_id,'recurrenceId',r.id,'sourceDate',day,'arrival',day::text||'T'||(r.data->>'arrivalTime'),'due',(day+(r.data->>'deliveryDays')::int)::text||'T'||(r.data->>'deliveryTime'),'quantity',r.data->'quantity','notes',coalesce(r.data->>'notes',''),'lotId',null,'exception',false);
   e:=e||jsonb_build_object('generatedArrival',e->'arrival','generatedDue',e->'due');
   result:=result||jsonb_build_array(e);
  end loop;
 end loop;
 select coalesce(jsonb_agg(value order by value->>'arrival',value->>'id'),'[]') into result from jsonb_array_elements(result);
 select coalesce(jsonb_agg(value order by value->>'arrival',value->>'id'),'[]') into original from jsonb_array_elements(original);
 if result is distinct from original then
  d:=jsonb_set(d,'{calendars}',result);if jsonb_typeof(d->'plan')='object' then d:=jsonb_set(d,'{plan,stale}','true');end if;
  update public.laundry_production set data=d,revision=revision+1 where id;
 end if;
end;$$;
revoke all on function laundry_private.refresh_client_calendar() from public,anon,authenticated;
create function laundry_private.client_calendar(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare who jsonb; x jsonb; sid uuid; old_row laundry_private.client_schedules; d jsonb; rev bigint; e jsonb; result jsonb; lot jsonb; i int;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 if p_action in ('lot_create','appointment') then
  if who->>'role' not in ('admin','operator') then raise exception 'FORBIDDEN';end if;
  -- Core revision lock precedes production lock, consistently with other authenticated RPCs.
  perform 1 from public.laundry_meta where id for update;
 end if;
 select data,revision into d,rev from public.laundry_production where id for update;
 if p_action='save' then
  if who->>'role'<>'admin' then raise exception 'FORBIDDEN';end if;
  x:=p_payload->'schedule';sid:=coalesce(nullif(x->>'id','')::uuid,gen_random_uuid());
  select * into old_row from laundry_private.client_schedules where id=sid;
  if old_row.id is not null and old_row.revision is distinct from (x->>'revision')::bigint then raise exception 'SCHEDULE_REVISION_CONFLICT';end if;
  if not exists(select 1 from public.laundry_clients where id=x->>'clientId' and data->>'active' is distinct from 'false') then raise exception 'INVALID_CLIENT';end if;
  if old_row.id is not null and old_row.client_id<>x->>'clientId' then raise exception 'SCHEDULE_CLIENT_IMMUTABLE';end if;
  if coalesce(x->>'weekday','')!~'^[0-6]$' or coalesce(x->>'deliveryDays','')!~'^(0|[1-9]|1[0-4])$' or coalesce(x->>'arrivalTime','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(x->>'deliveryTime','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or nullif(x->>'start','') is null or jsonb_typeof(x->'active') is distinct from 'boolean' then raise exception 'INVALID_SCHEDULE';end if;
  if nullif(x->>'end','')::date<(x->>'start')::date or ((x->>'deliveryDays')::int=0 and (x->>'deliveryTime')::time<(x->>'arrivalTime')::time) or (x->>'quantity')::numeric<=0 then raise exception 'INVALID_SCHEDULE';end if;
  if exists(select 1 from laundry_private.client_schedules s where s.id<>sid and s.client_id=x->>'clientId' and s.data->>'active'='true' and x->>'active'='true' and s.data->>'weekday'=x->>'weekday' and s.data->>'arrivalTime'=x->>'arrivalTime' and (s.data->>'start')::date<=coalesce(nullif(x->>'end','')::date,'infinity'::date) and (x->>'start')::date<=coalesce(nullif(s.data->>'end','')::date,'infinity'::date)) then raise exception 'DUPLICATE_SCHEDULE';end if;
  insert into laundry_private.client_schedules(id,client_id,data) values(sid,x->>'clientId',x-'id'-'revision') on conflict(id) do update set data=excluded.data,revision=client_schedules.revision+1;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'client_schedule_save',jsonb_build_object('scheduleId',sid));
 elsif p_action='appointment' then
  if who->>'role'<>'admin' then raise exception 'FORBIDDEN';end if;
  if (p_payload->>'revision')::bigint is distinct from rev then raise exception 'PRODUCTION_REVISION_CONFLICT';end if;
  x:=p_payload->'appointment';
  select value,(ordinality-1)::int into e,i from jsonb_array_elements(d->'calendars') with ordinality where value->>'id'=x->>'id';
  if e is null then raise exception 'APPOINTMENT_UNAVAILABLE';end if;
  if nullif(e->>'lotId','') is not null and (x->'lotId' is distinct from e->'lotId' or coalesce((x->>'cancelled')::boolean,false)) then raise exception 'APPOINTMENT_ALREADY_LINKED';end if;
  x:=e||jsonb_build_object('clientId',x->'clientId','arrival',x->'arrival','due',x->'due','quantity',x->'quantity','lotId',x->'lotId','notes',x->'notes','cancelled',coalesce(x->'cancelled','false'::jsonb),'exception',true);
  d:=jsonb_set(d,array['calendars',i::text],x);
  if nullif(x->>'lotId','') is not null then
   select coalesce(jsonb_agg(case when t->>'status'='pending' and jsonb_array_length(t->'items')>0 and not exists(select 1 from jsonb_array_elements(t->'items') item where item->>'lotId' is distinct from x->>'lotId') then t||jsonb_build_object('due',x->'due','releaseDate',left(x->>'arrival',10)) else t end),'[]') into result from jsonb_array_elements(d->'tasks') t;
   d:=jsonb_set(d,'{tasks}',result);
  end if;
  perform laundry_private.production('save',jsonb_build_object('revision',rev,'data',d));
  if nullif(x->>'lotId','') is not null then
   update public.laundry_lots set data=data||jsonb_build_object('due',left(x->>'due',10),'deliveryAt',x->'due','scheduledArrival',x->'arrival','calendarId',x->'id') where id=(x->>'lotId')::bigint;
   update public.laundry_meta set revision=revision+1 where id;
  end if;
 elsif p_action='lot_create' then
  if (p_payload->>'productionRevision')::bigint is distinct from rev then raise exception 'PRODUCTION_REVISION_CONFLICT';end if;
  select value,(ordinality-1)::int into e,i from jsonb_array_elements(d->'calendars') with ordinality where value->>'id'=p_payload->>'calendarId';
  if e is null or coalesce((e->>'cancelled')::boolean,false) then raise exception 'APPOINTMENT_UNAVAILABLE';end if;
  if nullif(e->>'lotId','') is not null then raise exception 'APPOINTMENT_ALREADY_LINKED';end if;
  if not exists(select 1 from public.laundry_clients where id=e->>'clientId' and data->>'name'=p_payload->>'client' and data->>'active' is distinct from 'false') then raise exception 'LOT_CLIENT_MISMATCH';end if;
  x:=p_payload||jsonb_build_object('due',left(e->>'due',10));
  if nullif(x->>'airtableOrderId','') is not null then result:=laundry_private.airtable_lot_create(x);else result:=laundry_private.laundry_authenticated('lot_create',x);end if;
  lot:=(result->'lot')||jsonb_build_object('calendarId',e->>'id','deliveryAt',e->>'due','scheduledArrival',e->>'arrival');
  update public.laundry_lots set data=lot where id=(lot->>'id')::bigint;
  d:=jsonb_set(d,array['calendars',i::text,'lotId'],lot->'id');
  update public.laundry_production set data=d,revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'calendar_lot_link',jsonb_build_object('lotId',lot->'id','calendarId',e->'id'));
  return jsonb_set(result,'{lot}',lot);
 elsif p_action<>'read' then raise exception 'UNKNOWN_ACTION';end if;
 perform laundry_private.refresh_client_calendar();
 return jsonb_build_object('schedules',(select coalesce(jsonb_agg(data||jsonb_build_object('id',id,'clientId',client_id,'revision',revision) order by client_id,data->>'weekday',data->>'arrivalTime'),'[]') from laundry_private.client_schedules),'production',laundry_private.production('read','{}'));
end;$$;
revoke all on function laundry_private.client_calendar(text,jsonb) from public,anon,authenticated;
grant execute on function laundry_private.client_calendar(text,jsonb) to authenticated;
create function public.laundry_client_calendar(p_action text default 'read',p_payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select laundry_private.client_calendar(p_action,p_payload);$$;
revoke all on function public.laundry_client_calendar(text,jsonb) from public,anon,authenticated;
grant execute on function public.laundry_client_calendar(text,jsonb) to authenticated;
-- Daily rolling horizon, even when the application is closed. Dates use Europe/Rome.
create extension if not exists pg_cron;
select cron.schedule('mycroclean-recurring-calendar','15 3 * * *',$job$select laundry_private.refresh_client_calendar();$job$);
commit;
