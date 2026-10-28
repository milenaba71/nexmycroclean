-- Maintain automatic processing records for machine programs; preserve historical/manual links.
create or replace function laundry_private.sync_wash_programs(d jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare t jsonb; pid text; before_data jsonb; next_data jsonb; changed boolean:=false;
begin
 for t in select value from jsonb_array_elements(coalesce(d->'types','[]')) where value->>'mode'='machine' and value->>'machineKind' in ('water','decon','dry') loop
  select processing_id into pid from public.laundry_wash_links where program_id=t->>'id';
  if pid is null then
   pid:='WP-'||gen_random_uuid()::text;
   insert into public.laundry_processing(id,data) values(pid,jsonb_build_object('id',pid,'name',t->>'name','description','Programma macchina','wash',true,'active',coalesce((t->>'active')::boolean,true),'autoProgramId',t->>'id'));
   insert into public.laundry_wash_links(program_id,processing_id) values(t->>'id',pid);changed:=true;
  else
   select data into before_data from public.laundry_processing where id=pid;
   if before_data->>'autoProgramId'=t->>'id' then
    next_data:=before_data||jsonb_build_object('name',t->>'name','active',coalesce((t->>'active')::boolean,true));
    if next_data is distinct from before_data then update public.laundry_processing set data=next_data where id=pid;changed:=true;end if;
   end if;
  end if;
 end loop;
 if changed then update public.laundry_meta set revision=revision+1 where id;end if;
end $$;
revoke all on function laundry_private.sync_wash_programs(jsonb) from public,anon,authenticated;
create or replace function laundry_private.sync_wash_programs_trigger() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.data->'types' is distinct from old.data->'types' then perform laundry_private.sync_wash_programs(new.data);end if;
 return new;
end $$;
revoke all on function laundry_private.sync_wash_programs_trigger() from public,anon,authenticated;
create trigger sync_wash_programs after update of data on public.laundry_production for each row execute function laundry_private.sync_wash_programs_trigger();
-- Complete missing links once; leave existing links and all lot rows untouched.
do $$begin perform 1 from public.laundry_meta where id for update;perform laundry_private.sync_wash_programs(data) from public.laundry_production where id;end$$;
