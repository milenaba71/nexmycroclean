-- One transaction per sewing action; retries reuse the same request ID.
create table laundry_private.sewing_requests (
 id uuid primary key, actor_id uuid not null, lot_id bigint not null,
 action text not null, payload jsonb not null, created_at timestamptz not null default now()
);
alter table laundry_private.sewing_requests enable row level security;
create policy deny_direct_access on laundry_private.sewing_requests for all to anon,authenticated using(false) with check(false);
revoke all on laundry_private.sewing_requests from public,anon,authenticated;

create function laundry_private.sewing_work(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare who jsonb; rev bigint; base_rev bigint; l jsonb; r jsonb; w jsonb; t jsonb; ev jsonb;
 old_work jsonb; works jsonb; item jsonb; idx int; wi int; q bigint; mins bigint; price bigint;
 lid bigint:=(p->>'lotId')::bigint; request_id uuid:=(p->>'requestId')::uuid;
 prior laundry_private.sewing_requests; code text; kind text; reason text; action_text text;
 codes text[]:='{}'; work_id text; replay boolean:=false; actor uuid:=auth.uid();
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('lots_work');
 if request_id is null or lid is null or p_action is null or p_action not in ('add','edit','delete','complete') then raise exception 'INVALID_SEWING';end if;
 -- Same lock order as existing scans and legacy saves. No global snapshot is read or replaced.
 select revision into rev from public.laundry_meta where id for update; base_rev:=rev;
 select * into prior from laundry_private.sewing_requests where id=request_id;
 if found then
  if prior.actor_id<>actor or prior.lot_id<>lid or prior.action<>p_action or prior.payload<>p then raise exception 'SEWING_REQUEST_CONFLICT';end if;
  replay:=true;
 end if;
 select data into l from public.laundry_lots where id=lid for update;
 if l is null then raise exception 'UNKNOWN_LOT';end if;
 if not replay then
  if coalesce((l->>'archived')::boolean,false) then raise exception 'LOT_ARCHIVED';end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') not between 1 and 200 then raise exception 'INVALID_SEWING';end if;
  if exists(select 1 from jsonb_array_elements(p->'items') x group by x->>'code' having count(*)>1) then raise exception 'INVALID_SEWING';end if;
  for item in select value from jsonb_array_elements(p->'items') loop
   code:=item->>'code'; codes:=array_append(codes,code);
   select value,(ordinality-1)::int into r,idx from jsonb_array_elements(l->'rows') with ordinality where value->>'code'=code;
   if r is null then raise exception 'UNKNOWN_PRODUCT';end if;
   works:=coalesce(r->'repairWork','[]'::jsonb); old_work:=null;w:=null;reason:=null;
   if p_action in ('edit','delete') then
    select value,(ordinality-1)::int into w,wi from jsonb_array_elements(works) with ordinality where value->>'id'=item->>'workId';
    if w is null or w is distinct from item->'expected' then raise exception 'SEWING_WORK_CHANGED';end if;
    old_work:=w;kind:=w->>'kind';work_id:=w->>'id';
   else
    kind:=item->>'kind';work_id:=request_id::text||':'||code;
   end if;
   if kind is null or kind not in ('repair','relabel','verify') then raise exception 'INVALID_SEWING';end if;
   if p_action in ('add','complete') or (p_action='delete' and coalesce((item->>'reopen')::boolean,false)) then
    if r->>'state' in ('Uscito','Dismesso') or coalesce((r->>'lifecycleClosed')::boolean,false) or coalesce(r->>'replacedBy','')<>'' then raise exception 'SEWING_PRODUCT_CLOSED';end if;
    if r->>'state'='In lavaggio' or r->>'washBatchState' in ('running','blocked') or exists(select 1 from public.laundry_wash_batches b where b.id::text=r->>'washBatchId' and b.state in ('running','blocked')) then raise exception 'SEWING_IN_WASH';end if;
   end if;
   if p_action in ('add','edit') then
    q:=(item->>'quantity')::bigint;mins:=(item->>'minutesHundredths')::bigint;
    if q is null or q not between 1 and 100000 or mins is null or mins not between 0 and 100000000 or length(coalesce(item->>'notes',''))>500 then raise exception 'INVALID_SEWING';end if;
    if p_action='add' then
     select data into t from public.laundry_processing where id=item->>'typeId';
     if t is null or t->>'category' is distinct from 'repairType' or not coalesce((t->>'repairActive')::boolean,false) then raise exception 'INVALID_REPAIR_TYPE';end if;
     if coalesce((item->>'requirePending')::boolean,false) and not coalesce((r->>kind)::boolean,false) then raise exception 'SEWING_NOT_PENDING';end if;
     if not coalesce((item->>'allowRepeat')::boolean,false) and exists(select 1 from jsonb_array_elements(works) x where x->>'repairTypeId'=item->>'typeId' and x->>'kind'=kind) then raise exception 'SEWING_DUPLICATE';end if;
     price:=case when t->>'unit'='piece' then coalesce((t->>'priceMills')::bigint,0) else 0 end;
     w:=jsonb_build_object('id',work_id,'kind',kind,'repairTypeId',item->>'typeId','name',t->>'name','unit',t->>'unit','priceMills',price,'completedAt',now(),'completedBy',who->>'name','completedByEmail',who->>'email');
    else price:=coalesce((w->>'priceMills')::bigint,0);end if;
    if price<0 or price*q>9007199254740991 then raise exception 'INVALID_SEWING';end if;
    w:=w||jsonb_build_object('quantity',q,'minutesHundredths',mins,'costMills',case when w->>'unit'='piece' then price*q else 0 end,'notes',btrim(coalesce(item->>'notes','')));
    if p_action='add' then
     works:=works||jsonb_build_array(w);
     r:=jsonb_set(r,array[kind],to_jsonb(not coalesce((item->>'complete')::boolean,true)));
     action_text:='Intervento eseguito · '||(w->>'name')||' · '||q||' · '||(mins::numeric/100)||' min';
    else works:=jsonb_set(works,array[wi::text],w);action_text:='Correzione intervento · '||(w->>'name');end if;
   elsif p_action='delete' then
    reason:=btrim(coalesce(item->>'reason',''));
    if length(reason) not between 3 and 500 then raise exception 'SEWING_REASON_REQUIRED';end if;
    works:=works-wi;
    if coalesce((item->>'reopen')::boolean,false) then r:=jsonb_set(r,array[kind],'true');end if;
    action_text:='Annullamento intervento · '||(w->>'name')||' · '||reason||case when coalesce((item->>'reopen')::boolean,false) then ' · Attività da rifare' else ' · Solo registrazione errata' end;
   else
    if not coalesce((r->>kind)::boolean,false) then raise exception 'SEWING_NOT_PENDING';end if;
    r:=jsonb_set(r,array[kind],'false');
    action_text:='Intervento completato · '||case kind when 'repair' then 'Riparazione' when 'relabel' then 'Etichettatura' else 'Verifica' end||' · Senza consuntivo';
   end if;
   r:=jsonb_set(r,'{repairWork}',works);
   l:=jsonb_set(l,array['rows',idx::text],r);
   ev:=jsonb_build_object('action',action_text,'code',code,'time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'at',now(),'actor',who->>'name','actorEmail',who->>'email','workId',work_id,'requestId',request_id);
   l:=jsonb_set(l,'{events}',coalesce(l->'events','[]')||jsonb_build_array(ev));
   update public.laundry_products set data=jsonb_set(data,'{history}',coalesce(data->'history','[]')||jsonb_build_array(ev||jsonb_build_object('lotId',lid))) where id=code;
   insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',actor::text,'sewing_'||p_action,jsonb_build_object('lotId',lid,'code',code,'requestId',request_id,'before',old_work,'after',case when p_action='delete' then null else w end,'reopen',item->'reopen','reason',reason));
  end loop;
  update public.laundry_lots set data=l where id=lid returning data into l;
  update public.laundry_meta set revision=revision+1 where id returning revision into rev;
  insert into laundry_private.sewing_requests(id,actor_id,lot_id,action,payload) values(request_id,actor,lid,p_action,p);
 else select array_agg(x->>'code') into codes from jsonb_array_elements(p->'items') x;end if;
 return jsonb_build_object('lot',l,'products',coalesce((select jsonb_agg(data) from public.laundry_products where id=any(codes)),'[]'),'baseRevision',case when replay then null else base_rev end,'revision',rev,'replayed',replay);
end $$;
create function public.laundry_sewing_work(p_action text,p_payload jsonb default '{}') returns jsonb
language sql set search_path='' set statement_timeout='15s' as $$select laundry_private.sewing_work(p_action,p_payload);$$;
revoke all on function laundry_private.sewing_work(text,jsonb),public.laundry_sewing_work(text,jsonb) from public,anon;
grant execute on function laundry_private.sewing_work(text,jsonb),public.laundry_sewing_work(text,jsonb) to authenticated;
