-- Explicit administrator actions only; no mutation on reads.
create or replace function laundry_private.planning_delete_control(p_action text,p jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare who jsonb; d jsonb; rev bigint; meta_rev bigint; lid bigint; l jsonb; ids text[]; note text; old_data jsonb;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 if who->>'role' is distinct from 'admin' then raise exception 'FORBIDDEN';end if;
 if p_action not in ('clear_plan','reset_route','delete_lot') then raise exception 'INVALID_ACTION';end if;
 note:=trim(coalesce(p->>'reason',''));
 if length(note)<3 or length(note)>500 then raise exception 'REASON_REQUIRED';end if;
 -- Match the normal lot-write lock order, and reject stale browser submissions.
 select revision into meta_rev from public.laundry_meta where id for update;
 select data,revision into d,rev from public.laundry_production where id for update;
 if (p->>'revision')::bigint is distinct from rev or (p->>'lotRevision')::bigint is distinct from meta_rev then raise exception 'REVISION_CONFLICT';end if;
 old_data:=d;
 if p_action='clear_plan' then
  if exists(select 1 from jsonb_array_elements(d->'tasks') t where t->>'status' in ('running','paused')) then raise exception 'PLAN_HAS_STARTED_TASKS';end if;
  if jsonb_typeof(d->'plan')='object' then d:=jsonb_set(d,'{planHistory}',coalesce(d->'planHistory','[]')||jsonb_build_array(d->'plan'));end if;
  d:=jsonb_set(d,'{plan}','null');
 else
  lid:=(p->>'lotId')::bigint;
  select data into l from public.laundry_lots where id=lid for update;
  if l is null then raise exception 'LOT_NOT_FOUND';end if;
  if p->>'confirm' is distinct from lid::text then raise exception 'LOT_CONFIRM_REQUIRED';end if;
  select coalesce(array_agg(t->>'id'),array[]::text[]) into ids from jsonb_array_elements(d->'tasks') t where (t->>'routeLotId'=lid::text or exists(select 1 from jsonb_array_elements(t->'items') i where i->>'lotId'=lid::text)) and (p_action='delete_lot' or coalesce(t->>'routeRetired','false')<>'true');
  if exists(select 1 from jsonb_array_elements(d->'tasks') t where t->>'id'=any(ids) and (exists(select 1 from jsonb_array_elements(t->'items') i where i->>'lotId'<>lid::text) or (t->>'routeLotId' is not null and t->>'routeLotId'<>lid::text))) then raise exception 'SHARED_TASK';end if;
  if exists(select 1 from jsonb_array_elements(d->'tasks') t cross join lateral jsonb_array_elements_text(t->'dependsOn') dep where not(t->>'id'=any(ids)) and (p_action='delete_lot' or t->>'status' not in ('cancelled','completed')) and dep=any(ids)) then raise exception 'DEPENDENT_TASKS';end if;
  if exists(select 1 from jsonb_array_elements(d->'tasks') t where t->>'id'=any(ids) and t->>'status' in ('running','paused')) then raise exception 'ROUTE_HAS_STARTED_TASKS';end if;
  if p_action='delete_lot' then
   if exists(select 1 from jsonb_array_elements(l->'rows') r where r->>'state' is distinct from 'Entrato' or coalesce((r->>'washed')::boolean,false) or coalesce((r->>'completed')::boolean,false) or jsonb_array_length(coalesce(r->'repairWork','[]'))>0)
    or exists(select 1 from public.laundry_repairs where lot_id=lid and status='completed')
    or exists(select 1 from jsonb_array_elements(d->'tasks') t where t->>'id'=any(ids) and (t->>'status'='completed' or jsonb_array_length(coalesce(t->'sessions','[]'))>0)) then raise exception 'LOT_HAS_WORK_HISTORY';end if;
   -- Preserve a complete recovery record, including unstarted planning, before deletion.
   insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'lot_deleted',jsonb_build_object('lot',l,'reason',note,'tasks',(select coalesce(jsonb_agg(t),'[]') from jsonb_array_elements(d->'tasks') t where t->>'id'=any(ids)),'repairs',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from public.laundry_repairs r where lot_id=lid)));
   delete from public.laundry_repairs where lot_id=lid;
   delete from public.laundry_lots where id=lid;
   d:=jsonb_set(d,'{tasks}',(select coalesce(jsonb_agg(t),'[]') from jsonb_array_elements(d->'tasks') t where not(t->>'id'=any(ids))));
   d:=jsonb_set(d,'{calendars}',(select coalesce(jsonb_agg(case when c->>'lotId'=lid::text then jsonb_set(c,'{lotId}','null') else c end),'[]') from jsonb_array_elements(d->'calendars') c));
   update public.laundry_meta set revision=revision+1 where id;
  else
   if cardinality(ids)=0 then raise exception 'NO_ROUTE';end if;
   d:=jsonb_set(d,'{tasks}',(select jsonb_agg(case when t->>'id'=any(ids) then t||jsonb_build_object('routeRetired',true,'status',case when t->>'status'='pending' then 'cancelled' else t->>'status' end,'events',coalesce(t->'events','[]')||jsonb_build_array(jsonb_build_object('at',now(),'actor',who->>'email','action','reset_route','note',note))) else t end) from jsonb_array_elements(d->'tasks') t));
  end if;
  if jsonb_typeof(d->'plan')='object' then
   d:=jsonb_set(d,'{planHistory}',coalesce(d->'planHistory','[]')||jsonb_build_array(d->'plan'));
   d:=jsonb_set(d,'{plan,allocations}',(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(d->'plan'->'allocations') a where not(a->>'taskId'=any(ids))));
   d:=jsonb_set(d,'{plan,issues}',(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(d->'plan'->'issues') a where not(a->>'taskId'=any(ids))));
   d:=jsonb_set(d,'{plan,stale}','true');
  end if;
 end if;
 update public.laundry_production set data=d,revision=revision+1 where id;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'planning_'||p_action,jsonb_build_object('lotId',lid,'reason',note,'previousPlan',old_data->'plan','revision',rev+1));
 return jsonb_build_object('ok',true);
end;$$;
revoke all on function laundry_private.planning_delete_control(text,jsonb) from public,anon;
grant execute on function laundry_private.planning_delete_control(text,jsonb) to authenticated;
create or replace function public.laundry_planning_delete(p_action text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select laundry_private.planning_delete_control(p_action,p)$$;
revoke all on function public.laundry_planning_delete(text,jsonb) from public,anon;
grant execute on function public.laundry_planning_delete(text,jsonb) to authenticated;
