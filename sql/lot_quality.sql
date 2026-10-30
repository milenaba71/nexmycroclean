-- Additive quality controls. Existing lots opt in; newly created lots require release.
create table public.laundry_lot_quality(
 lot_id bigint primary key references public.laundry_lots(id) on delete cascade,
 required boolean not null default true,
 revision bigint not null default 0,
 enabled_at timestamptz not null default now()
);
create table public.laundry_quality_checks(
 id uuid primary key default gen_random_uuid(),
 lot_id bigint not null references public.laundry_lot_quality(lot_id),
 checked_at timestamptz not null default clock_timestamp(),
 actor_id uuid not null, actor_name text not null, actor_email text not null,
 outcome text not null check(outcome in ('pass','fail')),
 checks jsonb not null, sample_count integer not null check(sample_count>0),
 notes text not null default '', evidence text not null default '',
 scope jsonb not null,
 lot_revision bigint not null,
 unique(lot_id,lot_revision)
);
create index laundry_quality_checks_lot on public.laundry_quality_checks(lot_id,lot_revision desc);
alter table public.laundry_lot_quality enable row level security;
alter table public.laundry_quality_checks enable row level security;
revoke all on public.laundry_lot_quality,public.laundry_quality_checks from public,anon,authenticated;

create function laundry_private.quality_row_ready(r jsonb) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(r->>'state','') in ('Entrato','In lavorazione')
 and r->>'completed'='true'
 and not exists(select 1 from unnest(array['repair','relabel','verify','rewashPending','discard','discardReview']) k where r->>k='true')
 and (coalesce(r->>'washBatchId','')='' or (r->>'completed'='true' and coalesce(r->>'foldedAt','')<>''))
 and (coalesce(r->>'requiresDrying','false')<>'true' or r->>'dryState'='done');
$$;
create function laundry_private.quality_fingerprint(r jsonb) returns text
language sql immutable set search_path='' as $$select md5((r-'state')::text)$$;
revoke all on function laundry_private.quality_row_ready(jsonb),laundry_private.quality_fingerprint(jsonb) from public,anon,authenticated;

create function laundry_private.quality_new_lot() returns trigger
language plpgsql security definer set search_path='' as $$
begin insert into public.laundry_lot_quality(lot_id) values(new.id);return new;end $$;
revoke all on function laundry_private.quality_new_lot() from public,anon,authenticated;
create trigger quality_new_lot after insert on public.laundry_lots for each row execute function laundry_private.quality_new_lot();

create function laundry_private.quality_exit_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare r jsonb; previous jsonb; q public.laundry_quality_checks;
begin
 if not exists(select 1 from public.laundry_lot_quality where lot_id=new.id and required) then return new;end if;
 select * into q from public.laundry_quality_checks where lot_id=new.id order by lot_revision desc limit 1;
 for r in select value from jsonb_array_elements(new.data->'rows') loop
  select value into previous from jsonb_array_elements(old.data->'rows') where value->>'code'=r->>'code';
  if r->>'state'='Uscito' and coalesce(previous->>'state','')<>'Uscito' then
   if q.id is null or q.outcome<>'pass' then raise exception 'QUALITY_RELEASE_REQUIRED';end if;
   if q.scope->>(r->>'code') is distinct from laundry_private.quality_fingerprint(r) then raise exception 'QUALITY_RECHECK_REQUIRED';end if;
  end if;
 end loop;
 return new;
end $$;
revoke all on function laundry_private.quality_exit_guard() from public,anon,authenticated;
create trigger zzz_quality_exit_guard before update of data on public.laundry_lots for each row execute function laundry_private.quality_exit_guard();

create function laundry_private.quality_control(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare context jsonb; actor jsonb; lid bigint; l jsonb; config public.laundry_lot_quality;
 latest public.laundry_quality_checks; scope_value jsonb; sample integer; status_value text;
 checks_value jsonb; notes_value text; evidence_value text; result jsonb; rev bigint;
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
  select coalesce(jsonb_object_agg(r->>'code',laundry_private.quality_fingerprint(r)),'{}') into scope_value from jsonb_array_elements(l->'rows') r where case when status_value='pass' then laundry_private.quality_row_ready(r) else coalesce(r->>'state','') not in ('Uscito','Dismesso') end;
  sample:=(p->>'sample_count')::integer;
  if sample is null or sample<1 or sample>(select count(*) from jsonb_object_keys(scope_value)) then raise exception 'INVALID_SAMPLE_COUNT';end if;
  insert into public.laundry_quality_checks(lot_id,actor_id,actor_name,actor_email,outcome,checks,sample_count,notes,evidence,scope,lot_revision)
   values(lid,auth.uid(),coalesce(actor->>'name',''),actor->>'email',status_value,checks_value,sample,notes_value,evidence_value,scope_value,config.revision+1);
  update public.laundry_lot_quality set revision=revision+1 where lot_id=lid;
  update public.laundry_meta set revision=revision+1 where id;
 end if;
 select * into config from public.laundry_lot_quality where lot_id=lid;
 select * into latest from public.laundry_quality_checks where lot_id=lid order by lot_revision desc limit 1;
 select jsonb_build_object('lot_id',lid,'enabled',coalesce(config.required,false),'revision',coalesce(config.revision,0),'rows',l->'rows',
  'eligible',coalesce((select jsonb_agg(r->>'code') from jsonb_array_elements(l->'rows') r where laundry_private.quality_row_ready(r)),'[]'),
  'released',coalesce((select jsonb_agg(r->>'code') from jsonb_array_elements(l->'rows') r where latest.outcome='pass' and latest.scope->>(r->>'code')=laundry_private.quality_fingerprint(r)),'[]'),
  'checks',coalesce((select jsonb_agg(to_jsonb(c)-'scope' order by c.lot_revision desc) from public.laundry_quality_checks c where lot_id=lid),'[]')) into result;
 if p_action='report' then
  result:=result||jsonb_build_object('lot',l,'generated_at',clock_timestamp(),'generated_by',actor->>'name','data_revision',rev,
   'products',coalesce((select jsonb_agg(g.data) from public.laundry_products g where g.id in (select r->>'code' from jsonb_array_elements(l->'rows') r)),'[]'));
 end if;
 return result;
end $$;
revoke all on function laundry_private.quality_control(text,jsonb) from public,anon,authenticated;
grant execute on function laundry_private.quality_control(text,jsonb) to authenticated;
create function public.laundry_quality(p_action text,p jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select laundry_private.quality_control(p_action,p)$$;
revoke all on function public.laundry_quality(text,jsonb) from public,anon;
grant execute on function public.laundry_quality(text,jsonb) to authenticated;
