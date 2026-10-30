-- Route water washing and drying to the existing water-department skill.
do $$declare d jsonb; sid text; cnt integer;begin
 perform 1 from public.laundry_meta where id for update;
 select data into d from public.laundry_production where id for update;
 select count(*),min(s->>'id') into cnt,sid from jsonb_array_elements(d->'stations') s where lower(btrim(s->>'name'))='reparto acqua' and coalesce(s->>'active','true')='true';
 if cnt<>1 then raise exception 'Expected exactly one active Reparto Acqua station';end if;
 update public.laundry_production set data=jsonb_set(d,'{types}',(select jsonb_agg(case when t->>'mode'='machine' and t->>'machineKind' in ('water','dryer') then jsonb_set(t,'{station}',to_jsonb(sid)) else t end order by ord) from jsonb_array_elements(d->'types') with ordinality x(t,ord))),revision=revision+1 where id;
 update public.laundry_meta set revision=revision+1 where id;
end $$;

create function laundry_private.require_water_batch_skill(bid uuid) returns void
language plpgsql security definer set search_path='' as $$
declare d jsonb;b public.laundry_wash_batches;t jsonb;who jsonb;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('production_execute');
 select * into b from public.laundry_wash_batches where id=bid;
 if b.id is null then raise exception 'BATCH_NOT_FOUND';end if;
 if b.machine_kind<>'water' then return;end if;
 select data into d from public.laundry_production where id;
 select x into t from jsonb_array_elements(d->'types') x where x->>'id'=b.program_id;
 if not exists(select 1 from jsonb_array_elements(d->'stations') s where s->>'id'=t->>'station' and coalesce(s->>'active','true')='true') then raise exception 'STATION_INACTIVE';end if;
 if who->>'role'<>'admin' and not exists(select 1 from jsonb_array_elements(d->'operators') o where lower(o->>'email')=lower(who->>'email') and coalesce(o->>'active','true')='true' and coalesce(o->'skills','[]') ? (t->>'station')) then raise exception 'STATION_SKILL_REQUIRED';end if;
end $$;
revoke all on function laundry_private.require_water_batch_skill(uuid) from public,anon,authenticated;

do $patch$
declare src text;anchor text:='perform 1 from public.laundry_meta where id for update;'; response_anchor text:='return jsonb_build_object(''serverTime'',now(),''machines'',d->''machines''';
begin
 src:=pg_get_functiondef('laundry_private.wash_batch_control(text,jsonb)'::regprocedure);
 if position(anchor in src)=0 or position(response_anchor in src)=0 then raise exception 'WASH_FUNCTION_CHANGED';end if;
 src:=replace(src,anchor,anchor||E'\n if p_action in (''start'',''interrupt'',''reset_batch'') then perform laundry_private.require_water_batch_skill((p->>''batchId'')::uuid);end if;');
 src:=replace(src,response_anchor,'return jsonb_build_object(''admin'',who->>''role''=''admin'',''myStations'',coalesce((select o->''skills'' from jsonb_array_elements(d->''operators'') o where lower(o->>''email'')=lower(actor) and coalesce(o->>''active'',''true'')=''true'' limit 1),''[]''::jsonb),''serverTime'',now(),''machines'',d->''machines''');
 execute src;
end $patch$;
