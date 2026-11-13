-- Remove only unprocessed entry rows; preserve product records and audit history.
CREATE OR REPLACE FUNCTION laundry_private.validate_lot_flow()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r jsonb; previous jsonb;
begin
 if exists(select 1 from jsonb_array_elements(new.data->'rows') as duplicate_row(value) group by lower(duplicate_row.value->>'code') having count(*)>1) then raise exception 'DUPLICATE_SCAN';end if;
 if tg_op='UPDATE' and exists(select 1 from jsonb_array_elements(old.data->'rows') prior where not exists(select 1 from jsonb_array_elements(new.data->'rows') newer where newer->>'code'=prior->>'code') and not exists(
   select 1 from public.laundry_audit a where a.action='lot_entry_remove'
   and a.details->>'transaction_id'=txid_current()::text
   and a.details->>'lot_id'=new.id::text
   and a.details->'rows' @> jsonb_build_array(prior))) then
  raise exception 'CANNOT_REMOVE_LOT_PRODUCT';
 end if;
 for r in select value from jsonb_array_elements(new.data->'rows') loop
  previous:=null;
  if tg_op='UPDATE' then select value into previous from jsonb_array_elements(old.data->'rows') where value->>'code'=r->>'code';end if;
  if length(coalesce(r->>'notes',''))>2000 then raise exception 'LOT_NOTE_TOO_LONG';end if;
  if previous is null and not exists(select 1 from public.laundry_products where id=r->>'code' and data->>'client'=new.data->>'client') then raise exception 'LOT_PRODUCT_CLIENT_MISMATCH';end if;
  if r->>'state'='Uscito' and coalesce(previous->>'state','')<>'Uscito' then
   if not (coalesce((r->>'completed')::boolean,false) or coalesce((r->>'washed')::boolean,false)) then raise exception 'WORK_NOT_COMPLETED';end if;
   if coalesce((r->>'repair')::boolean,false) or coalesce((r->>'relabel')::boolean,false) or coalesce((r->>'verify')::boolean,false) or coalesce((r->>'rewashPending')::boolean,false) then raise exception 'OPEN_INTERVENTIONS';end if;
  end if;
 end loop;
 return new;
end;$function$
;
create or replace function laundry_private.remove_entry_products(p jsonb)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare who jsonb; l jsonb; removed jsonb; codes text[]; bids uuid[]; event jsonb; count_removed integer;
begin
 perform set_config('laundry.compact_snapshot','on',true);
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('lots_work');
 if jsonb_typeof(p->'codes') is distinct from 'array' or jsonb_array_length(p->'codes') not between 1 and 1000 then raise exception 'INVALID_CODES';end if;
 select array_agg(distinct value) into codes from jsonb_array_elements_text(p->'codes');
 perform 1 from public.laundry_meta where id for update;
 select data into l from public.laundry_lots where id=(p->>'lot_id')::bigint for update;
 if l is null or coalesce((l->>'archived')::boolean,false) then raise exception 'LOT_NOT_WRITABLE';end if;
 select coalesce(jsonb_agg(r),'[]') into removed from jsonb_array_elements(l->'rows') r where r->>'code'=any(codes);
 count_removed:=jsonb_array_length(removed);
 if count_removed=0 then return laundry_private.laundry_authenticated('snapshot','{}')||'{"removed_count":0}'::jsonb;end if;
 if exists(select 1 from jsonb_array_elements(removed) r where r->>'state' is distinct from 'Entrato'
 or r->>'washed'='true' or r->>'completed'='true' or nullif(r->>'foldedAt','') is not null
 or coalesce((r->>'rewashCycles')::int,0)>0 or jsonb_array_length(coalesce(r->'repairWork','[]'))>0)
 then raise exception 'PRODUCT_ALREADY_PROCESSED';end if;
 select array_agg(distinct wi.batch_id) into bids from public.laundry_wash_items wi where wi.lot_id=(p->>'lot_id')::bigint and wi.code=any(codes);
 if exists(select 1 from public.laundry_wash_batches b where b.id=any(bids) and (b.state not in ('gathering','ready') or b.started_at is not null or b.load_group_id is not null))
 or exists(select 1 from public.laundry_dry_cycles d where d.wash_batch_id=any(bids))
 then raise exception 'WASH_ALREADY_STARTED';end if;
 if exists(select 1 from public.laundry_production pr cross join lateral jsonb_array_elements(pr.data->'tasks') t
 cross join lateral jsonb_array_elements(t->'items') i where i->>'lotId'=p->>'lot_id' and i->>'code'=any(codes) and coalesce(t->>'status','')<>'cancelled')
 then raise exception 'PRODUCT_IN_PRODUCTION_PLAN';end if;
 event:=jsonb_build_object('at',now(),'time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'action','Inserimento annullato · capo rimosso dal lotto','actor',who->>'name','actorEmail',who->>'email','lot',l->>'id');
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'lot_entry_remove',
 jsonb_build_object('transaction_id',txid_current()::text,'lot_id',p->>'lot_id','rows',removed,'reason',left(coalesce(p->>'reason','Errore di inserimento'),1000)));
 delete from public.laundry_wash_items where lot_id=(p->>'lot_id')::bigint and code=any(codes);
 delete from public.laundry_wash_batches b where b.id=any(bids) and not exists(select 1 from public.laundry_wash_items wi where wi.batch_id=b.id);
 update public.laundry_wash_batches b set state=case when (select count(*) from public.laundry_wash_items wi where wi.batch_id=b.id)>=b.capacity then 'ready' else 'gathering' end where b.id=any(bids);
 update public.laundry_products g set data=jsonb_set(g.data,'{history}',coalesce(g.data->'history','[]')||jsonb_build_array(event||jsonb_build_object('code',g.id)))
 where g.id in (select r->>'code' from jsonb_array_elements(removed) r);
 l:=jsonb_set(l,'{rows}',(select coalesce(jsonb_agg(r order by ord),'[]') from jsonb_array_elements(l->'rows') with ordinality v(r,ord) where not(r->>'code'=any(codes))));
 l:=jsonb_set(l,'{events}',coalesce(l->'events','[]')||(select jsonb_agg(event||jsonb_build_object('code',r->>'code')) from jsonb_array_elements(removed) r));
 update public.laundry_lots set data=l where id=(p->>'lot_id')::bigint;
 update public.laundry_meta set revision=revision+1 where id;
 return laundry_private.laundry_authenticated('snapshot','{}')||jsonb_build_object('removed_count',count_removed);
end $function$;
revoke all on function laundry_private.remove_entry_products(jsonb) from public,anon;
grant execute on function laundry_private.remove_entry_products(jsonb) to authenticated;
create or replace function public.laundry_remove_entry_products(p_payload jsonb)
returns jsonb language sql security invoker set search_path='' as $function$
 select laundry_private.remove_entry_products(p_payload);
$function$;
revoke all on function public.laundry_remove_entry_products(jsonb) from public,anon;
grant execute on function public.laundry_remove_entry_products(jsonb) to authenticated;
