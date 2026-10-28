-- Mandatory drying for water-wash carts. Decontamination and dry-cleaning carts still go straight to folding.
-- Install after wash_batch_corrections.sql. Only carts started after this migration require drying;
-- carts already started or finished keep their current phases.
alter table public.laundry_wash_batches add column if not exists requires_drying boolean not null default false;
create table if not exists public.laundry_dry_cycles(
 id uuid primary key default gen_random_uuid(),
 wash_batch_id uuid not null unique references public.laundry_wash_batches(id) on delete cascade,
 program_id text not null, program_name text not null, machine_id text not null, machine_name text not null,
 duration_minutes numeric not null check(duration_minutes>0),
 state text not null check(state in ('running','blocked','estimated')) default 'running',
 started_at timestamptz not null default now(), expected_end timestamptz not null, started_by text not null,
 events jsonb not null default '[]');
create index if not exists laundry_dry_cycles_machine on public.laundry_dry_cycles(machine_id) where state in ('running','blocked');
alter table public.laundry_dry_cycles enable row level security;
revoke all on public.laundry_dry_cycles from public,anon,authenticated;

-- A water cart needs drying from the moment it is loaded into the washer.
create or replace function laundry_private.wash_batch_mark_drying() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.state='running' and new.machine_kind='water' then new.requires_drying:=true;end if;
 return new;
end $$;
revoke all on function laundry_private.wash_batch_mark_drying() from public,anon,authenticated;
create trigger wash_batch_mark_drying before update of state on public.laundry_wash_batches for each row execute function laundry_private.wash_batch_mark_drying();

-- The expected end counts even before the next minute tick.
create or replace function laundry_private.dry_done(bid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.laundry_dry_cycles c where c.wash_batch_id=bid and (c.state='estimated' or (c.state='running' and c.expected_end<=now())))
$$;
revoke all on function laundry_private.dry_done(uuid) from public,anon,authenticated;

-- Folding or exit cannot be registered by any endpoint before the drying cycle ends.
create or replace function laundry_private.dry_guard_lot() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.laundry_wash_items wi join public.laundry_wash_batches b on b.id=wi.batch_id
 cross join lateral jsonb_array_elements(new.data->'rows') r
 where wi.lot_id=new.id and r->>'code'=wi.code and b.requires_drying and not laundry_private.dry_done(b.id)
 and (nullif(r->>'foldedAt','') is not null or r->>'state'='Uscito')
 and not exists(select 1 from jsonb_array_elements(old.data->'rows') o where o->>'code'=wi.code and coalesce(o->>'foldedAt','')=coalesce(r->>'foldedAt','') and o->>'state'=r->>'state')) then raise exception 'DRYING_REQUIRED';end if;
 return new;
end $$;
revoke all on function laundry_private.dry_guard_lot() from public,anon,authenticated;
create trigger dry_guard_lot before update of data on public.laundry_lots for each row execute function laundry_private.dry_guard_lot();

-- Lot rows show the drying phase; the lot state stays "In lavorazione" as for folding.
create or replace function laundry_private.dry_sync_product_phases() returns void
language plpgsql security definer set search_path='' as $$
declare l record; next_rows jsonb; changed boolean:=false;
begin
 for l in select ll.* from public.laundry_lots ll where exists(select 1 from public.laundry_wash_items i join public.laundry_wash_batches b on b.id=i.batch_id where i.lot_id=ll.id and b.requires_drying) for update loop
  select jsonb_agg(case when b.id is null or not b.requires_drying or r->>'state'='Uscito' then r
   when b.state<>'estimated' then (r-'dryCycleId')||jsonb_build_object('requiresDrying',true,'dryState','waiting_wash')
   when c.id is null then (r-'dryCycleId')||jsonb_build_object('requiresDrying',true,'dryState','pending')
   else r||jsonb_build_object('requiresDrying',true,'dryState',case when c.state='estimated' then 'done' else c.state end,'dryCycleId',c.id) end order by n)
  into next_rows from jsonb_array_elements(l.data->'rows') with ordinality x(r,n)
  left join public.laundry_wash_items wi on wi.lot_id=l.id and wi.code=r->>'code'
  left join public.laundry_wash_batches b on b.id=wi.batch_id
  left join public.laundry_dry_cycles c on c.wash_batch_id=b.id;
  if next_rows is distinct from l.data->'rows' then update public.laundry_lots set data=jsonb_set(data,'{rows}',next_rows) where id=l.id;changed:=true;end if;
 end loop;
 if changed then update public.laundry_meta set revision=revision+1 where id;end if;
end $$;
revoke all on function laundry_private.dry_sync_product_phases() from public,anon,authenticated;

create or replace function laundry_private.dry_cycle_tick() returns void
language plpgsql security definer set search_path='' as $$
declare d jsonb; c public.laundry_dry_cycles; lid bigint; changed boolean:=false; completed_ids text[];
begin
 perform 1 from public.laundry_meta where id for update;
 select data into d from public.laundry_production where id for update;
 for c in select * from public.laundry_dry_cycles where state='running' order by started_at for update loop
  if not exists(select 1 from jsonb_array_elements(d->'machines') m where m->>'id'=c.machine_id and coalesce(m->>'active','true')='true') or exists(select 1 from jsonb_array_elements(d->'tickets') t where t->>'machineId'=c.machine_id and t->>'blocking'='true' and t->>'status'<>'closed') then
   update public.laundry_dry_cycles set state='blocked',events=events||jsonb_build_array(jsonb_build_object('at',now(),'action','blocked_by_ticket')) where id=c.id;
   changed:=true;continue;
  end if;
  if c.expected_end>now() then continue;end if;
  select lot_id into lid from public.laundry_wash_batches where id=c.wash_batch_id;
  update public.laundry_lots set data=jsonb_set(data,'{events}',coalesce(data->'events','[]')||jsonb_build_array(jsonb_build_object('time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'action','Fine asciugatura prevista · '||c.program_name||' · '||c.machine_name,'code','','actor','Sistema · durata programma'))) where id=lid;
  update public.laundry_dry_cycles set state='estimated',events=events||jsonb_build_array(jsonb_build_object('at',now(),'action','expected_cycle_end')) where id=c.id;
  changed:=true;
 end loop;
 -- Reconcile only unstarted drying tasks fully covered by elapsed drying cycles.
 select coalesce(array_agg(t->>'id'),array[]::text[]) into completed_ids from jsonb_array_elements(d->'tasks') t
 where t->>'status'='pending' and coalesce(t->'sessions','[]')='[]'::jsonb and jsonb_array_length(coalesce(t->'items','[]'))>0
 and exists(select 1 from jsonb_array_elements(d->'types') typ where typ->>'id'=t->>'typeId' and typ->>'mode'='machine' and typ->>'machineKind'='dryer')
 and not exists(select 1 from jsonb_array_elements(t->'items') i where not exists(select 1 from public.laundry_wash_items wi join public.laundry_dry_cycles dc on dc.wash_batch_id=wi.batch_id where wi.lot_id=(i->>'lotId')::bigint and wi.code=i->>'code' and dc.state='estimated'));
 if cardinality(completed_ids)>0 then
  d:=jsonb_set(d,'{tasks}',(select jsonb_agg(case when t->>'id'=any(completed_ids) then t||jsonb_build_object('status','completed','completedAt',now(),'completionSource','machine_program_estimate','events',coalesce(t->'events','[]')||jsonb_build_array(jsonb_build_object('at',now(),'action','dry_cycles_elapsed'))) else t end order by n) from jsonb_array_elements(d->'tasks') with ordinality a(t,n)));
  if jsonb_typeof(d->'plan')='object' then
   d:=jsonb_set(d,'{plan,allocations}',(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(d#>'{plan,allocations}') a where not(a->>'taskId'=any(completed_ids))));
   d:=jsonb_set(d,'{plan,issues}',(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(d#>'{plan,issues}') a where not(a->>'taskId'=any(completed_ids))));
   d:=jsonb_set(d,'{plan,stale}','true');
  end if;
  update public.laundry_production set data=d,revision=revision+1 where id;
 end if;
 perform laundry_private.dry_sync_product_phases();
 if changed then update public.laundry_meta set revision=revision+1 where id;end if;
end $$;
revoke all on function laundry_private.dry_cycle_tick() from public,anon,authenticated;

create or replace function laundry_private.dry_cycle_control(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare who jsonb; actor text; d jsonb; t jsonb; m jsonb; b public.laundry_wash_batches; c public.laundry_dry_cycles; n integer; admin boolean;
begin
 if p_action not in ('read','start','interrupt','reset') then raise exception 'INVALID_ACTION';end if;
 if p_action<>'read' then perform laundry_private.require_permission('production_execute');end if;
 who:=laundry_private.laundry_authenticated('version','{}')->'user';actor:=who->>'email';admin:=who->>'role'='admin';
 if p_action<>'read' and who->>'role' not in ('admin','operator') then raise exception 'FORBIDDEN';end if;
 perform 1 from public.laundry_meta where id for update;
 perform laundry_private.wash_batch_tick();
 perform laundry_private.dry_cycle_tick();
 select data into d from public.laundry_production where id for update;
 if p_action='start' then
  select * into b from public.laundry_wash_batches where id=(p->>'batchId')::uuid for update;
  if b.id is null then raise exception 'BATCH_NOT_FOUND';end if;
  if not b.requires_drying then raise exception 'DRYING_NOT_REQUIRED';end if;
  if b.state<>'estimated' then raise exception 'WASH_BATCH_IN_PROGRESS';end if;
  select * into c from public.laundry_dry_cycles where wash_batch_id=b.id for update;
  if c.state='running' then return jsonb_build_object('alreadyStarted',true);end if;
  if c.state='estimated' then raise exception 'DRYING_ALREADY_DONE';end if;
  select value into t from jsonb_array_elements(d->'types') where value->>'id'=p->>'programId' and coalesce(value->>'active','true')='true' and value->>'mode'='machine' and value->>'machineKind'='dryer';
  if t is null then raise exception 'INVALID_DRY_PROGRAM';end if;
  if not exists(select 1 from jsonb_array_elements(d->'stations') s where s->>'id'=t->>'station' and coalesce(s->>'active','true')='true') then raise exception 'STATION_INACTIVE';end if;
  -- Operators start drying only at a station they are enabled for, as in planning assignments.
  if not admin and not exists(select 1 from jsonb_array_elements(coalesce(d->'operators','[]')) o where lower(o->>'email')=lower(actor) and coalesce(o->>'active','true')='true' and coalesce(o->'skills','[]') ? (t->>'station')) then raise exception 'STATION_SKILL_REQUIRED';end if;
  if coalesce((t->>'value')::numeric,0)<=0 then raise exception 'CYCLE_DURATION_REQUIRED';end if;
  select value into m from jsonb_array_elements(d->'machines') where value->>'id'=p->>'machineId' and coalesce(value->>'active','true')='true' and value->>'kind'='dryer';
  if m is null then raise exception 'INVALID_DRY_MACHINE';end if;
  select count(*) into n from public.laundry_wash_items where batch_id=b.id;
  if nullif(m->>'capacity','')::integer is null or (m->>'capacity')::integer<n then raise exception 'MACHINE_CAPACITY_REQUIRED';end if;
  if exists(select 1 from jsonb_array_elements(d->'tickets') x where x->>'machineId'=m->>'id' and x->>'blocking'='true' and x->>'status'<>'closed') then raise exception 'MACHINE_UNAVAILABLE';end if;
  if exists(select 1 from public.laundry_dry_cycles where machine_id=m->>'id' and state in ('running','blocked') and wash_batch_id<>b.id) then raise exception 'MACHINE_BUSY';end if;
  if exists(select 1 from jsonb_array_elements(d->'tasks') x join lateral jsonb_array_elements(d#>'{plan,allocations}') a on a->>'taskId'=x->>'id' where x->>'status' in ('running','paused') and a->>'machineId'=m->>'id') then raise exception 'MACHINE_BUSY';end if;
  if exists(select 1 from public.laundry_wash_items wi join public.laundry_lots ll on ll.id=wi.lot_id cross join lateral jsonb_array_elements(ll.data->'rows') r where wi.batch_id=b.id and r->>'code'=wi.code and (r->>'state'='Uscito' or nullif(r->>'foldedAt','') is not null)) then raise exception 'BATCH_PRODUCTS_ALREADY_PROCESSED';end if;
  if c.id is null then
   insert into public.laundry_dry_cycles(wash_batch_id,program_id,program_name,machine_id,machine_name,duration_minutes,expected_end,started_by,events)
   values(b.id,t->>'id',t->>'name',m->>'id',m->>'name',(t->>'value')::numeric,now()+((t->>'value')::numeric*interval '1 minute'),actor,jsonb_build_array(jsonb_build_object('at',now(),'action','start','actor',actor,'machineId',m->>'id','minutes',t->'value'))) returning * into c;
  else
   update public.laundry_dry_cycles set state='running',program_id=t->>'id',program_name=t->>'name',machine_id=m->>'id',machine_name=m->>'name',duration_minutes=(t->>'value')::numeric,started_at=now(),expected_end=now()+((t->>'value')::numeric*interval '1 minute'),started_by=actor,
   events=events||jsonb_build_array(jsonb_build_object('at',now(),'action','restart','actor',actor,'machineId',m->>'id','minutes',t->'value')) where id=c.id returning * into c;
  end if;
  update public.laundry_lots set data=jsonb_set(data,'{events}',coalesce(data->'events','[]')||jsonb_build_array(jsonb_build_object('time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'action','Asciugatura avviata · '||c.program_name||' · '||c.machine_name,'code','','actor',coalesce(who->>'name',actor),'actorEmail',actor))) where id=b.lot_id;
 elsif p_action in ('interrupt','reset') then
  select * into c from public.laundry_dry_cycles where id=(p->>'cycleId')::uuid for update;
  if c.id is null then raise exception 'BATCH_NOT_FOUND';end if;
  if c.state='estimated' then raise exception 'CYCLE_ALREADY_ELAPSED';end if;
  if p_action='interrupt' then
   if c.state<>'running' then raise exception 'BATCH_NOT_RUNNING';end if;
   update public.laundry_dry_cycles set state='blocked',events=events||jsonb_build_array(jsonb_build_object('at',now(),'action','interrupted','actor',actor)) where id=c.id;
  else
   -- Cancelling a start returns the cart to "Da asciugare"; the audit keeps the cancelled cycle.
   insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor,auth.uid()::text,'dry_cycle_reset_previous',jsonb_build_object('previousCycle',to_jsonb(c)));
   delete from public.laundry_dry_cycles where id=c.id;
  end if;
 end if;
 if p_action<>'read' then
  perform laundry_private.dry_sync_product_phases();
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor,auth.uid()::text,'dry_cycle_'||p_action,jsonb_build_object('batchId',coalesce(b.id,c.wash_batch_id),'cycleId',c.id,'programId',p->>'programId','machineId',p->>'machineId'));
 end if;
 return jsonb_build_object('serverTime',now(),
 'machines',(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(d->'machines') x where x->>'kind'='dryer'),
 'types',(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(d->'types') x where x->>'mode'='machine' and x->>'machineKind'='dryer'),
 'tickets',d->'tickets','stations',d->'stations','admin',admin,
 'myStations',case when admin then (select coalesce(jsonb_agg(s->'id'),'[]') from jsonb_array_elements(d->'stations') s) else coalesce((select o->'skills' from jsonb_array_elements(coalesce(d->'operators','[]')) o where lower(o->>'email')=lower(actor) and coalesce(o->>'active','true')='true' limit 1),'[]') end,
 'carts',(select coalesce(jsonb_agg(jsonb_build_object('batchId',b2.id,'lotId',b2.lot_id,'washProgram',b2.program_name,'washMachine',b2.machine_name,'washEnd',b2.expected_end,
   'quantity',(select count(*) from public.laundry_wash_items i where i.batch_id=b2.id),
   'codes',(select coalesce(jsonb_agg(i.code order by i.code),'[]') from public.laundry_wash_items i where i.batch_id=b2.id),
   'cycle',to_jsonb(c2)) order by b2.expected_end),'[]')
  from public.laundry_wash_batches b2 left join public.laundry_dry_cycles c2 on c2.wash_batch_id=b2.id
  where b2.requires_drying and b2.state='estimated' and (c2.id is null or c2.state<>'estimated' or c2.expected_end>now()-interval '1 day')));
end $$;
revoke all on function laundry_private.dry_cycle_control(text,jsonb) from public,anon,authenticated;
grant execute on function laundry_private.dry_cycle_control(text,jsonb) to authenticated;
create or replace function public.laundry_dry_cycles(p_action text,p_payload jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select laundry_private.dry_cycle_control(p_action,p_payload)$$;
revoke all on function public.laundry_dry_cycles(text,jsonb) from public,anon;
grant execute on function public.laundry_dry_cycles(text,jsonb) to authenticated;

-- A planning task cannot start on a dryer occupied by a real drying cycle.
create or replace function laundry_private.dry_guard_production() returns trigger
language plpgsql security definer set search_path='' as $$
declare t jsonb; a jsonb;
begin
 for t in select value from jsonb_array_elements(new.data->'tasks') where value->>'status'='running' loop
  if exists(select 1 from jsonb_array_elements(old.data->'tasks') x where x->>'id'=t->>'id' and x->>'status'='running') then continue;end if;
  select value into a from jsonb_array_elements(new.data#>'{plan,allocations}') where value->>'taskId'=t->>'id';
  if exists(select 1 from public.laundry_dry_cycles c where c.machine_id=a->>'machineId' and c.state in ('running','blocked')) then raise exception 'MACHINE_BUSY';end if;
 end loop;
 return new;
end $$;
revoke all on function laundry_private.dry_guard_production() from public,anon,authenticated;
create trigger dry_guard_production before update on public.laundry_production for each row execute function laundry_private.dry_guard_production();

-- Show the drying phase as soon as the wash timer elapses, without waiting for the dryer tick.
do $migration$
declare d text;
begin
 d:=pg_get_functiondef('laundry_private.wash_batch_tick()'::regprocedure);
 if position('perform laundry_private.dry_sync_product_phases();' in d)=0 then
  if position(' perform laundry_private.wash_sync_product_phases();' in d)=0 then raise exception 'DRY_PHASE_SOURCE_CHANGED: wash_batch_tick';end if;
  execute replace(d,' perform laundry_private.wash_sync_product_phases();',' perform laundry_private.wash_sync_product_phases();
 perform laundry_private.dry_sync_product_phases();');
 end if;
end $migration$;

-- Production has pg_cron installed; local tests may omit the extension.
do $$begin
 if exists(select 1 from pg_namespace where nspname='cron') then
  perform cron.schedule('laundry-dry-cycle-tick','* * * * *','select laundry_private.dry_cycle_tick()');
 end if;
end $$;
