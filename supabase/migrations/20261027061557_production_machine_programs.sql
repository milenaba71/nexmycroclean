begin;
-- Supply missing machine-program categories without inventing cycle or labor durations.
do $fn$
declare d jsonb; work_station text; k text; title text; additions jsonb:='[]';
begin
 select data into d from public.laundry_production where id for update;
 select value->>'id' into work_station from jsonb_array_elements(d->'stations') where value->>'kind'='entry' order by (value->>'active'='true') desc,value->>'id' limit 1;
 if work_station is null then raise exception 'ENTRY_STATION_REQUIRED';end if;
 foreach k in array array['water','decon','dry','dryer'] loop
  if not exists(select 1 from jsonb_array_elements(d->'types') where value->>'mode'='machine' and value->>'machineKind'=k) then
   title:=case k when 'water' then 'Lavaggio ad acqua' when 'decon' then 'Lavaggio e decontaminazione' when 'dry' then 'Lavaggio a secco' else 'Asciugatura in essiccatoio' end;
   additions:=additions||jsonb_build_array(jsonb_build_object('id',gen_random_uuid()::text,'name',title,'station',work_station,'mode','machine','machineKind',k,'value',null,'operatorMinutes',null,'setup',0,'active',true));
  end if;
 end loop;
 if jsonb_array_length(additions)>0 then
  d:=jsonb_set(d,'{types}',(d->'types')||additions);
  if jsonb_typeof(d->'plan')='object' then d:=jsonb_set(d,'{plan,stale}','true');end if;
  update public.laundry_production set data=d,revision=revision+1 where id;
 end if;
end;$fn$;
commit;
