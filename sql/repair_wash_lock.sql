-- Only prevent repair completion while a linked wash cycle is running or interrupted.
create or replace function laundry_private.repair_wash_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare machine_name text;
begin
 select b.machine_name into machine_name
 from public.laundry_wash_items wi join public.laundry_wash_batches b on b.id=wi.batch_id
 cross join lateral jsonb_array_elements(new.data->'rows') r
 join lateral jsonb_array_elements(old.data->'rows') o on o->>'code'=r->>'code'
 where wi.lot_id=new.id and wi.code=r->>'code' and b.state in ('running','blocked')
 and (coalesce(r->'repairWork','[]') is distinct from coalesce(o->'repairWork','[]')
 or (o->>'repair'='true' and coalesce(r->>'repair','false')<>'true')
 or (o->>'relabel'='true' and coalesce(r->>'relabel','false')<>'true')
 or (o->>'verify'='true' and coalesce(r->>'verify','false')<>'true')) limit 1;
 if found then raise exception 'In lavaggio · % · Riparazione bloccata fino al termine del lavaggio.',machine_name;end if;
 return new;
end $$;
revoke all on function laundry_private.repair_wash_guard() from public,anon,authenticated;
create trigger repair_wash_guard before update of data on public.laundry_lots
for each row execute function laundry_private.repair_wash_guard();
