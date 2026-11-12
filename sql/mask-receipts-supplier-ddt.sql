alter table laundry_private.mask_movements add column if not exists receipt_data jsonb not null default '{}'::jsonb;
CREATE OR REPLACE FUNCTION laundry_private.mask_stock(action text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ident jsonb;ln laundry_private.ddt_lines;mov laundry_private.mask_movements;original laundry_private.mask_movements;
 packed bigint;shipped bigint;global_stock bigint;delta integer;qty integer;kind_value text;line_value text;token uuid;offst int;q text;result jsonb;ship_history boolean;receipt jsonb:='{}'::jsonb;expected_qty integer;
begin
 ident:=laundry_private.laundry_authenticated('version','{}');
 if action in ('move','cancel','correct') then
  perform laundry_private.require_permission(case when action='move' then 'lots_work' else 'planning_delete' end);
  -- Serialize all stock changes: different DDTs share one shipping inventory.
  perform pg_advisory_xact_lock(hashtextextended('mycroclean-mask-global-stock',0));
  if length(coalesce(p->>'notes',''))>2000 or length(coalesce(p->>'reason',''))>2000 then raise exception 'NOTES_TOO_LONG';end if;
  if action in ('move','correct') then
   token:=(p->>'requestId')::uuid;
   if token is null or coalesce(p->>'quantity','')!~'^[0-9]+$' then raise exception 'INVALID_QUANTITY';end if;
   qty:=(p->>'quantity')::integer;
   if qty<=0 or qty>1000000 then raise exception 'INVALID_QUANTITY';end if;
   if action='move' and p->>'kind'='pack' and p ? 'supplierDdt' then
    if length(trim(coalesce(p->>'supplierDdt','')))=0 or length(p->>'supplierDdt')>120 then raise exception 'SUPPLIER_DDT_REQUIRED';end if;
    if coalesce(p->>'expectedQuantity','')!~'^[0-9]+$' then raise exception 'INVALID_EXPECTED_QUANTITY';end if;
    expected_qty:=(p->>'expectedQuantity')::integer;
    if expected_qty<0 or expected_qty>1000000 then raise exception 'INVALID_EXPECTED_QUANTITY';end if;
    receipt:=jsonb_build_object('supplierDdt',trim(p->>'supplierDdt'),'expectedQuantity',expected_qty);
   end if;
   select * into mov from laundry_private.mask_movements where id=token;
   if found then
    if mov.quantity<>qty or mov.actor_id<>auth.uid()::text or mov.notes is distinct from coalesce(p->>'notes','') then raise exception 'REQUEST_CONFLICT';end if;
    if action='correct' then
     if mov.corrects_id is distinct from (p->>'movementId')::uuid or mov.correction_reason is distinct from p->>'reason' then raise exception 'REQUEST_CONFLICT';end if;
    elsif mov.corrects_id is not null or mov.reverses_id is not null or mov.kind is distinct from p->>'kind' or mov.line_id is distinct from nullif(p->>'lineId','') then raise exception 'REQUEST_CONFLICT';end if;
    if action='move' and (mov.receipt_data->>'supplierDdt' is distinct from receipt->>'supplierDdt' or mov.receipt_data->'expectedQuantity' is distinct from receipt->'expectedQuantity') then raise exception 'REQUEST_CONFLICT';end if;
    return to_jsonb(mov);
   end if;
  end if;
  if action in ('cancel','correct') then
   if length(trim(coalesce(case when action='cancel' then p->>'notes' else p->>'reason' end,'')))=0 then raise exception 'CANCEL_REASON_REQUIRED';end if;
   select * into original from laundry_private.mask_movements where id=(p->>'movementId')::uuid;
   if not found or original.reverses_id is not null or original.quantity<=0 then raise exception 'INVALID_MOVEMENT';end if;
   select * into mov from laundry_private.mask_movements where reverses_id=original.id;
   if found then
    if action='cancel' and not exists(select 1 from laundry_private.mask_movements where corrects_id=original.id) then return to_jsonb(mov);end if;
    raise exception 'MOVEMENT_ALREADY_REVERSED';
   end if;
   line_value:=original.line_id;kind_value:=original.kind;receipt:=original.receipt_data;
   if action='cancel' then token:=gen_random_uuid();qty:=-original.quantity;delta:=qty;
   else delta:=qty-original.quantity;end if;
  else
   line_value:=nullif(p->>'lineId','');kind_value:=p->>'kind';delta:=qty;
   if kind_value is null or kind_value not in ('pack','ship') then raise exception 'INVALID_QUANTITY';end if;
   if kind_value='ship' and line_value is not null then raise exception 'GLOBAL_SHIPMENT_REQUIRED';end if;
  end if;
  if line_value is null then
   if kind_value<>'ship' then raise exception 'LINE_NOT_AVAILABLE';end if;
   if abs(qty::bigint) not between 1 and 1000000 then raise exception 'INVALID_QUANTITY';end if;
  else
   select * into ln from laundry_private.ddt_lines where id=line_value for update;
   if ln.id is null then raise exception 'LINE_NOT_AVAILABLE';end if;
   -- Undo and reductions remain possible even if a DDT is no longer mirrored.
   if kind_value='pack' and delta>0 then
    if not ln.present or coalesce(ln.data->>'description','')!~*'mascherin' then raise exception 'LINE_NOT_AVAILABLE';end if;
    if exists(select 1 from laundry_private.ddt_receipts where line_id=ln.id and status='pending') then raise exception 'RETURN_PENDING';end if;
    if coalesce((select last_sync from laundry_private.ddt_sync where id),'epoch'::timestamptz)<now()-interval '15 minutes' then raise exception 'SYNC_STALE';end if;
   end if;
   select coalesce(sum(quantity)filter(where kind='pack'),0),coalesce(sum(quantity)filter(where kind='ship'),0) into packed,shipped from laundry_private.mask_movements where line_id=line_value;
   if kind_value='pack' then packed:=packed+delta;else shipped:=shipped+delta;end if;
   if packed<0 or shipped<0 or shipped>packed then raise exception 'INSUFFICIENT_STOCK';end if;
   if kind_value='pack' and delta>0 and packed>ln.returned and receipt='{}'::jsonb then raise exception 'EXCEEDS_RECEIVED';end if;
  end if;
  if kind_value='pack' and action='move' and receipt<>'{}'::jsonb then
   receipt:=receipt||jsonb_build_object('ddtNumber',ln.data->>'number','supplierName',ln.data->>'supplierName','sentAtRegistration',ln.sent,'returnedAtRegistration',ln.returned,'packedBefore',packed-delta);
  end if;
  select coalesce(sum(case when kind='pack' then quantity else -quantity end),0) into global_stock from laundry_private.mask_movements;
  global_stock:=global_stock+case when kind_value='pack' then delta else -delta end;
  if global_stock<0 then raise exception 'INSUFFICIENT_GLOBAL_STOCK';end if;
  if action='correct' then
   insert into laundry_private.mask_movements(id,line_id,kind,quantity,actor_id,actor_name,notes,reverses_id,receipt_data)
    values(gen_random_uuid(),line_value,kind_value,-original.quantity,auth.uid()::text,coalesce(ident->'user'->>'name','Operatore'),p->>'reason',original.id,original.receipt_data);
  end if;
  insert into laundry_private.mask_movements(id,line_id,kind,quantity,actor_id,actor_name,notes,reverses_id,corrects_id,correction_reason,receipt_data)
   values(token,line_value,kind_value,qty,auth.uid()::text,coalesce(ident->'user'->>'name','Operatore'),coalesce(p->>'notes',''),case when action='cancel' then original.id end,case when action='correct' then original.id end,case when action='correct' then p->>'reason' else '' end,receipt) returning * into mov;
  return to_jsonb(mov);
 elsif action='history' then
  offst:=greatest(0,coalesce((p->>'offset')::int,0));ship_history:=coalesce(p->>'scope','')='shipments';
  with matching as(select m.*,l.data as ddt_data,exists(select 1 from laundry_private.mask_movements v where v.reverses_id=m.id) as reversed,exists(select 1 from laundry_private.mask_movements v where v.corrects_id=m.id) as corrected from laundry_private.mask_movements m left join laundry_private.ddt_lines l on l.id=m.line_id where (ship_history and m.kind='ship') or (not ship_history and m.line_id=p->>'lineId')),
  paged as(select * from matching order by created_at desc,id desc limit 50 offset offst)
  select jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(paged)),'[]') from paged),'total',(select count(*) from matching)) into result;
  return result;
 elsif action<>'read' then raise exception 'INVALID_ACTION';end if;
 offst:=greatest(0,coalesce((p->>'offset')::int,0));q:=lower(trim(coalesce(p->>'query','')));
 with amounts as(select line_id,coalesce(sum(quantity)filter(where kind='pack'),0) packed from laundry_private.mask_movements group by line_id),
 rows as(select l.*,coalesce(a.packed,0) packed from laundry_private.ddt_lines l left join amounts a on a.line_id=l.id where l.present and coalesce(l.data->>'description','')~*'mascherin' and (q='' or position(q in lower(l.data::text))>0)),
 paged as(select * from rows order by data->>'date' desc nulls last,id limit 50 offset offst),
 totals as(select coalesce(sum(quantity)filter(where kind='pack'),0) packed,coalesce(sum(quantity)filter(where kind='ship'),0) shipped from laundry_private.mask_movements)
 select jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(paged)),'[]') from paged),'total',(select count(*) from rows),'stock',(select totals.packed-totals.shipped from totals),'packed',(select totals.packed from totals),'shipped',(select totals.shipped from totals),'filteredPacked',(select coalesce(sum(rows.packed),0) from rows)) into result;
 return result;
end $function$
;
