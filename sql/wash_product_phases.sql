-- Separate machine wash completion from an operator folding scan.
create or replace function laundry_private.wash_sync_product_phases() returns void
language plpgsql security definer set search_path='' as $$
declare l record; next_rows jsonb; changed boolean:=false;
begin
 for l in select ll.* from public.laundry_lots ll where exists(select 1 from public.laundry_wash_items i where i.lot_id=ll.id) for update loop
  select jsonb_agg(case when b.id is null or r->>'state'='Uscito' then r
   when b.state in ('running','blocked') then r||jsonb_build_object('state','In lavaggio','completed',false,'washBatchId',b.id,'washBatchState',b.state,'requiresFolding',true)
   when b.state='estimated' and nullif(r->>'foldedAt','') is null then r||jsonb_build_object('state','In lavorazione','completed',false,'washBatchId',b.id,'washBatchState',b.state,'requiresFolding',true)
   else r||jsonb_build_object('washBatchId',b.id,'washBatchState',b.state,'requiresFolding',true) end order by n)
  into next_rows from jsonb_array_elements(l.data->'rows') with ordinality x(r,n)
  left join public.laundry_wash_items wi on wi.lot_id=l.id and wi.code=r->>'code'
  left join public.laundry_wash_batches b on b.id=wi.batch_id;
  if next_rows is distinct from l.data->'rows' then update public.laundry_lots set data=jsonb_set(data,'{rows}',next_rows) where id=l.id;changed:=true;end if;
 end loop;
 if changed then update public.laundry_meta set revision=revision+1 where id;end if;
end $$;
revoke all on function laundry_private.wash_sync_product_phases() from public,anon,authenticated;

do $migration$
declare d text;
begin
d:=pg_get_functiondef('laundry_private.wash_batch_tick()'::regprocedure);
if position('''washed'',true,''completed'',true,''washBatchId''' in d)=0 then raise exception 'WASH_PHASE_SOURCE_CHANGED: wash_batch_tick';end if;
execute replace(d,'''washed'',true,''completed'',true,''washBatchId''','''washed'',true,''completed'',false,''washBatchState'',''estimated'',''requiresFolding'',true,''washBatchId''');
d:=pg_get_functiondef('laundry_private.wash_batch_tick()'::regprocedure);
if position(' if changed then update public.laundry_meta set revision=revision+1 where id;end if;' in d)=0 then raise exception 'WASH_PHASE_SOURCE_CHANGED: wash_batch_tick';end if;
execute replace(d,' if changed then update public.laundry_meta set revision=revision+1 where id;end if;',' perform laundry_private.wash_sync_product_phases();
 if changed then update public.laundry_meta set revision=revision+1 where id;end if;');
d:=pg_get_functiondef('laundry_private.wash_batch_guard_lot()'::regprocedure);
if position(' and (r->>''state''=''Uscito'' or r->>''washed''=''true'')' in d)=0 then raise exception 'WASH_PHASE_SOURCE_CHANGED: wash_batch_guard_lot';end if;
execute replace(d,' and (r->>''state''=''Uscito'' or r->>''washed''=''true'')',' and (r->>''state''=''Uscito'' or r->>''washed''=''true'' or r->>''completed''=''true'')');
d:=pg_get_functiondef('laundry_private.wash_batch_guard_lot()'::regprocedure);
if position('and coalesce(o->>''washed'',''false'')=coalesce(r->>''washed'',''false'')))' in d)=0 then raise exception 'WASH_PHASE_SOURCE_CHANGED: wash_batch_guard_lot';end if;
execute replace(d,'and coalesce(o->>''washed'',''false'')=coalesce(r->>''washed'',''false'')))','and coalesce(o->>''washed'',''false'')=coalesce(r->>''washed'',''false'') and coalesce(o->>''completed'',''false'')=coalesce(r->>''completed'',''false'')))');
d:=pg_get_functiondef('laundry_private.wash_batch_guard_lot()'::regprocedure);
if position(' return new;' in d)=0 then raise exception 'WASH_PHASE_SOURCE_CHANGED: wash_batch_guard_lot';end if;
execute replace(d,' return new;',' if exists(select 1 from public.laundry_wash_items wi join public.laundry_wash_batches b on b.id=wi.batch_id
 cross join lateral jsonb_array_elements(new.data->''rows'') r
 where wi.lot_id=new.id and r->>''code''=wi.code and r->>''state''=''Uscito''
 and exists(select 1 from jsonb_array_elements(old.data->''rows'') o where o->>''code''=wi.code and o->>''state''<>''Uscito'')
 and (not exists(select 1 from jsonb_array_elements(old.data->''rows'') o where o->>''code''=wi.code and o->>''completed''=''true'' and nullif(o->>''foldedAt'','''') is not null)
 or r->>''repair''=''true'' or r->>''relabel''=''true'' or r->>''verify''=''true'' or r->>''rewashPending''=''true'')) then raise exception ''PRODUCT_NOT_READY_FOR_EXIT'';end if;
 return new;');
d:=pg_get_functiondef('laundry_private.wash_batch_control(text,jsonb)'::regprocedure);
if position('(''acquire'',''switch'',''finish'')' in d)=0 then raise exception 'WASH_PHASE_SOURCE_CHANGED: wash_batch_control';end if;
execute replace(d,'(''acquire'',''switch'',''finish'')','(''acquire'',''switch'',''finish'',''fold'')');
d:=pg_get_functiondef('laundry_private.wash_batch_control(text,jsonb)'::regprocedure);
if position('(''read'',''link'',''acquire'',''start'',''interrupt'',''switch'',''finish'')' in d)=0 then raise exception 'WASH_PHASE_SOURCE_CHANGED: wash_batch_control';end if;
execute replace(d,'(''read'',''link'',''acquire'',''start'',''interrupt'',''switch'',''finish'')','(''read'',''link'',''acquire'',''start'',''interrupt'',''switch'',''finish'',''fold'')');
d:=pg_get_functiondef('laundry_private.wash_batch_control(text,jsonb)'::regprocedure);
if position('cap integer; result jsonb;' in d)=0 then raise exception 'WASH_PHASE_SOURCE_CHANGED: wash_batch_control';end if;
execute replace(d,'cap integer; result jsonb;','cap integer; fold_row jsonb; fold_event jsonb; result jsonb;');
d:=pg_get_functiondef('laundry_private.wash_batch_control(text,jsonb)'::regprocedure);
if position(' if p_action=''link'' then
  select value' in d)=0 then raise exception 'WASH_PHASE_SOURCE_CHANGED: wash_batch_control';end if;
execute replace(d,' if p_action=''link'' then
  select value',' if p_action=''fold'' then
  code_value:=trim(p->>''code'');
  select r into fold_row from public.laundry_lots ll cross join lateral jsonb_array_elements(ll.data->''rows'') r where ll.id=lid and r->>''code''=code_value;
  if fold_row is null then raise exception ''PRODUCT_NOT_IN_LOT'';end if;
  select wb.* into b from public.laundry_wash_items wi join public.laundry_wash_batches wb on wb.id=wi.batch_id where wi.lot_id=lid and wi.code=code_value;
  if b.id is null then raise exception ''WASH_BATCH_NOT_FOUND'';end if;
  if b.state<>''estimated'' or coalesce(fold_row->>''washed'',''false'')<>''true'' then raise exception ''WASH_BATCH_IN_PROGRESS'';end if;
  if fold_row->>''state''=''Uscito'' then raise exception ''PRODUCT_ALREADY_EXITED'';end if;
  if fold_row->>''repair''=''true'' or fold_row->>''relabel''=''true'' or fold_row->>''verify''=''true'' or fold_row->>''rewashPending''=''true'' then raise exception ''PRODUCT_INTERVENTIONS_PENDING'';end if;
  if fold_row->>''completed''=''true'' and nullif(fold_row->>''foldedAt'','''') is not null then return laundry_private.laundry_authenticated(''snapshot'',''{}'')||jsonb_build_object(''alreadyFolded'',true);end if;
  fold_event:=jsonb_build_object(''time'',to_char(now() at time zone ''Europe/Rome'',''DD/MM/YYYY, HH24:MI:SS''),''at'',now(),''action'',''Piegatura completata · Pronto per l’uscita'',''code'',code_value,''actor'',who->>''name'',''actorEmail'',actor);
  update public.laundry_lots ll set data=jsonb_set(jsonb_set(ll.data,''{rows}'',(select jsonb_agg(case when r->>''code''=code_value then r||jsonb_build_object(''state'',''In lavorazione'',''completed'',true,''foldedAt'',now(),''foldedBy'',actor) else r end order by x.n) from jsonb_array_elements(ll.data->''rows'') with ordinality x(r,n))),''{events}'',coalesce(ll.data->''events'',''[]'')||jsonb_build_array(fold_event)) where ll.id=lid;
  update public.laundry_products set data=jsonb_set(data,''{history}'',coalesce(data->''history'',''[]'')||jsonb_build_array(fold_event||jsonb_build_object(''lotId'',lid))) where id=code_value;
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor,auth.uid()::text,''product_fold_scan'',jsonb_build_object(''lotId'',lid,''code'',code_value,''batchId'',b.id));
  return laundry_private.laundry_authenticated(''snapshot'',''{}'');
 end if;
 if p_action=''link'' then
  select value');
d:=pg_get_functiondef('laundry_private.wash_batch_control(text,jsonb)'::regprocedure);
if position(' if p_action not in (''read'',''switch'') then insert' in d)=0 then raise exception 'WASH_PHASE_SOURCE_CHANGED: wash_batch_control';end if;
execute replace(d,' if p_action not in (''read'',''switch'') then insert',' if p_action in (''acquire'',''start'',''interrupt'') then perform laundry_private.wash_sync_product_phases();end if;
 if p_action not in (''read'',''switch'') then insert');
d:=pg_get_functiondef('laundry_private.wash_batch_control(text,jsonb)'::regprocedure);
if position('if p_action=''acquire'' then return result;end if;' in d)=0 then raise exception 'WASH_PHASE_SOURCE_CHANGED: wash_batch_control';end if;
execute replace(d,'if p_action=''acquire'' then return result;end if;','if p_action=''acquire'' then return laundry_private.laundry_authenticated(''snapshot'',''{}'');end if;');
end $migration$;
-- Align non-exited carts with the new phases; already-exited rows stay historical.
insert into public.laundry_audit(actor_email,actor_id,action,details) select 'system','authorized-migration','wash_product_phases_migration',jsonb_build_object('previousLots',coalesce(jsonb_agg(to_jsonb(l)),'[]')) from public.laundry_lots l where exists(select 1 from public.laundry_wash_items i where i.lot_id=l.id);
select laundry_private.wash_sync_product_phases();
