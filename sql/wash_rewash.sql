-- Keep completed memberships while the existing current-membership pointer moves to a new cycle.
create table laundry_private.wash_item_history(
 batch_id uuid not null references public.laundry_wash_batches(id) on delete cascade,
 lot_id bigint not null references public.laundry_lots(id) on delete cascade,
 code text not null, completed_row jsonb not null, archived_at timestamptz not null default now(),
 primary key(batch_id,code)
);
alter table laundry_private.wash_item_history enable row level security;
revoke all on laundry_private.wash_item_history from public,anon,authenticated;
create or replace function laundry_private.queue_rewash(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare who jsonb; d jsonb; t jsonb; m jsonb; r jsonb; e jsonb; old_batch public.laundry_wash_batches; target public.laundry_wash_batches;
 lid bigint; code_value text; proc_id text; cap integer; qty integer;
begin
 perform laundry_private.require_permission('lots_work');
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 if who->>'role' not in ('admin','operator') then raise exception 'FORBIDDEN';end if;
 perform 1 from public.laundry_meta where id for update;
 perform laundry_private.wash_batch_tick();
 lid:=(p->>'lotId')::bigint;code_value:=p->>'code';
 select x into r from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') x where l.id=lid and x->>'code'=code_value;
 if r is null then raise exception 'PRODUCT_NOT_IN_LOT';end if;
 if r->>'state'='Uscito' then raise exception 'PRODUCT_ALREADY_EXITED';end if;
 select b.* into old_batch from public.laundry_wash_items wi join public.laundry_wash_batches b on b.id=wi.batch_id where wi.lot_id=lid and wi.code=code_value;
 if old_batch.id is null then raise exception 'WASH_BATCH_NOT_FOUND';end if;
 if old_batch.id::text is distinct from p->>'previousBatchId' then raise exception 'REWASH_ALREADY_QUEUED';end if;
 if old_batch.state<>'estimated' then raise exception 'WASH_BATCH_IN_PROGRESS';end if;
 select data into d from public.laundry_production where id for update;
 select x into t from jsonb_array_elements(d->'types') x where x->>'id'=p->>'programId' and coalesce(x->>'active','true')='true' and x->>'mode'='machine' and x->>'machineKind' in ('water','decon','dry');
 select x into m from jsonb_array_elements(d->'machines') x where x->>'id'=p->>'machineId' and coalesce(x->>'active','true')='true';
 select processing_id into proc_id from public.laundry_wash_links where program_id=t->>'id';
 if t is null or m is null or proc_id is null or t->>'machineKind' is distinct from m->>'kind' then raise exception 'INVALID_PROGRAM_LINK';end if;
 if not exists(select 1 from jsonb_array_elements(d->'stations') x where x->>'id'=t->>'station' and coalesce(x->>'active','true')='true') then raise exception 'STATION_INACTIVE';end if;
 cap:=nullif(m->>'capacity','')::integer;
 if cap is null or cap<1 then raise exception 'MACHINE_CAPACITY_REQUIRED';end if;
 if coalesce((t->>'value')::numeric,0)<=0 then raise exception 'CYCLE_DURATION_REQUIRED';end if;
 -- A ready partial cart can receive more rewash products until capacity; running carts cannot.
 select b.* into target from public.laundry_wash_batches b where b.lot_id=lid and b.program_id=t->>'id' and b.machine_id=m->>'id' and b.capacity=cap and b.state in ('gathering','ready') and (select count(*) from public.laundry_wash_items wi where wi.batch_id=b.id)<cap order by b.created_at limit 1 for update;
 if target.id is null then
  insert into public.laundry_wash_batches(lot_id,program_id,processing_id,machine_id,program_name,machine_name,machine_kind,capacity,created_by,state)
  values(lid,t->>'id',proc_id,m->>'id',t->>'name',m->>'name',m->>'kind',cap,who->>'email','ready') returning * into target;
 end if;
 insert into laundry_private.wash_item_history(batch_id,lot_id,code,completed_row) values(old_batch.id,lid,code_value,r);
 update public.laundry_wash_items set batch_id=target.id where lot_id=lid and code=code_value;
 update public.laundry_wash_batches set state='ready' where id=target.id;
 e:=jsonb_build_object('at',now(),'time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'action','Rilavaggio · inserito nel carrello · '||target.program_name||' · '||target.machine_name,'code',code_value,'lotId',lid,'actor',who->>'name','actorEmail',who->>'email','previousBatchId',old_batch.id,'batchId',target.id);
 r:=(r-'foldedAt'-'foldedBy'-'rewashRestore'-'washCompletionSource')||jsonb_build_object('state','Entrato','washed',false,'completed',false,'rewash',true,'rewashPending',true,'washBatchId',target.id,'washBatchState','ready','requiresFolding',true,'processingId',proc_id,'processingName',target.program_name,'washRequired',true);
 update public.laundry_lots l set data=jsonb_set(jsonb_set(l.data,'{rows}',(select jsonb_agg(case when x->>'code'=code_value then r else x end order by n) from jsonb_array_elements(l.data->'rows') with ordinality a(x,n))),'{events}',coalesce(l.data->'events','[]')||jsonb_build_array(e)) where id=lid;
 update public.laundry_products set data=jsonb_set(data,'{history}',coalesce(data->'history','[]')||jsonb_build_array(e)) where id=code_value;
 update public.laundry_meta set revision=revision+1 where id;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'wash_rewash_queued',e);
 return laundry_private.laundry_authenticated('snapshot','{}');
end $$;
revoke all on function laundry_private.queue_rewash(jsonb) from public,anon,authenticated;
create or replace function public.laundry_queue_rewash(p_payload jsonb) returns jsonb
language sql set search_path='' as $$select laundry_private.queue_rewash(p_payload);$$;
revoke all on function public.laundry_queue_rewash(jsonb) from public,anon;
grant execute on function public.laundry_queue_rewash(jsonb) to authenticated;
-- Match the existing RPC architecture: only the authenticated wrapper reaches private functions.
grant usage on schema laundry_private to authenticated;
grant execute on function laundry_private.queue_rewash(jsonb) to authenticated;

CREATE OR REPLACE FUNCTION laundry_private.wash_batch_tick()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d jsonb; old_d jsonb; b public.laundry_wash_batches; l jsonb; row_item jsonb; codes text[]; changed boolean:=false; completed_ids text[];
begin
 perform 1 from public.laundry_meta where id for update;
 select data into d from public.laundry_production where id for update; old_d:=d;
 for b in select * from public.laundry_wash_batches where state='running' order by created_at for update loop
  if not exists(select 1 from jsonb_array_elements(d->'machines') m where m->>'id'=b.machine_id and coalesce(m->>'active','true')='true') or exists(select 1 from jsonb_array_elements(d->'tickets') t where t->>'machineId'=b.machine_id and t->>'blocking'='true' and t->>'status'<>'closed') then
   update public.laundry_wash_batches set state='blocked',events=events||jsonb_build_array(jsonb_build_object('at',now(),'action','blocked_by_ticket')) where id=b.id;
   continue;
  end if;
  if b.expected_end>now() then continue;end if;
  update public.laundry_wash_batches set state='estimated' where id=b.id;
  select data into l from public.laundry_lots where id=b.lot_id for update;
  select array_agg(code) into codes from public.laundry_wash_items where batch_id=b.id;
  for row_item in select value from jsonb_array_elements(l->'rows') where value->>'code'=any(codes) loop
   if row_item->>'state'<>'Uscito' and coalesce(row_item->>'washed','false')<>'true' then
    update public.laundry_products set data=jsonb_set(data,'{wash}',to_jsonb(coalesce((data->>'wash')::integer,0)+1)) where id=row_item->>'code';
   end if;
  end loop;
  l:=jsonb_set(l,'{rows}',(select jsonb_agg(case when r->>'code'=any(codes) and r->>'state'<>'Uscito' then r||jsonb_build_object('state','In lavorazione','washed',true,'completed',false,'washBatchState','estimated','requiresFolding',true,'washBatchId',b.id,'washCompletionSource','program_estimate','rewashPending',false,'rewashCycles',coalesce((r->>'rewashCycles')::integer,0)+case when r->>'rewashPending'='true' then 1 else 0 end) else r end order by n) from jsonb_array_elements(l->'rows') with ordinality a(r,n)));
  l:=jsonb_set(l,'{events}',coalesce(l->'events','[]')||jsonb_build_array(jsonb_build_object('time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'action','Fine ciclo prevista · '||b.program_name||' · '||b.machine_name,'code','','actor','Sistema · durata programma')));
  update public.laundry_lots set data=l where id=b.lot_id;
  update public.laundry_wash_batches set state='estimated',events=events||jsonb_build_array(jsonb_build_object('at',now(),'action','expected_cycle_end')) where id=b.id;
  changed:=true;
 end loop;
 -- Reconcile only unstarted wash tasks fully covered by these new, elapsed batches.
 select coalesce(array_agg(t->>'id'),array[]::text[]) into completed_ids from jsonb_array_elements(d->'tasks') t
 where t->>'status'='pending' and coalesce(t->'sessions','[]')='[]'::jsonb and jsonb_array_length(coalesce(t->'items','[]'))>0
 and exists(select 1 from jsonb_array_elements(d->'types') typ where typ->>'id'=t->>'typeId' and typ->>'mode'='machine' and typ->>'machineKind' in ('water','decon','dry'))
 and not exists(select 1 from jsonb_array_elements(t->'items') i where not exists(select 1 from public.laundry_wash_items wi join public.laundry_wash_batches wb on wb.id=wi.batch_id where wi.lot_id=(i->>'lotId')::bigint and wi.code=i->>'code' and wb.state='estimated'));
 if cardinality(completed_ids)>0 then
  d:=jsonb_set(d,'{tasks}',(select jsonb_agg(case when t->>'id'=any(completed_ids) then t||jsonb_build_object('status','completed','completedAt',now(),'completionSource','machine_program_estimate','events',coalesce(t->'events','[]')||jsonb_build_array(jsonb_build_object('at',now(),'action','wash_batches_elapsed'))) else t end order by n) from jsonb_array_elements(d->'tasks') with ordinality a(t,n)));
  if jsonb_typeof(d->'plan')='object' then
   d:=jsonb_set(d,'{plan,allocations}',(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(d#>'{plan,allocations}') a where not(a->>'taskId'=any(completed_ids))));
   d:=jsonb_set(d,'{plan,issues}',(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(d#>'{plan,issues}') a where not(a->>'taskId'=any(completed_ids))));
   d:=jsonb_set(d,'{plan,stale}','true');
  end if;
  update public.laundry_production set data=d,revision=revision+1 where id;
 end if;
 perform laundry_private.wash_sync_product_phases();
 if changed then update public.laundry_meta set revision=revision+1 where id;end if;
end $function$;

CREATE OR REPLACE FUNCTION laundry_private.wash_batch_control(p_action text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare who jsonb; d jsonb; m jsonb; t jsonb; proc_id text; b public.laundry_wash_batches; bid uuid; lid bigint; n integer; cap integer; fold_row jsonb; fold_event jsonb; result jsonb; old_lid bigint; code_value text; actor text;
begin
 -- user_permission_guard
 if p_action='link' then perform laundry_private.require_permission('production_manage');elsif p_action in ('acquire','switch','finish','fold') then perform laundry_private.require_permission('lots_work');elsif p_action in ('start','interrupt') then perform laundry_private.require_permission('production_execute');end if;
 who:=laundry_private.laundry_authenticated('version','{}')->'user';actor:=who->>'email';
 if p_action not in ('read','link','acquire','start','interrupt','switch','finish','fold','reset_batch','delete_batch') then raise exception 'INVALID_ACTION';end if;
 if p_action<>'read' and who->>'role' not in ('admin','operator') then raise exception 'FORBIDDEN';end if;
 if p_action='link' then perform laundry_private.require_permission('production_manage');end if;
 perform 1 from public.laundry_meta where id for update;
 if p_action in ('reset_batch','delete_batch') then
  if p_action='reset_batch' then perform laundry_private.require_permission('production_execute');
  elsif who->>'role'<>'admin' then raise exception 'FORBIDDEN';end if;
  select * into b from public.laundry_wash_batches where id=(p->>'batchId')::uuid for update;
  if b.id is null then raise exception 'BATCH_NOT_FOUND';end if;
  if b.state='estimated' or (b.state='running' and b.expected_end<=now()) then raise exception 'BATCH_ALREADY_FINISHED';end if;
  if exists(select 1 from public.laundry_wash_items wi join public.laundry_lots ll on ll.id=wi.lot_id cross join lateral jsonb_array_elements(ll.data->'rows') r where wi.batch_id=b.id and r->>'code'=wi.code and (r->>'state'='Uscito' or r->>'washed'='true' or r->>'completed'='true')) then raise exception 'BATCH_PRODUCTS_ALREADY_PROCESSED';end if;
  select count(*) into n from public.laundry_wash_items where batch_id=b.id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor,auth.uid()::text,'wash_batch_'||p_action,jsonb_build_object('previousBatch',to_jsonb(b),'items',(select coalesce(jsonb_agg(to_jsonb(i)),'[]') from public.laundry_wash_items i where i.batch_id=b.id)));
  bid:=b.id;
  if p_action='delete_batch' then
   insert into public.laundry_wash_batches(lot_id,program_id,processing_id,machine_id,program_name,machine_name,machine_kind,capacity,created_by,state,events)
   values(b.lot_id,b.program_id,b.processing_id,b.machine_id,b.program_name,b.machine_name,b.machine_kind,b.capacity,actor,case when n>=b.capacity then 'ready' else 'gathering' end,jsonb_build_array(jsonb_build_object('at',now(),'action','cart_restored','actor',actor,'previousBatchId',b.id))) returning id into bid;
   update public.laundry_wash_items set batch_id=bid where batch_id=b.id;
   delete from public.laundry_wash_batches where id=b.id;
  else
   update public.laundry_wash_batches set state=case when n>=capacity then 'ready' else 'gathering' end,started_at=null,expected_end=null,started_by=null,duration_minutes=null,
   events=events||jsonb_build_array(jsonb_build_object('at',now(),'action','start_cancelled','actor',actor)) where id=b.id;
  end if;
  update public.laundry_lots ll set data=jsonb_set(ll.data,'{rows}',(select jsonb_agg(case when exists(select 1 from public.laundry_wash_items wi where wi.lot_id=ll.id and wi.batch_id=bid and wi.code=r->>'code') then (r-'foldedAt'-'foldedBy'-'washCompletionSource')||jsonb_build_object('state','Entrato','washed',false,'completed',false,'washBatchId',bid,'washBatchState',case when n>=b.capacity then 'ready' else 'gathering' end,'requiresFolding',true) else r end order by x.ord) from jsonb_array_elements(ll.data->'rows') with ordinality x(r,ord))) where ll.id=b.lot_id;
  update public.laundry_meta set revision=revision+1 where id;
  return laundry_private.wash_batch_control('read',jsonb_build_object('lotId',b.lot_id));
 end if;
 perform laundry_private.wash_batch_tick();
 select data into d from public.laundry_production where id for update;
 lid:=nullif(p->>'lotId','')::bigint;
 if p_action='fold' then
  code_value:=trim(p->>'code');
  select r into fold_row from public.laundry_lots ll cross join lateral jsonb_array_elements(ll.data->'rows') r where ll.id=lid and r->>'code'=code_value;
  if fold_row is null then raise exception 'PRODUCT_NOT_IN_LOT';end if;
  select wb.* into b from public.laundry_wash_items wi join public.laundry_wash_batches wb on wb.id=wi.batch_id where wi.lot_id=lid and wi.code=code_value;
  if b.id is null then raise exception 'WASH_BATCH_NOT_FOUND';end if;
  if b.state<>'estimated' or coalesce(fold_row->>'washed','false')<>'true' then raise exception 'WASH_BATCH_IN_PROGRESS';end if;
  if fold_row->>'state'='Uscito' then raise exception 'PRODUCT_ALREADY_EXITED';end if;
  if fold_row->>'repair'='true' or fold_row->>'relabel'='true' or fold_row->>'verify'='true' or fold_row->>'rewashPending'='true' then raise exception 'PRODUCT_INTERVENTIONS_PENDING';end if;
  if fold_row->>'completed'='true' and nullif(fold_row->>'foldedAt','') is not null then return laundry_private.laundry_authenticated('snapshot','{}')||jsonb_build_object('alreadyFolded',true);end if;
  fold_event:=jsonb_build_object('time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'at',now(),'action','Piegatura completata · Pronto per l’uscita','code',code_value,'actor',who->>'name','actorEmail',actor);
  update public.laundry_lots ll set data=jsonb_set(jsonb_set(ll.data,'{rows}',(select jsonb_agg(case when r->>'code'=code_value then r||jsonb_build_object('state','In lavorazione','completed',true,'foldedAt',now(),'foldedBy',actor) else r end order by x.n) from jsonb_array_elements(ll.data->'rows') with ordinality x(r,n))),'{events}',coalesce(ll.data->'events','[]')||jsonb_build_array(fold_event)) where ll.id=lid;
  update public.laundry_products set data=jsonb_set(data,'{history}',coalesce(data->'history','[]')||jsonb_build_array(fold_event||jsonb_build_object('lotId',lid))) where id=code_value;
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor,auth.uid()::text,'product_fold_scan',jsonb_build_object('lotId',lid,'code',code_value,'batchId',b.id));
  return laundry_private.laundry_authenticated('snapshot','{}');
 end if;
 if p_action='link' then
  select value into t from jsonb_array_elements(d->'types') where value->>'id'=p->>'programId' and value->>'mode'='machine' and value->>'machineKind' in ('water','decon','dry');
  if t is null or not exists(select 1 from public.laundry_processing where id=p->>'processingId' and data->>'active'='true' and data->>'wash'='true') then raise exception 'INVALID_PROGRAM_LINK';end if;
  insert into public.laundry_wash_links values(p->>'programId',p->>'processingId') on conflict(program_id) do update set processing_id=excluded.processing_id;
 elsif p_action in ('switch','finish') then
  select lot_id into old_lid from public.laundry_entry_sessions where email=actor and closed_at is null;
  if p_action='finish' then old_lid:=lid;end if;
  if old_lid is not null and (p_action='finish' or old_lid is distinct from lid) then
   update public.laundry_wash_batches set state='ready' where lot_id=old_lid and state='gathering';
   update public.laundry_entry_sessions set closed_at=now() where email=actor;
  end if;
  if p_action='switch' then
   if not exists(select 1 from public.laundry_lots where id=lid) then raise exception 'LOT_NOT_FOUND';end if;
   insert into public.laundry_entry_sessions(email,lot_id) values(actor,lid) on conflict(email) do update set lot_id=excluded.lot_id,closed_at=null;
  end if;
 elsif p_action='acquire' then
  select value into t from jsonb_array_elements(d->'types') where value->>'id'=p->>'programId' and coalesce(value->>'active','true')='true' and value->>'mode'='machine' and value->>'machineKind' in ('water','decon','dry');
  select value into m from jsonb_array_elements(d->'machines') where value->>'id'=p->>'machineId' and coalesce(value->>'active','true')='true';
  select processing_id into proc_id from public.laundry_wash_links where program_id=p->>'programId';
  cap:=nullif(m->>'capacity','')::integer;
  if t is null or m is null or t->>'machineKind' is distinct from m->>'kind' or proc_id is null then raise exception 'INVALID_PROGRAM_LINK';end if;
  if cap is null or cap<1 then raise exception 'MACHINE_CAPACITY_REQUIRED';end if;
  if not exists(select 1 from jsonb_array_elements(d->'stations') s where s->>'id'=t->>'station' and coalesce(s->>'active','true')='true') then raise exception 'STATION_INACTIVE';end if;
  code_value:=trim(p->>'code');
  -- Core acquisition and batch membership commit together; duplicate scans still fail in the core.
  result:=laundry_private.laundry_authenticated('lot_acquire',jsonb_build_object('lot_id',lid,'code',code_value,'processing_id',proc_id,'revision',p->'revision'));
  select * into b from public.laundry_wash_batches where lot_id=lid and program_id=t->>'id' and machine_id=m->>'id' and state='gathering' and capacity=cap order by created_at limit 1 for update;
  if b.id is null then
   insert into public.laundry_wash_batches(lot_id,program_id,processing_id,machine_id,program_name,machine_name,machine_kind,capacity,created_by)
   values(lid,t->>'id',proc_id,m->>'id',t->>'name',m->>'name',m->>'kind',cap,actor) returning * into b;
  end if;
  select data->'rows'->-1->>'code' into code_value from public.laundry_lots where id=lid;
  insert into public.laundry_wash_items values(lid,code_value,b.id);
  select count(*) into n from public.laundry_wash_items where batch_id=b.id;
  if n>=cap then update public.laundry_wash_batches set state='ready' where id=b.id;end if;
  insert into public.laundry_entry_sessions(email,lot_id) values(actor,lid) on conflict(email) do update set lot_id=excluded.lot_id,closed_at=null;
 elsif p_action in ('start','interrupt') then
  select * into b from public.laundry_wash_batches where id=(p->>'batchId')::uuid for update;
  if b.id is null then raise exception 'BATCH_NOT_FOUND';end if;
  if p_action='interrupt' then
   if b.state not in ('running','estimated') then raise exception 'BATCH_NOT_RUNNING';end if;
   if b.state='estimated' then raise exception 'CYCLE_ALREADY_ELAPSED';end if;
   update public.laundry_wash_batches set state='blocked',events=events||jsonb_build_array(jsonb_build_object('at',now(),'action','interrupted','actor',actor)) where id=b.id;
  else
   if b.state='running' then return jsonb_build_object('alreadyStarted',true);end if;
   if b.state not in ('gathering','ready','blocked') then raise exception 'BATCH_ALREADY_FINISHED';end if;
   select value into t from jsonb_array_elements(d->'types') where value->>'id'=b.program_id and coalesce(value->>'active','true')='true';
   select value into m from jsonb_array_elements(d->'machines') where value->>'id'=coalesce(nullif(p->>'machineId',''),b.machine_id) and coalesce(value->>'active','true')='true';
   select count(*) into n from public.laundry_wash_items where batch_id=b.id;
   if m is null or m->>'kind' is distinct from b.machine_kind or nullif(m->>'capacity','')::integer is null or (m->>'capacity')::integer<n then raise exception 'MACHINE_CAPACITY_REQUIRED';end if;
   if t is null or coalesce((t->>'value')::numeric,0)<=0 then raise exception 'CYCLE_DURATION_REQUIRED';end if;
   if exists(select 1 from jsonb_array_elements(d->'tickets') x where x->>'machineId'=m->>'id' and x->>'blocking'='true' and x->>'status'<>'closed') then raise exception 'MACHINE_UNAVAILABLE';end if;
   if exists(select 1 from public.laundry_wash_batches where machine_id=m->>'id' and state in ('running','blocked') and id<>b.id) then raise exception 'MACHINE_BUSY';end if;
   if exists(select 1 from jsonb_array_elements(d->'tasks') x join lateral jsonb_array_elements(d#>'{plan,allocations}') a on a->>'taskId'=x->>'id' where x->>'status' in ('running','paused') and a->>'machineId'=m->>'id') then raise exception 'MACHINE_BUSY';end if;
   if exists(select 1 from public.laundry_wash_items wi join public.laundry_lots ll on ll.id=wi.lot_id cross join lateral jsonb_array_elements(ll.data->'rows') r where wi.batch_id=b.id and r->>'code'=wi.code and (r->>'state'='Uscito' or r->>'washed'='true')) then raise exception 'BATCH_PRODUCTS_ALREADY_PROCESSED';end if;
   update public.laundry_wash_batches set state='running',machine_id=m->>'id',machine_name=m->>'name',capacity=(m->>'capacity')::integer,duration_minutes=(t->>'value')::numeric,started_at=now(),expected_end=now()+((t->>'value')::numeric*interval '1 minute'),started_by=actor,
   events=events||jsonb_build_array(jsonb_build_object('at',now(),'action','start','actor',actor,'machineId',m->>'id','minutes',t->'value')) where id=b.id;
  end if;
 end if;
 if p_action in ('acquire','start','interrupt') then perform laundry_private.wash_sync_product_phases();end if;
 if p_action not in ('read','switch') then insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor,auth.uid()::text,'wash_batch_'||p_action,jsonb_build_object('lotId',lid,'batchId',coalesce(b.id,null),'programId',p->>'programId'));end if;
 if p_action='acquire' then return laundry_private.laundry_authenticated('snapshot','{}');end if;
 return jsonb_build_object('serverTime',now(),'machines',d->'machines','types',d->'types','tickets',d->'tickets','stations',d->'stations',
 'links',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.laundry_wash_links x),
 'batches',(select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('quantity',(select count(*) from public.laundry_wash_items i where i.batch_id=x.id)+(select count(*) from laundry_private.wash_item_history h where h.batch_id=x.id)) order by x.created_at),'[]') from public.laundry_wash_batches x where x.state<>'estimated' or x.lot_id=lid or x.expected_end>now()-interval '1 day'));
end $function$;

-- Historical rewash markers remain visible even if an older client clears the checkbox.
create or replace function laundry_private.keep_rewash_marker() returns trigger
language plpgsql set search_path='' as $$
begin
 if exists(select 1 from jsonb_array_elements(coalesce(new.data->'rows','[]')) r where coalesce((r->>'rewashCycles')::integer,0)>0 and coalesce(r->>'rewash','false')<>'true') then
  new.data:=jsonb_set(new.data,'{rows}',(select jsonb_agg(case when coalesce((r->>'rewashCycles')::integer,0)>0 then r||jsonb_build_object('rewash',true) else r end order by n) from jsonb_array_elements(new.data->'rows') with ordinality x(r,n)));
 end if;
 return new;
end $$;
revoke all on function laundry_private.keep_rewash_marker() from public,anon,authenticated;
create trigger keep_rewash_marker before update of data on public.laundry_lots for each row execute function laundry_private.keep_rewash_marker();
