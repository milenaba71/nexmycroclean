CREATE OR REPLACE FUNCTION laundry_private.production_validate(d jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare k text; x jsonb; t jsonb; old_t jsonb; i jsonb; dep text; v numeric; seen text[]; old_data jsonb; kinds jsonb;
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

 select data into old_data from public.laundry_production where id;
 kinds:=coalesce(d->'machineKinds',old_data->'machineKinds','[{"id":"decon","name":"Lavaggio e decontaminazione"},{"id":"dry","name":"Lavaggio a secco"},{"id":"water","name":"Lavaggio ad acqua"},{"id":"dryer","name":"Asciugatura"}]'::jsonb);
 if jsonb_typeof(kinds) is distinct from 'array' then raise exception 'INVALID_MACHINE_KIND_CATALOG';end if;
 if jsonb_array_length(kinds)<1 or jsonb_array_length(kinds)>200 then raise exception 'INVALID_MACHINE_KIND_CATALOG';end if;
 if exists(select 1 from jsonb_array_elements(kinds) kind_entry where jsonb_typeof(kind_entry)<>'object' or nullif(btrim(kind_entry->>'id'),'') is null or length(kind_entry->>'id')>100 or nullif(btrim(kind_entry->>'name'),'') is null or length(kind_entry->>'name')>100) then raise exception 'INVALID_MACHINE_KIND_CATALOG';end if;
 if (select count(*) from jsonb_array_elements(kinds))<>(select count(distinct kind_entry->>'id') from jsonb_array_elements(kinds) kind_entry)
 or (select count(*) from jsonb_array_elements(kinds))<>(select count(distinct lower(btrim(kind_entry->>'name'))) from jsonb_array_elements(kinds) kind_entry) then raise exception 'INVALID_MACHINE_KIND_CATALOG';end if;
 if exists(select 1 from jsonb_array_elements(coalesce(old_data->'machineKinds','[{"id":"decon","name":"Lavaggio e decontaminazione"},{"id":"dry","name":"Lavaggio a secco"},{"id":"water","name":"Lavaggio ad acqua"},{"id":"dryer","name":"Asciugatura"}]'::jsonb)) kind_entry where not exists(select 1 from jsonb_array_elements(kinds) n where n->>'id'=kind_entry->>'id')) then raise exception 'PRESERVE_MACHINE_KINDS';end if;
 if exists(select 1 from jsonb_array_elements(d->'types') work_entry where work_entry->>'mode'='machine' and not exists(select 1 from jsonb_array_elements(kinds) kind_entry where kind_entry->>'id'=work_entry->>'machineKind')) then raise exception 'INVALID_MACHINE_KIND';end if;

 for x in select value from jsonb_array_elements(d->'machines') loop
  if nullif(btrim(x->>'name'),'') is null or not exists(select 1 from jsonb_array_elements(kinds) kind_entry where kind_entry->>'id'=x->>'kind') or (x->>'capacity')::numeric<=0 then raise exception 'INVALID_MACHINE';end if;
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
end;$function$
