begin;
alter table laundry_private.ddt_receipts add column reverses_id uuid references laundry_private.ddt_receipts(id), add column dispatched_at timestamptz, add column cancelled_by text, add column cancelled_name text, add column cancel_reason text;
alter table laundry_private.ddt_receipts drop constraint ddt_receipts_quantity_check;
alter table laundry_private.ddt_receipts add constraint ddt_receipts_quantity_check check(quantity>0 and reverses_id is null or quantity<0 and reverses_id is not null);
alter table laundry_private.ddt_receipts drop constraint ddt_receipts_status_check;
alter table laundry_private.ddt_receipts add constraint ddt_receipts_status_check check(status in ('pending','applied','conflict','cancelled'));
create index ddt_receipts_reverses on laundry_private.ddt_receipts(reverses_id);
create unique index ddt_one_reversal on laundry_private.ddt_receipts(reverses_id) where status in ('pending','applied');
-- Existing pending requests may already have reached Airtable; preserve them for reconciliation.
update laundry_private.ddt_receipts set dispatched_at=now() where status='pending';
CREATE OR REPLACE FUNCTION laundry_private.ddt_app(action text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare identity_value jsonb; r laundry_private.ddt_lines; job laundry_private.ddt_receipts; qty numeric; token uuid; result jsonb; lim int:=50; offst int; q text; supplier text; selected_ddt text; state_filter text;
begin
 identity_value:=laundry_private.laundry_authenticated('version','{}');
 if action='cancel' then
  perform laundry_private.require_permission('planning_delete');
  if length(trim(coalesce(p->>'reason','')))=0 or length(p->>'reason')>2000 then raise exception 'CANCEL_REASON_REQUIRED';end if;
  -- Serialize with worker dispatch before locking receipts or lines.
  perform 1 from laundry_private.ddt_sync where id for update;
  select * into job from laundry_private.ddt_receipts where id=(p->>'receiptId')::uuid for update;
  if not found or job.quantity<=0 then raise exception 'INVALID_RECEIPT';end if;
  if job.status='cancelled' then return to_jsonb(job);end if;
  select to_jsonb(j) into result from laundry_private.ddt_receipts j where j.reverses_id=job.id and j.status in ('pending','applied') limit 1;
  if result is not null then return result;end if;
  if job.status='pending' then
   if job.dispatched_at is not null then raise exception 'SYNC_IN_PROGRESS';end if;
   update laundry_private.ddt_receipts set status='cancelled',finished_at=now(),cancelled_by=auth.uid()::text,cancelled_name=coalesce(identity_value->'user'->>'name','Operatore'),cancel_reason=p->>'reason' where id=job.id returning * into job;
   return to_jsonb(job);
  end if;
  if job.status<>'applied' then raise exception 'INVALID_RECEIPT';end if;
  select * into r from laundry_private.ddt_lines where id=job.line_id for update;
  if not found or not r.present then raise exception 'LINE_NOT_AVAILABLE';end if;
  if (select last_sync from laundry_private.ddt_sync where id)<now()-interval '15 minutes' then raise exception 'SYNC_STALE';end if;
  if exists(select 1 from laundry_private.ddt_receipts where line_id=r.id and status='pending') then raise exception 'RETURN_PENDING';end if;
  if r.returned-job.quantity<(select coalesce(sum(quantity),0) from laundry_private.mask_movements where line_id=r.id and kind='pack') then raise exception 'PACKAGED_STOCK_EXISTS';end if;
  if r.returned<job.quantity then raise exception 'CANCEL_EXCEEDS_RETURNED';end if;
  insert into laundry_private.ddt_receipts(id,line_id,quantity,before_qty,after_qty,actor_id,actor_name,notes,reverses_id)
  values(gen_random_uuid(),r.id,-job.quantity,r.returned,r.returned-job.quantity,auth.uid()::text,coalesce(identity_value->'user'->>'name','Operatore'),p->>'reason',job.id) returning * into job;
  return to_jsonb(job);
 elsif action='receive' then
  perform laundry_private.require_permission('lots_work');
  token:=(p->>'requestId')::uuid;qty:=(p->>'quantity')::numeric;
  if token is null or qty is null or qty<=0 or qty>1000000 or qty::text in ('NaN','Infinity') or length(coalesce(p->>'notes',''))>2000 then raise exception 'INVALID_QUANTITY';end if;
  perform pg_advisory_xact_lock(hashtextextended(token::text,0));
  select * into job from laundry_private.ddt_receipts where id=token;
  if found then
   if job.line_id is distinct from p->>'lineId' or job.quantity<>qty or job.actor_id<>auth.uid()::text then raise exception 'REQUEST_CONFLICT';end if;
   return to_jsonb(job);
  end if;
  select * into r from laundry_private.ddt_lines where id=p->>'lineId' for update;
  if not found or not r.present then raise exception 'LINE_NOT_AVAILABLE';end if;
  if (select last_sync from laundry_private.ddt_sync where id) is null or (select last_sync from laundry_private.ddt_sync where id)<now()-interval '15 minutes' then raise exception 'SYNC_STALE';end if;
  if r.version is distinct from (p->>'version')::bigint then raise exception 'LINE_CHANGED';end if;
  if exists(select 1 from laundry_private.ddt_receipts where line_id=r.id and status='pending') then raise exception 'RETURN_PENDING';end if;
  if qty>r.sent-r.returned then raise exception 'EXCEEDS_REMAINING';end if;
  insert into laundry_private.ddt_receipts(id,line_id,quantity,before_qty,after_qty,actor_id,actor_name,notes)
  values(token,r.id,qty,r.returned,r.returned+qty,auth.uid()::text,coalesce(identity_value->'user'->>'name',identity_value->'user'->>'email','Operatore'),coalesce(p->>'notes','')) returning * into job;
  return to_jsonb(job);
 elsif action='history' then
  return jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select j.*, (select v.status from laundry_private.ddt_receipts v where v.reverses_id=j.id and v.status in ('pending','applied') limit 1) as reversal_status from laundry_private.ddt_receipts j where j.line_id=p->>'lineId' order by created_at desc limit 100)x));
 elsif action<>'read' then raise exception 'INVALID_ACTION';end if;
 offst:=greatest(0,coalesce((p->>'offset')::int,0));q:=lower(trim(coalesce(p->>'query','')));supplier:=coalesce(p->>'supplier','');selected_ddt:=coalesce(p->>'ddt','');state_filter:=coalesce(p->>'state','open');
 with filtered as(select l.*,exists(select 1 from laundry_private.ddt_receipts j where j.line_id=l.id and j.status='pending') as pending from laundry_private.ddt_lines l where l.present and (supplier='' or l.data->>'supplierId'=supplier) and (selected_ddt='' or l.data->>'ddtId'=selected_ddt) and (q='' or position(q in lower(l.data::text))>0) and (state_filter='all' or (state_filter='open' and l.sent>l.returned) or (state_filter='closed' and l.sent<=l.returned))),
 paged as(select * from filtered order by data->>'date' desc nulls last,data->>'number',id limit lim offset offst)
 select jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(paged)),'[]') from paged),'total',(select count(*) from filtered)) into result;
 return result||jsonb_build_object('lastSync',(select last_sync from laundry_private.ddt_sync where id),
 'suppliers',(select coalesce(jsonb_agg(x order by x.name),'[]') from(select distinct data->>'supplierId' id,data->>'supplierName' name from laundry_private.ddt_lines where present and coalesce(data->>'supplierId','')<>'')x),
 'documents',(select coalesce(jsonb_agg(x order by x.number),'[]') from(select distinct data->>'ddtId' id,data->>'number' number from laundry_private.ddt_lines where present and (supplier='' or data->>'supplierId'=supplier) and (state_filter='all' or(state_filter='open' and sent>returned)or(state_filter='closed' and sent<=returned)))x));
end $function$;

CREATE OR REPLACE FUNCTION laundry_private.ddt_worker(key_value text, action text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg laundry_private.ddt_sync; token uuid; item jsonb; job laundry_private.ddt_receipts; seen text[]:='{}'; stamp timestamptz:=clock_timestamp();
begin
 if length(coalesce(key_value,''))<>64 or not exists(select 1 from laundry_private.airtable_order_sync where id and key_hash=encode(sha256(convert_to(key_value,'UTF8')),'hex')) then raise exception 'UNAUTHORIZED_SYNC';end if;
 select * into cfg from laundry_private.ddt_sync where id for update;
 if action='begin' then
  if cfg.lease_until>now() then return jsonb_build_object('busy',true);end if;
  token:=gen_random_uuid();update laundry_private.ddt_sync set lease=token,lease_until=now()+interval '4 minutes' where id;
  update laundry_private.ddt_receipts set dispatched_at=coalesce(dispatched_at,now()) where id in (select id from laundry_private.ddt_receipts where status='pending' order by created_at limit 25);
  return jsonb_build_object('lease',token,'jobs',(select coalesce(jsonb_agg(to_jsonb(j)),'[]') from(select * from laundry_private.ddt_receipts where status='pending' and dispatched_at is not null order by created_at limit 25)j));
 end if;
 if cfg.lease is null or p->>'lease' is null or cfg.lease_until is null or cfg.lease is distinct from (p->>'lease')::uuid or cfg.lease_until<now() then raise exception 'LEASE_EXPIRED';end if;
 if action='ack' then
  select * into job from laundry_private.ddt_receipts where id=(p->>'id')::uuid for update;
  if not found then raise exception 'INVALID_RECEIPT';end if;
  if job.status<>'pending' then return jsonb_build_object('status',job.status);end if;
  if p->>'status' not in ('applied','conflict') or p->>'status' is null then raise exception 'INVALID_STATUS';end if;
  update laundry_private.ddt_receipts set status=p->>'status',finished_at=now(),error=left(p->>'error',500) where id=job.id;
  if p->>'status'='applied' then update laundry_private.ddt_lines set returned=job.after_qty,version=version+1 where id=job.line_id;end if;
  return jsonb_build_object('ok',true);
 elsif action='finish' then
  if jsonb_typeof(p->'records') is distinct from 'array' or jsonb_array_length(p->'records')>5000 then raise exception 'INVALID_RECORDS';end if;
  for item in select value from jsonb_array_elements(p->'records') loop
   if item->>'id' is null or item->>'id' !~ '^rec[A-Za-z0-9]{14}$' or item->>'id'=any(seen) or jsonb_typeof(item->'data') is distinct from 'object' or (item->>'sent') is null or (item->>'returned') is null or (item->>'sent')::numeric<0 or (item->>'returned')::numeric<0 or (item->>'sent')::numeric::text in ('NaN','Infinity') or (item->>'returned')::numeric::text in ('NaN','Infinity') then raise exception 'INVALID_RECORD';end if;
   seen:=array_append(seen,item->>'id');
   insert into laundry_private.ddt_lines(id,data,sent,returned,synced_at) values(item->>'id',item->'data',(item->>'sent')::numeric,(item->>'returned')::numeric,stamp)
   on conflict(id) do update set data=excluded.data,sent=excluded.sent,returned=excluded.returned,present=true,synced_at=stamp,
   version=laundry_private.ddt_lines.version+case when (laundry_private.ddt_lines.data,laundry_private.ddt_lines.sent,laundry_private.ddt_lines.returned,laundry_private.ddt_lines.present) is distinct from(excluded.data,excluded.sent,excluded.returned,true) then 1 else 0 end;
  end loop;
  update laundry_private.ddt_lines set present=false,version=version+1 where present and not(id=any(seen));
  update laundry_private.ddt_sync set lease=null,lease_until=null,last_sync=stamp where id;
  return jsonb_build_object('synced',cardinality(seen));
 end if;
 raise exception 'INVALID_ACTION';
end $function$;


commit;
