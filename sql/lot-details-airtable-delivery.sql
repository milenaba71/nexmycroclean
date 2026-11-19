begin;
-- Keep order references and delivery date authoritative on every lot write.
create or replace function laundry_private.lot_order_delivery()
returns trigger language plpgsql security invoker set search_path='' as $$
declare o jsonb; d text;
begin
 if tg_op='UPDATE' and new.data->>'client' is distinct from old.data->>'client' then
  if not exists(select 1 from public.laundry_clients where data->>'name'=new.data->>'client' and data->>'active' is distinct from 'false') then raise exception 'INVALID_CLIENT';end if;
  if exists(select 1 from jsonb_array_elements(new.data->'rows') r join public.laundry_products p on p.id=r->>'code' where p.data->>'client' is distinct from new.data->>'client') then raise exception 'LOT_PRODUCT_CLIENT_MISMATCH';end if;
  if nullif(old.data->>'calendarId','') is not null then raise exception 'LINKED_CALENDAR_CLIENT';end if;
 end if;
 if new.data->>'archived'='true' then return new;end if;
 if tg_op='UPDATE' and jsonb_array_length(coalesce(old.data->'rows','[]'))>0 and not exists(select 1 from jsonb_array_elements(old.data->'rows') r where r->>'state' not in ('Uscito','Dismesso')) and new.data->>'airtableOrderId' is not distinct from old.data->>'airtableOrderId' then return new;end if;
 select data into o from public.laundry_airtable_orders where id=new.data->>'airtableOrderId';
 if o is not null then
  d:=nullif(o->>'due','');
  if d is not null then d:=(d::date)::text;end if;
  new.data:=new.data||jsonb_build_object('due',d,'dueSource','airtable','airtableOrderCode',o->>'code','airtableCustomerOrder',o->>'customerOrder');
 end if;
 return new;
end;$$;
revoke all on function laundry_private.lot_order_delivery() from public,anon,authenticated;
create trigger lot_order_delivery before insert or update of data on public.laundry_lots for each row execute function laundry_private.lot_order_delivery();

create or replace function laundry_private.sync_order_lot_delivery()
returns trigger language plpgsql security invoker set search_path='' as $$
declare n int;
begin
 if tg_op='UPDATE' and new.data->'due' is not distinct from old.data->'due' and new.data->'code' is not distinct from old.data->'code' and new.data->'customerOrder' is not distinct from old.data->'customerOrder' then return new;end if;
 perform 1 from public.laundry_meta where id for update;
 update public.laundry_lots set data=data||jsonb_build_object('events',coalesce(data->'events','[]')||jsonb_build_array(jsonb_build_object('action','Consegna e riferimenti aggiornati da ordine Airtable','at',now(),'actor','Sincronizzazione Airtable','code','')))
 where data->>'airtableOrderId'=new.id and data->>'archived' is distinct from 'true'
 and (jsonb_array_length(coalesce(data->'rows','[]'))=0 or exists(select 1 from jsonb_array_elements(data->'rows') r where r->>'state' not in ('Uscito','Dismesso')));
 get diagnostics n=row_count;
 if n>0 then update public.laundry_meta set revision=revision+1 where id;end if;
 return new;
end;$$;
revoke all on function laundry_private.sync_order_lot_delivery() from public,anon,authenticated;
create trigger sync_order_lot_delivery after insert or update of data on public.laundry_airtable_orders for each row execute function laundry_private.sync_order_lot_delivery();
-- Align existing open linked lots, preserving completed history.
do $$ declare n int;begin
 perform 1 from public.laundry_meta where id for update;
 update public.laundry_lots l set data=l.data||jsonb_build_object('events',coalesce(l.data->'events','[]')||jsonb_build_array(jsonb_build_object('action','Consegna acquisita da ordine Airtable','at',now(),'actor','Aggiornamento gestionale','code','')))
 from public.laundry_airtable_orders o where o.id=l.data->>'airtableOrderId' and l.data->>'archived' is distinct from 'true'
 and (jsonb_array_length(coalesce(l.data->'rows','[]'))=0 or exists(select 1 from jsonb_array_elements(l.data->'rows') r where r->>'state' not in ('Uscito','Dismesso')));
 get diagnostics n=row_count;if n>0 then update public.laundry_meta set revision=revision+1 where id;end if;
end $$;
commit;
