begin;
-- Guard outgoing registrations on the server, including requests from older clients.
create or replace function laundry_private.validate_lot_flow()
returns trigger language plpgsql set search_path='' as $function$
declare r jsonb; previous jsonb;
begin
 if tg_op='UPDATE' and exists(select 1 from jsonb_array_elements(old.data->'rows') prior where not exists(select 1 from jsonb_array_elements(new.data->'rows') newer where newer->>'code'=prior->>'code')) then
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
end;$function$;
revoke all on function laundry_private.validate_lot_flow() from public,anon,authenticated;
create trigger validate_lot_flow before insert or update on public.laundry_lots for each row execute function laundry_private.validate_lot_flow();
update public.laundry_meta set revision=revision+1 where id;
commit;
