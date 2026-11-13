-- Create and acquire one automatically numbered garment atomically.
create or replace function laundry_private.entry_new_product(p jsonb)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare who jsonb; l jsonb; result jsonb; prior jsonb; request_data jsonb;
 lid bigint; token uuid; code text; rev bigint; typ text; dept text;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('lots_work');
 token:=(p->>'request_id')::uuid;
 if token is null then raise exception 'REQUEST_ID_REQUIRED';end if;
 lid:=(p->>'lot_id')::bigint; typ:=p->>'type_id';
 request_data:=jsonb_build_object('lot_id',lid,'type_id',typ,'program_id',p->>'program_id','machine_id',p->>'machine_id','processing_id',p->>'processing_id');
 select revision into rev from public.laundry_meta where id for update;
 select details into prior from public.laundry_audit where action='entry_new_product'
 and actor_id=auth.uid()::text and details->>'request_id'=token::text order by id desc limit 1;
 if prior is not null then
  if prior->'request' is distinct from request_data then raise exception 'REQUEST_MISMATCH';end if;
  return laundry_private.laundry_authenticated('snapshot','{}')||jsonb_build_object('saved_id',prior->>'code','saved_code',prior->>'code','already_saved',true);
 end if;
 select data into l from public.laundry_lots where id=lid;
 if l is null or coalesce((l->>'archived')::boolean,false) or l->>'status' in ('closed','Chiuso') then raise exception 'LOT_NOT_WRITABLE';end if;
 if not exists(select 1 from public.laundry_types where id=typ and active) then raise exception 'TYPE_REQUIRED';end if;
 code:=laundry_private.next_available_barcode();
 if nullif(p->>'program_id','') is not null then
  result:=laundry_private.wash_batch_control('acquire',jsonb_build_object('lotId',lid,'code',code,'programId',p->>'program_id','machineId',p->>'machine_id','revision',rev));
 else
  if not exists(select 1 from public.laundry_processing where id=p->>'processing_id' and data->>'active'='true' and coalesce(data->>'wash','false')='false') then raise exception 'PROCESSING_REQUIRED';end if;
  result:=laundry_private.laundry_authenticated('lot_acquire',jsonb_build_object('lot_id',lid,'code',code,'processing_id',p->>'processing_id','revision',rev));
 end if;
 result:=laundry_private.laundry_authenticated('lot_set_type',jsonb_build_object('lot_id',lid,'type_id',typ,'codes',jsonb_build_array(code),'revision',result->'revision'));
 dept:=coalesce(l->>'departmentName','');
 update public.laundry_products set data=jsonb_set(jsonb_set(data,'{dept}',to_jsonb(dept)),'{raw,REPARTO}',to_jsonb(dept)) where id=code;
 insert into public.laundry_audit(actor_email,actor_id,action,details)
 values(who->>'email',auth.uid()::text,'entry_new_product',jsonb_build_object('request_id',token,'request',request_data,'code',code));
 return laundry_private.laundry_authenticated('snapshot','{}')||jsonb_build_object('saved_id',code,'saved_code',code);
end $function$;
revoke all on function laundry_private.entry_new_product(jsonb) from public,anon;
grant execute on function laundry_private.entry_new_product(jsonb) to authenticated;
create or replace function public.laundry_entry_new_product(p_payload jsonb)
returns jsonb language sql security invoker set search_path='' as $function$
 select laundry_private.entry_new_product(p_payload);
$function$;
revoke all on function public.laundry_entry_new_product(jsonb) from public,anon;
grant execute on function public.laundry_entry_new_product(jsonb) to authenticated;
