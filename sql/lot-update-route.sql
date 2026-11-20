-- Atomic correction of selected, not-yet-started entry routes.
create or replace function laundry_private.lot_update_route(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 who jsonb; actor text; lid bigint; l jsonb; d jsonb; proc jsonb; t jsonb; m jsonb;
 codes text[]; old_batches uuid[]; bid uuid; cap integer; n integer; code_value text;
 r jsonb; next_rows jsonb := '[]'; ev jsonb; events jsonb := '[]'; new_label boolean;
begin
 who := laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('lots_work');
 actor := who->>'email';
 perform 1 from public.laundry_meta where id for update;
 if (p->>'revision')::bigint is distinct from (select revision from public.laundry_meta where id) then raise exception 'ROUTE_CONFLICT'; end if;
 lid := (p->>'lotId')::bigint;
 select data into l from public.laundry_lots where id=lid for update;
 if l is null or l->>'archived'='true' then raise exception 'INVALID_LOT'; end if;
 if jsonb_typeof(p->'codes') is distinct from 'array' then raise exception 'SELECT_PRODUCTS'; end if;
 select array_agg(distinct value) into codes from jsonb_array_elements_text(p->'codes');
 if coalesce(cardinality(codes),0)=0 then raise exception 'SELECT_PRODUCTS'; end if;
 if exists(select 1 from unnest(codes) c where not exists(select 1 from jsonb_array_elements(l->'rows') x where x->>'code'=c)) then raise exception 'PRODUCT_NOT_IN_LOT'; end if;
 -- Validate the whole selection before changing any row or cart.
 if exists(select 1 from jsonb_array_elements(l->'rows') x where x->>'code'=any(codes) and
   (x->>'state' is distinct from 'Entrato' or x->>'washed'='true' or x->>'completed'='true' or nullif(x->>'foldedAt','') is not null))
 or exists(select 1 from public.laundry_wash_items i join public.laundry_wash_batches b on b.id=i.batch_id
   where i.lot_id=lid and i.code=any(codes) and (b.state not in ('gathering','ready') or b.started_at is not null))
 then raise exception 'ROUTE_ALREADY_STARTED'; end if;
 select data into d from public.laundry_production where id;
 if nullif(p->>'programId','') is not null then
   select value into t from jsonb_array_elements(d->'types') where value->>'id'=p->>'programId' and coalesce(value->>'active','true')='true' and value->>'mode'='machine' and value->>'machineKind' in ('water','decon','dry');
   select value into m from jsonb_array_elements(d->'machines') where value->>'id'=p->>'machineId' and coalesce(value->>'active','true')='true';
   select pr.data into proc from public.laundry_wash_links w join public.laundry_processing pr on pr.id=w.processing_id where w.program_id=p->>'programId' and pr.data->>'active'='true' and pr.data->>'wash'='true';
   if t is null or m is null or proc is null or t->>'machineKind' is distinct from m->>'kind' then raise exception 'INVALID_PROGRAM_LINK'; end if;
   if not exists(select 1 from jsonb_array_elements(d->'stations') s where s->>'id'=t->>'station' and coalesce(s->>'active','true')='true') then raise exception 'STATION_INACTIVE'; end if;
   cap := nullif(m->>'capacity','')::integer;
   if cap is null or cap<1 then raise exception 'MACHINE_CAPACITY_REQUIRED'; end if;
 else
   select data into proc from public.laundry_processing where id=p->>'processingId' and data->>'active'='true' and data->>'wash'='false';
   if proc is null then raise exception 'PROCESSING_REQUIRED'; end if;
 end if;
 new_label := proc->>'name'='Etichettare' and proc->>'wash'='false';
 select array_agg(distinct batch_id) into old_batches from public.laundry_wash_items where lot_id=lid and code=any(codes);
 delete from public.laundry_wash_items where lot_id=lid and code=any(codes);
 -- Empty, unstarted carts have no remaining work. Other lots' items stay intact.
 delete from public.laundry_wash_batches b where b.id=any(old_batches) and not exists(select 1 from public.laundry_wash_items i where i.batch_id=b.id);
 for r in select value from jsonb_array_elements(l->'rows') loop
   if r->>'code'=any(codes) then
     code_value := r->>'code';
     ev := jsonb_build_object('action','Percorso aggiornato · '||(proc->>'name'),'code',code_value,'at',now(),'time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'actor',who->>'name','actorEmail',actor,'previousProcessingId',r->>'processingId','previousProcessingName',r->>'processingName');
     events := events || jsonb_build_array(ev);
     r := (r-'washBatchId'-'washBatchState'-'washProgramId'-'washProgramName'-'requiresFolding') || jsonb_build_object(
       'processingId',proc->>'id','processingName',proc->>'name','washRequired',(proc->>'wash')::boolean,
       'relabel',case when new_label then true when r->>'processingName'='Etichettare' and r->>'washRequired'='false' then false else coalesce((r->>'relabel')::boolean,false) end);
     if t is not null then
       select b.id into bid from public.laundry_wash_batches b where b.lot_id=lid and b.program_id=t->>'id' and b.machine_id=m->>'id' and b.state='gathering' and b.started_at is null and b.capacity=cap
         and (select count(*) from public.laundry_wash_items i where i.batch_id=b.id)<cap order by b.created_at limit 1 for update;
       if bid is null then
         insert into public.laundry_wash_batches(lot_id,program_id,processing_id,machine_id,program_name,machine_name,machine_kind,capacity,created_by)
         values(lid,t->>'id',proc->>'id',m->>'id',t->>'name',m->>'name',m->>'kind',cap,actor) returning id into bid;
       end if;
       insert into public.laundry_wash_items(lot_id,code,batch_id) values(lid,code_value,bid);
       select count(*) into n from public.laundry_wash_items where batch_id=bid;
       if n>=cap then update public.laundry_wash_batches set state='ready' where id=bid; end if;
       r := r || jsonb_build_object('washBatchId',bid,'washBatchState',case when n>=cap then 'ready' else 'gathering' end,'washProgramId',t->>'id','washProgramName',t->>'name','requiresFolding',true);
     end if;
     update public.laundry_products set data=jsonb_set(data,'{history}',coalesce(data->'history','[]')||jsonb_build_array(ev||jsonb_build_object('lotId',lid))) where id=code_value;
   end if;
   next_rows := next_rows || jsonb_build_array(r);
 end loop;
 update public.laundry_lots set data=jsonb_set(jsonb_set(l,'{rows}',next_rows),'{events}',coalesce(l->'events','[]')||events) where id=lid;
 perform laundry_private.wash_sync_product_phases();
 update public.laundry_meta set revision=revision+1 where id;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor,auth.uid()::text,'lot_update_route',p);
 return laundry_private.laundry_authenticated('snapshot','{}') || jsonb_build_object('routeUpdated',cardinality(codes));
end $$;
revoke all on function laundry_private.lot_update_route(jsonb) from public,anon;
grant execute on function laundry_private.lot_update_route(jsonb) to authenticated;

create or replace function public.laundry_wash_batches(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql set search_path='' as $$
select case when p_action='update_route' then laundry_private.lot_update_route(p_payload)
else laundry_private.wash_batch_control(p_action,p_payload) end
$$;
