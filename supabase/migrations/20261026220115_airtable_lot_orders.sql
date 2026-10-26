begin;
-- The same client/order guard applies to products and laundry lots.
create trigger check_airtable_lot_order before insert or update on public.laundry_lots
for each row execute function laundry_private.check_airtable_product_order();
create function laundry_private.airtable_lot_create(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare identity_result jsonb; result jsonb; o jsonb; l jsonb; order_id text;
begin
 identity_result:=laundry_private.laundry_authenticated('version','{}');
 if coalesce(identity_result->'user'->>'role','') not in ('admin','operator') then raise exception 'FORBIDDEN';end if;
 order_id:=nullif(p_payload->>'airtableOrderId','');
 if order_id is null then raise exception 'INVALID_AIRTABLE_ORDER';end if;
 select data into o from public.laundry_airtable_orders where id=order_id for share;
 if o is null then raise exception 'INVALID_AIRTABLE_ORDER';end if;
 -- Core preserves its existing revision lock, sequence and actor/session checks.
 result:=laundry_private.laundry_authenticated('lot_create',p_payload);
 l:=(result->'lot')||jsonb_build_object('airtableOrderId',order_id,'airtableOrderCode',o->>'code','airtableCustomerOrder',o->>'customerOrder');
 l:=jsonb_set(l,'{events}',coalesce(l->'events','[]')||jsonb_build_array(jsonb_build_object('action','Collegato ordine Airtable '||coalesce(o->>'code',order_id),'code','','time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI'),'actor',identity_result->'user'->>'name','actorEmail',identity_result->'user'->>'email')));
 -- Trigger verifies the order belongs to this client; failure rolls back creation.
 update public.laundry_lots set data=l where id=(l->>'id')::bigint;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(identity_result->'user'->>'email',auth.uid()::text,'airtable_lot_link',jsonb_build_object('lotId',l->'id','orderId',order_id));
 return jsonb_set(result,'{lot}',l);
end;$fn$;
revoke all on function laundry_private.airtable_lot_create(jsonb) from public,anon,authenticated;
grant execute on function laundry_private.airtable_lot_create(jsonb) to authenticated;
create function public.laundry_airtable_lot_create(p_payload jsonb)
returns jsonb language sql security invoker set search_path='' as $fn$select laundry_private.airtable_lot_create(p_payload);$fn$;
revoke all on function public.laundry_airtable_lot_create(jsonb) from public,anon,authenticated;
grant execute on function public.laundry_airtable_lot_create(jsonb) to authenticated;
commit;
