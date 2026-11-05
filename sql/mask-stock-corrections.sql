begin;
alter table laundry_private.mask_movements add column corrects_id uuid unique references laundry_private.mask_movements(id), add column correction_reason text not null default '';
CREATE OR REPLACE FUNCTION laundry_private.mask_stock(action text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ident jsonb;line laundry_private.ddt_lines;mov laundry_private.mask_movements;original laundry_private.mask_movements;packed bigint;shipped bigint;qty integer;kind_value text;token uuid;offst int;q text;result jsonb;
begin
 ident:=laundry_private.laundry_authenticated('version','{}');
 if action='correct' then
  perform laundry_private.require_permission('planning_delete');
  token:=(p->>'requestId')::uuid;
  if token is null or coalesce(p->>'quantity','')!~'^[0-9]+$' then raise exception 'INVALID_QUANTITY';end if;
  qty:=(p->>'quantity')::int;
  if qty<=0 or qty>1000000 then raise exception 'INVALID_QUANTITY';end if;
  if length(trim(coalesce(p->>'reason','')))=0 then raise exception 'CANCEL_REASON_REQUIRED';end if;
  if length(coalesce(p->>'notes',''))>2000 or length(p->>'reason')>2000 then raise exception 'NOTES_TOO_LONG';end if;
  perform pg_advisory_xact_lock(hashtextextended(token::text,0));
  select * into mov from laundry_private.mask_movements where id=token;
  if found then
   if mov.corrects_id is distinct from (p->>'movementId')::uuid or mov.quantity<>qty or mov.actor_id<>auth.uid()::text or mov.notes is distinct from coalesce(p->>'notes','') or mov.correction_reason is distinct from p->>'reason' then raise exception 'REQUEST_CONFLICT';end if;
   return to_jsonb(mov);
  end if;
  select * into original from laundry_private.mask_movements where id=(p->>'movementId')::uuid;
  if not found or original.reverses_id is not null or original.quantity<=0 then raise exception 'INVALID_MOVEMENT';end if;
  select * into line from laundry_private.ddt_lines where id=original.line_id for update;
  if exists(select 1 from laundry_private.mask_movements where reverses_id=original.id) then raise exception 'MOVEMENT_ALREADY_REVERSED';end if;
  if line.id is null or not line.present or coalesce(line.data->>'description','')!~*'mascherin' then raise exception 'LINE_NOT_AVAILABLE';end if;
  if exists(select 1 from laundry_private.ddt_receipts where line_id=line.id and status='pending') then raise exception 'RETURN_PENDING';end if;
  select coalesce(sum(quantity)filter(where kind='pack'),0),coalesce(sum(quantity)filter(where kind='ship'),0) into packed,shipped from laundry_private.mask_movements where line_id=line.id;
  if original.kind='pack' then packed:=packed-original.quantity+qty;else shipped:=shipped-original.quantity+qty;end if;
  if packed<0 or shipped<0 or shipped>packed then raise exception 'INSUFFICIENT_STOCK';end if;
  if original.kind='pack' and qty>original.quantity then
   if packed>line.returned then raise exception 'EXCEEDS_RECEIVED';end if;
   if coalesce((select last_sync from laundry_private.ddt_sync where id),'epoch'::timestamptz)<now()-interval '15 minutes' then raise exception 'SYNC_STALE';end if;
  end if;
  insert into laundry_private.mask_movements(id,line_id,kind,quantity,actor_id,actor_name,notes,reverses_id)
   values(gen_random_uuid(),line.id,original.kind,-original.quantity,auth.uid()::text,coalesce(ident->'user'->>'name','Operatore'),p->>'reason',original.id);
  insert into laundry_private.mask_movements(id,line_id,kind,quantity,actor_id,actor_name,notes,corrects_id,correction_reason)
   values(token,line.id,original.kind,qty,auth.uid()::text,coalesce(ident->'user'->>'name','Operatore'),coalesce(p->>'notes',''),original.id,p->>'reason') returning * into mov;
  return to_jsonb(mov);
 end if;
 if action in ('move','cancel') then
  perform laundry_private.require_permission(case when action='cancel' then 'planning_delete' else 'lots_work' end);
  if action='cancel' then
   select * into original from laundry_private.mask_movements where id=(p->>'movementId')::uuid;
   if not found or original.reverses_id is not null then raise exception 'INVALID_MOVEMENT';end if;
   if length(trim(coalesce(p->>'notes','')))=0 then raise exception 'CANCEL_REASON_REQUIRED';end if;
   select * into line from laundry_private.ddt_lines where id=original.line_id for update;
   select * into mov from laundry_private.mask_movements where reverses_id=original.id;
   if found then return to_jsonb(mov);end if;
   token:=gen_random_uuid();qty:=-original.quantity;kind_value:=original.kind;
  else
   token:=(p->>'requestId')::uuid;
   if token is null or coalesce(p->>'quantity','')!~ '^[0-9]+$' then raise exception 'INVALID_QUANTITY';end if;
   qty:=(p->>'quantity')::int;kind_value:=p->>'kind';
   if qty<=0 or qty>1000000 or kind_value not in ('pack','ship') or kind_value is null then raise exception 'INVALID_QUANTITY';end if;
   perform pg_advisory_xact_lock(hashtextextended(token::text,0));
   select * into mov from laundry_private.mask_movements where id=token;
   if found then
    if mov.line_id is distinct from p->>'lineId' or mov.quantity<>qty or mov.kind<>kind_value or mov.actor_id<>auth.uid()::text then raise exception 'REQUEST_CONFLICT';end if;
    return to_jsonb(mov);
   end if;
   select * into line from laundry_private.ddt_lines where id=p->>'lineId' for update;
  end if;
  if line.id is null or not line.present or coalesce(line.data->>'description','') !~* 'mascherin' then raise exception 'LINE_NOT_AVAILABLE';end if;
  if length(coalesce(p->>'notes',''))>2000 then raise exception 'NOTES_TOO_LONG';end if;
  if exists(select 1 from laundry_private.ddt_receipts where line_id=line.id and status='pending') then raise exception 'RETURN_PENDING';end if;
  select coalesce(sum(quantity)filter(where kind='pack'),0),coalesce(sum(quantity)filter(where kind='ship'),0) into packed,shipped from laundry_private.mask_movements where line_id=line.id;
  if kind_value='pack' then packed:=packed+qty;else shipped:=shipped+qty;end if;
  if packed<0 or shipped<0 or shipped>packed then raise exception 'INSUFFICIENT_STOCK';end if;
  if kind_value='pack' and qty>0 and packed>line.returned then raise exception 'EXCEEDS_RECEIVED';end if;
  if kind_value='pack' and qty>0 and (select last_sync from laundry_private.ddt_sync where id)<now()-interval '15 minutes' then raise exception 'SYNC_STALE';end if;
  insert into laundry_private.mask_movements(id,line_id,kind,quantity,actor_id,actor_name,notes,reverses_id)
   values(token,line.id,kind_value,qty,auth.uid()::text,coalesce(ident->'user'->>'name','Operatore'),coalesce(p->>'notes',''),case when action='cancel' then original.id end) returning * into mov;
  return to_jsonb(mov);
 elsif action='history' then
  return jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select m.*,exists(select 1 from laundry_private.mask_movements v where v.reverses_id=m.id) as reversed,exists(select 1 from laundry_private.mask_movements v where v.corrects_id=m.id) as corrected from laundry_private.mask_movements m where line_id=p->>'lineId' order by created_at desc limit 100)x));
 elsif action<>'read' then raise exception 'INVALID_ACTION';end if;
 offst:=greatest(0,coalesce((p->>'offset')::int,0));q:=lower(trim(coalesce(p->>'query','')));
 with amounts as(select line_id,coalesce(sum(quantity)filter(where kind='pack'),0) packed,coalesce(sum(quantity)filter(where kind='ship'),0) shipped from laundry_private.mask_movements group by line_id),
 rows as(select l.*,coalesce(a.packed,0) packed,coalesce(a.shipped,0) shipped,coalesce(a.packed,0)-coalesce(a.shipped,0) stock from laundry_private.ddt_lines l left join amounts a on a.line_id=l.id where l.present and coalesce(l.data->>'description','')~*'mascherin' and (q='' or position(q in lower(l.data::text))>0)),
 paged as(select * from rows order by data->>'date' desc nulls last,id limit 50 offset offst)
 select jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(paged)),'[]') from paged),'total',(select count(*) from rows),'stock',(select coalesce(sum(stock),0) from rows),'packed',(select coalesce(sum(rows.packed),0) from rows),'shipped',(select coalesce(sum(rows.shipped),0) from rows)) into result;
 return result;
end $function$

;
commit;
