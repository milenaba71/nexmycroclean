-- Entry-driven machine batches. Existing core/auth functions are not replaced.
create table if not exists public.laundry_wash_links(program_id text primary key, processing_id text not null references public.laundry_processing(id));
create table if not exists public.laundry_wash_batches(
 id uuid primary key default gen_random_uuid(), lot_id bigint not null references public.laundry_lots(id) on delete cascade,
 program_id text not null, processing_id text not null, machine_id text not null,
 program_name text not null, machine_name text not null, machine_kind text not null,
 capacity integer not null check(capacity>0), duration_minutes numeric,
 state text not null check(state in ('gathering','ready','running','estimated','blocked')) default 'gathering',
 created_at timestamptz not null default now(), created_by text not null,
 started_at timestamptz, expected_end timestamptz, started_by text, events jsonb not null default '[]');
create table if not exists public.laundry_wash_items(
 lot_id bigint not null references public.laundry_lots(id) on delete cascade,code text not null,
 batch_id uuid not null references public.laundry_wash_batches(id) on delete cascade,primary key(lot_id,code));
create index if not exists laundry_wash_items_batch on public.laundry_wash_items(batch_id);
create table if not exists public.laundry_entry_sessions(email text primary key,lot_id bigint not null references public.laundry_lots(id) on delete cascade,closed_at timestamptz);
alter table public.laundry_wash_links enable row level security;
alter table public.laundry_wash_batches enable row level security;
alter table public.laundry_wash_items enable row level security;
alter table public.laundry_entry_sessions enable row level security;
revoke all on public.laundry_wash_links,public.laundry_wash_batches,public.laundry_wash_items,public.laundry_entry_sessions from public,anon,authenticated;
-- Only unambiguous, identical names are linked. Other programs are linked explicitly by an administrator.
insert into public.laundry_wash_links(program_id,processing_id)
select t->>'id',min(p.id) from public.laundry_production d cross join lateral jsonb_array_elements(d.data->'types') t
join public.laundry_processing p on lower(trim(p.data->>'name'))=lower(trim(t->>'name')) and p.data->>'active'='true' and p.data->>'wash'='true'
where t->>'mode'='machine' and t->>'machineKind' in ('water','decon','dry') group by t->>'id' having count(*)=1 on conflict do nothing;


-- A named program inherits the unambiguous entry category matching its configured machine kind.
insert into public.laundry_wash_links(program_id,processing_id)
select t->>'id',min(p.id) from public.laundry_production d cross join lateral jsonb_array_elements(d.data->'types') t
join public.laundry_processing p on lower(trim(p.data->>'name'))=case t->>'machineKind' when 'water' then 'lavaggio ad acqua' when 'decon' then 'lavaggio e decontaminazione' when 'dry' then 'lavaggio a secco' end
and p.data->>'active'='true' and p.data->>'wash'='true'
where t->>'mode'='machine' group by t->>'id' having count(*)=1 on conflict do nothing;

create or replace function laundry_private.wash_batch_tick() returns void
language plpgsql security definer set search_path='' as $$
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
  l:=jsonb_set(l,'{rows}',(select jsonb_agg(case when r->>'code'=any(codes) and r->>'state'<>'Uscito' then r||jsonb_build_object('state','In lavorazione','washed',true,'completed',true,'washBatchId',b.id,'washCompletionSource','program_estimate') else r end order by n) from jsonb_array_elements(l->'rows') with ordinality a(r,n)));
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
 if changed then update public.laundry_meta set revision=revision+1 where id;end if;
end $$;
revoke all on function laundry_private.wash_batch_tick() from public,anon,authenticated;

create or replace function laundry_private.wash_batch_control(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare who jsonb; d jsonb; m jsonb; t jsonb; proc_id text; b public.laundry_wash_batches; bid uuid; lid bigint; n integer; cap integer; result jsonb; old_lid bigint; code_value text; actor text;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';actor:=who->>'email';
 if p_action not in ('read','link','acquire','start','interrupt','switch','finish') then raise exception 'INVALID_ACTION';end if;
 if p_action<>'read' and who->>'role' not in ('admin','operator') then raise exception 'FORBIDDEN';end if;
 if p_action='link' and who->>'role'<>'admin' then raise exception 'FORBIDDEN';end if;
 perform 1 from public.laundry_meta where id for update;
 perform laundry_private.wash_batch_tick();
 select data into d from public.laundry_production where id for update;
 lid:=nullif(p->>'lotId','')::bigint;
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
 if p_action not in ('read','switch') then insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor,auth.uid()::text,'wash_batch_'||p_action,jsonb_build_object('lotId',lid,'batchId',coalesce(b.id,null),'programId',p->>'programId'));end if;
 if p_action='acquire' then return result;end if;
 return jsonb_build_object('serverTime',now(),'machines',d->'machines','types',d->'types','tickets',d->'tickets','stations',d->'stations',
 'links',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.laundry_wash_links x),
 'batches',(select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('quantity',(select count(*) from public.laundry_wash_items i where i.batch_id=x.id)) order by x.created_at),'[]') from public.laundry_wash_batches x where x.state<>'estimated' or x.lot_id=lid or x.expected_end>now()-interval '1 day'));
end $$;
revoke all on function laundry_private.wash_batch_control(text,jsonb) from public,anon,authenticated;
grant execute on function laundry_private.wash_batch_control(text,jsonb) to authenticated;
create or replace function public.laundry_wash_batches(p_action text,p_payload jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select laundry_private.wash_batch_control(p_action,p_payload)$$;
revoke all on function public.laundry_wash_batches(text,jsonb) from public,anon;
grant execute on function public.laundry_wash_batches(text,jsonb) to authenticated;

-- An existing barcode endpoint cannot bypass an outstanding cart or machine cycle.
create or replace function laundry_private.wash_batch_guard_lot() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.laundry_wash_items wi join public.laundry_wash_batches b on b.id=wi.batch_id
 cross join lateral jsonb_array_elements(new.data->'rows') r
 where wi.lot_id=new.id and r->>'code'=wi.code and b.state<>'estimated'
 and (r->>'state'='Uscito' or r->>'washed'='true')
 and not exists(select 1 from jsonb_array_elements(old.data->'rows') o where o->>'code'=wi.code and o->>'state'=r->>'state' and coalesce(o->>'washed','false')=coalesce(r->>'washed','false'))) then raise exception 'WASH_BATCH_IN_PROGRESS';end if;
 return new;
end $$;
revoke all on function laundry_private.wash_batch_guard_lot() from public,anon,authenticated;
create trigger wash_batch_guard_lot before update on public.laundry_lots for each row execute function laundry_private.wash_batch_guard_lot();

create or replace function laundry_private.wash_batch_guard_production() returns trigger
language plpgsql security definer set search_path='' as $$
declare t jsonb; a jsonb;
begin
 for t in select value from jsonb_array_elements(new.data->'tasks') where value->>'status'='running' loop
  if exists(select 1 from jsonb_array_elements(old.data->'tasks') x where x->>'id'=t->>'id' and x->>'status'='running') then continue;end if;
  if exists(select 1 from jsonb_array_elements(t->'items') i join public.laundry_wash_items wi on wi.lot_id=(i->>'lotId')::bigint and wi.code=i->>'code' join public.laundry_wash_batches b on b.id=wi.batch_id where b.state<>'estimated') then raise exception 'WASH_BATCH_IN_PROGRESS';end if;
  select value into a from jsonb_array_elements(new.data#>'{plan,allocations}') where value->>'taskId'=t->>'id';
  if exists(select 1 from public.laundry_wash_batches b where b.machine_id=a->>'machineId' and b.state in ('running','blocked')) then raise exception 'MACHINE_BUSY';end if;
 end loop;
 return new;
end $$;
revoke all on function laundry_private.wash_batch_guard_production() from public,anon,authenticated;
create trigger wash_batch_guard_production before update on public.laundry_production for each row execute function laundry_private.wash_batch_guard_production();

-- Production has pg_cron installed; local tests may omit the extension.
do $$begin
 if exists(select 1 from pg_namespace where nspname='cron') then
  perform cron.schedule('laundry-wash-batch-tick','* * * * *','select laundry_private.wash_batch_tick()');
 end if;
end $$;
create or replace function laundry_private.wash_batch_guard_delete() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.laundry_wash_batches where lot_id=old.id and started_at is not null) then raise exception 'LOT_HAS_WORK_HISTORY';end if;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(null,auth.uid()::text,'wash_carts_deleted_with_unworked_lot',jsonb_build_object('lotId',old.id,'batches',(select coalesce(jsonb_agg(to_jsonb(b)),'[]') from public.laundry_wash_batches b where b.lot_id=old.id)));
 return old;
end $$;
revoke all on function laundry_private.wash_batch_guard_delete() from public,anon,authenticated;
create trigger wash_batch_guard_delete before delete on public.laundry_lots for each row execute function laundry_private.wash_batch_guard_delete();
