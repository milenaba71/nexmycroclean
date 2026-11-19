-- At most three distinct sampled garments; append-only history preserves every correction.
alter table public.laundry_lot_quality add column samples jsonb not null default '[]' check(jsonb_typeof(samples)='array' and jsonb_array_length(samples)<=3), add column expanded boolean not null default false;
alter table public.laundry_quality_checks add column sample_code text, add column sample_outcome text check(sample_outcome in ('pass','fail'));

-- Completion and exit bookkeeping must not invalidate a lot's sampling result.
-- Product identity, processing choice and rewash history still invalidate it.
create or replace function laundry_private.quality_sample_fingerprint(r jsonb) returns text
language sql stable set search_path='' as $$
 select md5(jsonb_build_object('code',r->'code','processingId',r->'processingId','washRequired',r->'washRequired','rewashCycles',coalesce(r->'rewashCycles','0'),
 'product',(select jsonb_build_object('barcode',p.data->'barcode','client',p.data->'client','name',p.data->'name','dept',p.data->'dept','type',p.data->'type','size',p.data->'size','color',p.data->'color') from public.laundry_products p where p.id=r->>'code'))::text)
$$;
revoke all on function laundry_private.quality_sample_fingerprint(jsonb) from public,anon,authenticated;

create or replace function laundry_private.quality_released(lid bigint,r jsonb) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare latest public.laundry_quality_checks;
begin
 if not coalesce(laundry_private.quality_row_ready(r),false) then return false;end if;
 select * into latest from public.laundry_quality_checks where lot_id=lid order by lot_revision desc limit 1;
 if latest.id is null or latest.outcome<>'pass' then return false;end if;
 if latest.sample_code is not null then
  return coalesce(latest.scope->>(r->>'code')=laundry_private.quality_sample_fingerprint(r),false);
 end if;
 -- Legacy conforming checks retain their valid scopes until the next failed check.
 return exists(select 1 from public.laundry_quality_checks c where c.lot_id=lid and c.outcome='pass'
 and c.lot_revision>coalesce((select max(f.lot_revision) from public.laundry_quality_checks f where f.lot_id=lid and f.outcome='fail'),0)
 and c.scope->>(r->>'code')=laundry_private.quality_fingerprint(r));
end $$;
revoke all on function laundry_private.quality_released(bigint,jsonb) from public,anon,authenticated;

create or replace function laundry_private.quality_exit_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare r jsonb; previous jsonb;
begin
 if not exists(select 1 from public.laundry_lot_quality where lot_id=new.id and required) then return new;end if;
 for r in select value from jsonb_array_elements(new.data->'rows') loop
  select value into previous from jsonb_array_elements(old.data->'rows') where value->>'code'=r->>'code';
  if r->>'state'='Uscito' and coalesce(previous->>'state','')<>'Uscito' then
   if not laundry_private.quality_released(new.id,r||jsonb_build_object('state',previous->>'state')) then raise exception 'QUALITY_RELEASE_REQUIRED';end if;
  end if;
 end loop;
 return new;
end $$;

create or replace function laundry_private.quality_control(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare context jsonb; actor jsonb; lid bigint; l jsonb; config public.laundry_lot_quality;
 latest public.laundry_quality_checks; scope_value jsonb; sample integer; status_value text;
 checks_value jsonb; notes_value text; evidence_value text; result jsonb; rev bigint; code text; slot integer; samples_value jsonb; expanded_value boolean; target integer;
begin
 context:=laundry_private.laundry_authenticated('version','{}');actor:=context->'user';
 if auth.uid() is null then raise exception 'UNAUTHORIZED';end if;
 if p_action not in ('read','enable','record','report') then raise exception 'INVALID_ACTION';end if;
 if p_action in ('enable','record') then perform laundry_private.require_permission('lots_work');end if;
 lid:=(p->>'lot_id')::bigint;
 -- Same lock order as normal lot writes, preventing a release racing an exit.
 select revision into rev from public.laundry_meta where id for update;
 select data into l from public.laundry_lots where id=lid for update;
 if not found then raise exception 'LOT_NOT_FOUND';end if;
 select * into config from public.laundry_lot_quality where lot_id=lid;
 if p_action='enable' then
  insert into public.laundry_lot_quality(lot_id) values(lid) on conflict do nothing;
  update public.laundry_meta set revision=revision+1 where id;
 end if;
 if p_action='record' then
  if config.lot_id is null then raise exception 'QUALITY_NOT_ENABLED';end if;
  if (p->>'revision')::bigint is distinct from config.revision or p->'rows' is distinct from l->'rows' then raise exception 'REVISION_CONFLICT';end if;
  status_value:=p->>'outcome';checks_value:=p->'checks';notes_value:=btrim(coalesce(p->>'notes',''));evidence_value:=btrim(coalesce(p->>'evidence',''));
  if status_value is null or status_value not in ('pass','fail') or jsonb_typeof(checks_value) is distinct from 'object' then raise exception 'INVALID_QUALITY_CHECK';end if;
  if exists(select 1 from unnest(array['clean','dry','integrity','identity','packing']) k where coalesce(checks_value->>k,'') not in ('ok','ko','na')) then raise exception 'INCOMPLETE_CHECKLIST';end if;
  if status_value='pass' and (exists(select 1 from jsonb_each_text(checks_value) c where c.value='ko') or checks_value->>'clean'<>'ok' or checks_value->>'integrity'<>'ok' or checks_value->>'identity'<>'ok') then raise exception 'QUALITY_CHECKS_FAILED';end if;
  if status_value='fail' and length(notes_value)<3 then raise exception 'QUALITY_REASON_REQUIRED';end if;
  if length(notes_value)>2000 or length(evidence_value)>1000 then raise exception 'QUALITY_TEXT_TOO_LONG';end if;
  code:=p->>'sample_code';
  if not exists(select 1 from jsonb_array_elements(l->'rows') r where r->>'code'=code and laundry_private.quality_row_ready(r)) then raise exception 'QUALITY_SAMPLE_NOT_READY';end if;
  samples_value:=config.samples; expanded_value:=config.expanded;
  select ordinality::integer into slot from jsonb_array_elements(samples_value) with ordinality s where s.value->>'code'=code;
  if slot is null then
   if jsonb_array_length(samples_value)>=(case when expanded_value then 3 else 1 end) then raise exception 'QUALITY_SAMPLE_LIMIT';end if;
   slot:=jsonb_array_length(samples_value)+1;
  end if;
  if slot=1 and status_value='fail' then expanded_value:=true;end if;
  samples_value:=jsonb_set(samples_value,array[(slot-1)::text],jsonb_build_object('code',code,'outcome',status_value,'checks',checks_value,'notes',notes_value,'evidence',evidence_value,'checked_at',clock_timestamp(),'actor_name',actor->>'name'),true);
  select least(3,count(*))::integer into target from jsonb_array_elements(l->'rows') r where r->>'state'<>'Dismesso';
  if not expanded_value then target:=1;end if;
  -- A failed sample is never silently converted to conformity by the extra samples.
  status_value:=case when jsonb_array_length(samples_value)>=target and not exists(select 1 from jsonb_array_elements(samples_value) s where s->>'outcome'<>'pass') then 'pass' else 'fail' end;
  select coalesce(jsonb_object_agg(r->>'code',laundry_private.quality_sample_fingerprint(r)),'{}') into scope_value from jsonb_array_elements(l->'rows') r where r->>'state' not in ('Uscito','Dismesso');
  insert into public.laundry_quality_checks(lot_id,actor_id,actor_name,actor_email,outcome,checks,sample_count,notes,evidence,scope,lot_revision,sample_code,sample_outcome)
   values(lid,auth.uid(),coalesce(actor->>'name',''),actor->>'email',status_value,checks_value,1,notes_value,evidence_value,scope_value,config.revision+1,code,p->>'outcome');
  update public.laundry_lot_quality set samples=samples_value,expanded=expanded_value where lot_id=lid;
  update public.laundry_lot_quality set revision=revision+1 where lot_id=lid;
  update public.laundry_meta set revision=revision+1 where id;
 end if;
 select * into config from public.laundry_lot_quality where lot_id=lid;
 select * into latest from public.laundry_quality_checks where lot_id=lid order by lot_revision desc limit 1;
 select jsonb_build_object('lot_id',lid,'enabled',coalesce(config.required,false),'revision',coalesce(config.revision,0),'rows',l->'rows','samples',coalesce(config.samples,'[]'),'expanded',coalesce(config.expanded,false),'sample_target',case when config.expanded then least(3,(select count(*) from jsonb_array_elements(l->'rows') r where r->>'state'<>'Dismesso')) else 1 end,
  'eligible',coalesce((select jsonb_agg(r->>'code') from jsonb_array_elements(l->'rows') r where laundry_private.quality_row_ready(r)),'[]'),
  'released',coalesce((select jsonb_agg(r->>'code') from jsonb_array_elements(l->'rows') r where laundry_private.quality_released(lid,r)),'[]'),
  'checks',coalesce((select jsonb_agg(to_jsonb(c)-'scope' order by c.lot_revision desc) from public.laundry_quality_checks c where lot_id=lid),'[]')) into result;
 if p_action='report' then
  result:=result||jsonb_build_object('lot',l,'generated_at',clock_timestamp(),'generated_by',actor->>'name','data_revision',rev,
   'products',coalesce((select jsonb_agg(g.data) from public.laundry_products g where g.id in (select r->>'code' from jsonb_array_elements(l->'rows') r)),'[]'));
 end if;
 return result;
end $$;
