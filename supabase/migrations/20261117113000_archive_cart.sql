alter table public.laundry_wash_batches add column archived_at timestamptz;

create function public.laundry_archive_cart(batch uuid, phase text, pieces integer) returns void
language plpgsql security definer set search_path='' as $$
declare b public.laundry_wash_batches; who jsonb; n integer;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('production_execute');
 perform 1 from public.laundry_meta where id for update;
 select * into strict b from public.laundry_wash_batches where id=batch for update;
 perform laundry_private.require_water_batch_skill(batch);
 if b.archived_at is not null then return;end if;
 select count(*) into n from public.laundry_wash_items where batch_id=batch;
 if n is distinct from pieces or not coalesce(
   (phase='wash' and b.state in ('ready','gathering') and b.started_at is null and b.load_group_id is null)
   or (phase='dry' and b.state='estimated' and b.requires_drying and not exists(select 1 from public.laundry_dry_cycles where wash_batch_id=batch)),false)
 then raise exception 'Carrello cambiato o ciclo avviato. Aggiorna il reparto.';end if;
 update public.laundry_wash_batches set archived_at=now(),events=events||jsonb_build_array(jsonb_build_object('action','cart_archived','at',now(),'actor',who->>'email')) where id=batch;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'cart_archived',jsonb_build_object('lotId',b.lot_id,'batchId',batch,'phase',phase,'pieces',n));
 update public.laundry_meta set revision=revision+1 where id;
end $$;
revoke all on function public.laundry_archive_cart(uuid,text,integer) from public,anon;
grant execute on function public.laundry_archive_cart(uuid,text,integer) to authenticated;

-- Preserve each deployed function's existing station checks and routing logic.
do $$
declare spec record; original text;
begin
 for spec in select * from (values
 ('laundry_private.wash_batch_control_single(text,jsonb)', 'from public.laundry_wash_batches x where x.state', 'from (select * from public.laundry_wash_batches where archived_at is null) x where x.state'),
 ('laundry_private.wash_batch_control_single(text,jsonb)', 'and state=''gathering'' and load_group_id', 'and archived_at is null and state=''gathering'' and load_group_id'),
 ('laundry_private.wash_batch_control_single(text,jsonb)', 'where id=(p->>''batchId'')::uuid for update', 'where archived_at is null and id=(p->>''batchId'')::uuid for update'),
 ('laundry_private.dry_cycle_control(text,jsonb)', 'where b2.requires_drying and', 'where b2.archived_at is null and b2.requires_drying and'),
 ('laundry_private.dry_cycle_control(text,jsonb)', 'where id=(p->>''batchId'')::uuid for update', 'where archived_at is null and id=(p->>''batchId'')::uuid for update')
 ) a(fn,needle,repl) loop
 original:=pg_get_functiondef(spec.fn::regprocedure);
 if strpos(original,spec.needle)=0 then raise exception 'Unexpected cart function %',spec.fn;end if;
 execute replace(original,spec.needle,spec.repl);
 end loop;
end $$;
