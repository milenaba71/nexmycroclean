-- Administrator-only selective removal. Never deletes lots or product movements.
create or replace function laundry_private.production_bulk_delete(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare who jsonb; d jsonb; rev bigint; ids text[]; old_data jsonb; mode text; note text;
begin
 -- user_permission_guard: preserve custom powers if this script is reapplied after user_permissions.sql.
 if to_regprocedure('laundry_private.require_permission(text)') is not null then perform laundry_private.require_permission('planning_delete');end if;
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 if who->>'role' is distinct from 'admin' then raise exception 'FORBIDDEN';end if;
 mode:=p->>'mode';note:=trim(coalesce(p->>'reason',''));
 if mode is null or mode not in ('assignments','tasks') then raise exception 'INVALID_ACTION';end if;
 if length(note)<3 or length(note)>500 then raise exception 'REASON_REQUIRED';end if;
 if jsonb_typeof(p->'ids') is distinct from 'array' then raise exception 'SELECTION_REQUIRED';end if;
 select array_agg(distinct x) into ids from jsonb_array_elements_text(p->'ids') x;
 if coalesce(cardinality(ids),0)=0 or cardinality(ids)>1000 then raise exception 'SELECTION_REQUIRED';end if;
 perform 1 from public.laundry_meta where id for update;
 select data,revision into d,rev from public.laundry_production where id for update;
 if (p->>'revision')::bigint is distinct from rev then raise exception 'REVISION_CONFLICT';end if;
 if (select count(*) from jsonb_array_elements(d->'tasks') t where t->>'id'=any(ids))<>cardinality(ids) then raise exception 'SELECTION_CHANGED';end if;
 if exists(select 1 from jsonb_array_elements(d->'tasks') t where t->>'id'=any(ids) and (t->>'status' not in ('pending','cancelled') or jsonb_array_length(coalesce(t->'sessions','[]'))>0 or t->>'startedAt' is not null or t->>'completedAt' is not null)) then raise exception 'TASK_HAS_WORK_HISTORY';end if;
 if mode='tasks' and exists(select 1 from jsonb_array_elements(d->'tasks') t cross join lateral jsonb_array_elements_text(t->'dependsOn') dep where not(t->>'id'=any(ids)) and dep=any(ids)) then raise exception 'SELECT_DEPENDENT_TASKS';end if;
 old_data:=d;
 if mode='tasks' then
  d:=jsonb_set(d,'{tasks}',(select coalesce(jsonb_agg(t order by n),'[]') from jsonb_array_elements(d->'tasks') with ordinality a(t,n) where not(t->>'id'=any(ids))));
 else
  d:=jsonb_set(d,'{tasks}',(select jsonb_agg(case when t->>'id'=any(ids) then t||jsonb_build_object('assignee',null) else t end order by n) from jsonb_array_elements(d->'tasks') with ordinality a(t,n)));
 end if;
 if jsonb_typeof(d->'plan')='object' then
  d:=jsonb_set(d,'{planHistory}',coalesce(d->'planHistory','[]')||jsonb_build_array(d->'plan'));
  d:=jsonb_set(d,'{plan,allocations}',(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(d#>'{plan,allocations}') a where not(a->>'taskId'=any(ids))));
  d:=jsonb_set(d,'{plan,issues}',(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(d#>'{plan,issues}') a where not(a->>'taskId'=any(ids))));
  d:=jsonb_set(d,'{plan,stale}','true');
 end if;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'production_bulk_delete_'||mode,jsonb_build_object('reason',note,'ids',ids,'tasks',(select jsonb_agg(t) from jsonb_array_elements(old_data->'tasks') t where t->>'id'=any(ids)),'previousPlan',old_data->'plan'));
 update public.laundry_production set data=d,revision=revision+1 where id;
 return jsonb_build_object('count',cardinality(ids),'revision',rev+1);
end $$;
revoke all on function laundry_private.production_bulk_delete(jsonb) from public,anon;
grant execute on function laundry_private.production_bulk_delete(jsonb) to authenticated;
create or replace function public.laundry_production_bulk_delete(p jsonb) returns jsonb
language sql security invoker set search_path='' as $$select laundry_private.production_bulk_delete(p)$$;
revoke all on function public.laundry_production_bulk_delete(jsonb) from public,anon;
grant execute on function public.laundry_production_bulk_delete(jsonb) to authenticated;
