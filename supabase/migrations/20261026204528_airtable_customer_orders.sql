begin;
create table public.laundry_airtable_orders (
 id text primary key check(id ~ '^rec[A-Za-z0-9]{14}$'),
 source_read_at timestamptz not null,
 synced_at timestamptz not null default now(),
 data jsonb not null check(jsonb_typeof(data)='object')
);
alter table public.laundry_airtable_orders enable row level security;
create policy deny_direct_access on public.laundry_airtable_orders for all to anon,authenticated using(false) with check(false);
revoke all on public.laundry_airtable_orders from public,anon,authenticated;
create table laundry_private.airtable_order_sync (
 id boolean primary key default true check(id),
 key_hash text not null,
 metadata jsonb not null default '{}'::jsonb
);
alter table laundry_private.airtable_order_sync enable row level security;
create policy deny_direct_access on laundry_private.airtable_order_sync for all to anon,authenticated using(false) with check(false);
revoke all on laundry_private.airtable_order_sync from public,anon,authenticated;
create table public.laundry_airtable_client_map (
 source_id text primary key check(source_id ~ '^rec[A-Za-z0-9]{14}$'),
 client_id text not null references public.laundry_clients(id),
 updated_at timestamptz not null default now(),
 actor_email text not null
);
alter table public.laundry_airtable_client_map enable row level security;
create policy deny_direct_access on public.laundry_airtable_client_map for all to anon,authenticated using(false) with check(false);
create index laundry_airtable_client_map_local_idx on public.laundry_airtable_client_map(client_id);
revoke all on public.laundry_airtable_client_map from public,anon,authenticated;
create function laundry_private.airtable_orders_ingest(p_key text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare cfg laundry_private.airtable_order_sync; item jsonb; item_id text; seen text[]:='{}'; stamp timestamptz; affected int; n int:=0;
begin
 select * into cfg from laundry_private.airtable_order_sync where id;
 if cfg.key_hash is null or length(coalesce(p_key,''))<>64 or encode(sha256(convert_to(p_key,'UTF8')),'hex')<>cfg.key_hash then raise exception 'UNAUTHORIZED_SYNC';end if;
 if p_payload->>'baseId'<>'appfq4D7MKC9YxUZi' or p_payload->>'tableId'<>'tblGSZRKEPOHtUlQM' or p_payload->>'baseId' is null or p_payload->>'tableId' is null then raise exception 'INVALID_SOURCE';end if;
 if jsonb_typeof(p_payload->'records') is distinct from 'array' or jsonb_array_length(p_payload->'records')>500 then raise exception 'INVALID_RECORDS';end if;
 stamp:=(p_payload->>'readAt')::timestamptz;
 if stamp is null or stamp>now()+interval '5 minutes' then raise exception 'INVALID_READ_TIME';end if;
 for item in select value from jsonb_array_elements(p_payload->'records') loop
  item_id:=item->>'id';
  if item_id is null or item_id!~'^rec[A-Za-z0-9]{14}$' or item_id=any(seen) or jsonb_typeof(item->'data') is distinct from 'object' then raise exception 'INVALID_RECORD';end if;
  seen:=array_append(seen,item_id);
  insert into public.laundry_airtable_orders(id,data,source_read_at) values(item_id,item->'data',stamp)
  on conflict(id) do update set data=excluded.data,source_read_at=excluded.source_read_at,synced_at=now()
  where public.laundry_airtable_orders.source_read_at<excluded.source_read_at;
  get diagnostics affected=row_count;n:=n+affected;
 end loop;
 if n>0 then
  update laundry_private.airtable_order_sync set metadata=metadata||jsonb_build_object('lastSyncAt',now(),'lastReadAt',greatest(stamp,coalesce((metadata->>'lastReadAt')::timestamptz,stamp)),'source','Airtable · Mycroclean Italia · Ordini Clienti') where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values('airtable-sync','airtable:appfq4D7MKC9YxUZi','airtable_orders_sync',jsonb_build_object('upserted',n,'readAt',stamp));
 end if;
 return jsonb_build_object('upserted',n);
end;$fn$;
revoke all on function laundry_private.airtable_orders_ingest(text,jsonb) from public,anon,authenticated;
grant usage on schema laundry_private to service_role;
grant execute on function laundry_private.airtable_orders_ingest(text,jsonb) to service_role;
create function public.laundry_airtable_ingest(p_key text,p_payload jsonb)
returns jsonb language sql security invoker set search_path='' as $fn$select laundry_private.airtable_orders_ingest(p_key,p_payload);$fn$;
revoke all on function public.laundry_airtable_ingest(text,jsonb) from public,anon,authenticated;
grant execute on function public.laundry_airtable_ingest(text,jsonb) to service_role;
create function laundry_private.airtable_orders_read()
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare identity_result jsonb;
begin
 identity_result:=laundry_private.laundry_authenticated('version','{}'::jsonb);
 return jsonb_build_object('orders',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'data',data,'syncedAt',synced_at,'sourceReadAt',source_read_at) order by data->>'orderDate' desc nulls last,id),'[]'::jsonb) from public.laundry_airtable_orders),'clientMap',(select coalesce(jsonb_object_agg(source_id,client_id),'{}'::jsonb) from public.laundry_airtable_client_map),'metadata',(select metadata from laundry_private.airtable_order_sync where id));
end;$fn$;
revoke all on function laundry_private.airtable_orders_read() from public,anon,authenticated;
grant execute on function laundry_private.airtable_orders_read() to authenticated;
create function public.laundry_airtable_orders()
returns jsonb language sql security invoker set search_path='' as $fn$select laundry_private.airtable_orders_read();$fn$;
revoke all on function public.laundry_airtable_orders() from public,anon,authenticated;
grant execute on function public.laundry_airtable_orders() to authenticated;
create function laundry_private.airtable_map_client(p_source_id text,p_client_id text,p_previous text)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare identity_result jsonb; existing text;
begin
 identity_result:=laundry_private.laundry_authenticated('version','{}'::jsonb);
 if (identity_result->'user'->>'role') is distinct from 'admin' then raise exception 'FORBIDDEN';end if;
 if not exists(select 1 from public.laundry_airtable_orders o cross join lateral jsonb_array_elements(o.data->'clients') c where c->>'id'=p_source_id) then raise exception 'INVALID_SOURCE_CLIENT';end if;
 perform pg_advisory_xact_lock(hashtextextended('airtable-map:'||p_source_id,0));
 select client_id into existing from public.laundry_airtable_client_map where source_id=p_source_id;
 if existing is distinct from p_previous then raise exception 'MAPPING_CONFLICT';end if;
 if p_client_id is null then delete from public.laundry_airtable_client_map where source_id=p_source_id;
 else
  if not exists(select 1 from public.laundry_clients where id=p_client_id and data->>'active' is distinct from 'false') then raise exception 'INVALID_CLIENT';end if;
  insert into public.laundry_airtable_client_map(source_id,client_id,actor_email) values(p_source_id,p_client_id,identity_result->'user'->>'email') on conflict(source_id) do update set client_id=excluded.client_id,updated_at=now(),actor_email=excluded.actor_email;
 end if;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(identity_result->'user'->>'email',auth.uid()::text,'airtable_client_map',jsonb_build_object('sourceId',p_source_id,'before',existing,'after',p_client_id));
 return laundry_private.airtable_orders_read();
end;$fn$;
revoke all on function laundry_private.airtable_map_client(text,text,text) from public,anon,authenticated;
grant execute on function laundry_private.airtable_map_client(text,text,text) to authenticated;
create function public.laundry_airtable_map_client(p_source_id text,p_client_id text,p_previous text default null)
returns jsonb language sql security invoker set search_path='' as $fn$select laundry_private.airtable_map_client(p_source_id,p_client_id,p_previous);$fn$;
revoke all on function public.laundry_airtable_map_client(text,text,text) from public,anon,authenticated;
grant execute on function public.laundry_airtable_map_client(text,text,text) to authenticated;
create function laundry_private.check_airtable_product_order()
returns trigger language plpgsql security invoker set search_path='' as $fn$
declare order_id text; o jsonb; source_client jsonb; local_id text; matching text; matching_count int;
begin
 order_id:=nullif(new.data->>'airtableOrderId','');
 if order_id is null then return new;end if;
 if tg_op='UPDATE' and old.data->>'airtableOrderId'=order_id and old.data->>'client'=new.data->>'client' then return new;end if;
 select data into o from public.laundry_airtable_orders where id=order_id;
 if o is null or coalesce(jsonb_array_length(o->'clients'),0)=0 then raise exception 'INVALID_AIRTABLE_ORDER';end if;
 select id into local_id from public.laundry_clients where data->>'name'=new.data->>'client' and data->>'active' is distinct from 'false';
 if local_id is null then raise exception 'INVALID_AIRTABLE_CLIENT';end if;
 for source_client in select value from jsonb_array_elements(o->'clients') loop
  select client_id into matching from public.laundry_airtable_client_map where source_id=source_client->>'id';
  if matching is null then
   select count(*),min(id) into matching_count,matching from public.laundry_clients where lower(btrim(regexp_replace(data->>'name','\s+',' ','g')))=lower(btrim(regexp_replace(source_client->>'name','\s+',' ','g')));
   if matching_count<>1 then raise exception 'AIRTABLE_CLIENT_MAPPING_REQUIRED';end if;
  end if;
  if matching is distinct from local_id then raise exception 'AIRTABLE_ORDER_CLIENT_MISMATCH';end if;
 end loop;
 return new;
end;$fn$;
revoke all on function laundry_private.check_airtable_product_order() from public,anon,authenticated;
create trigger check_airtable_product_order before insert or update on public.laundry_products for each row execute function laundry_private.check_airtable_product_order();
commit;
