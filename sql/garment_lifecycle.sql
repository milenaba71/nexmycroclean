-- Garments keep their existing IDs. Physical tags have independent, audited assignments.
-- Prices and depreciation bands intentionally have no defaults.
create table laundry_private.asset_policies(id uuid primary key default gen_random_uuid(),name text not null,base text not null check(base in ('months','washes')),bands jsonb not null,created_at timestamptz not null default now(),created_by text not null);
create table laundry_private.assets(product_id text primary key references public.laundry_products(id) on delete restrict,state text not null check(state in ('stock','in_service','retired','reconditioning','bought_out')),price_cents bigint check(price_cents>=0),service_date date,wash_baseline integer not null default 0 check(wash_baseline>=0),policy jsonb,retired_at timestamptz,reason text,replaced_by text references public.laundry_products(id),replaces text references public.laundry_products(id),events jsonb not null default '[]');
create table laundry_private.tags(code text primary key,display_code text not null,attachment text not null default 'unknown' check(attachment in ('unknown','heatsealed_sewn','other')),state text not null check(state in ('in_use','check','free','destroyed')),verified_at timestamptz,verified_by text);
create table laundry_private.tag_assignments(id uuid primary key default gen_random_uuid(),tag_code text not null references laundry_private.tags(code),product_id text not null references public.laundry_products(id) on delete restrict,assigned_at timestamptz,released_at timestamptz,actor text not null,source text not null default 'operation');
create unique index tag_one_current_garment on laundry_private.tag_assignments(tag_code) where released_at is null;
create unique index garment_one_current_tag on laundry_private.tag_assignments(product_id) where released_at is null;
create table laundry_private.asset_charges(id uuid primary key default gen_random_uuid(),product_id text not null references public.laundry_products(id),reason text not null,state text not null check(state in ('incomplete','pending','approved','rejected')),amount_cents bigint check(amount_cents>=0),calculation jsonb not null,created_at timestamptz not null default now(),decided_at timestamptz,decided_by text,decision_note text,unique(product_id,reason));
create table laundry_private.asset_requests(id uuid primary key,response jsonb not null,actor text not null,created_at timestamptz not null default now());
alter table laundry_private.asset_policies enable row level security;
alter table laundry_private.assets enable row level security;
alter table laundry_private.tags enable row level security;
alter table laundry_private.tag_assignments enable row level security;
alter table laundry_private.asset_charges enable row level security;
alter table laundry_private.asset_requests enable row level security;
revoke all on laundry_private.asset_policies,laundry_private.assets,laundry_private.tags,laundry_private.tag_assignments,laundry_private.asset_charges,laundry_private.asset_requests from public,anon,authenticated;
-- Unknown attachment and unknown original assignment date are explicit; never invent them.
insert into laundry_private.tags(code,display_code,state) select lower(coalesce(nullif(data->>'barcode',''),id)),coalesce(nullif(data->>'barcode',''),id),'in_use' from public.laundry_products;
insert into laundry_private.tag_assignments(tag_code,product_id,actor,source) select lower(coalesce(nullif(data->>'barcode',''),id)),id,'system:migration','legacy_date_unknown' from public.laundry_products;
-- Legacy aliases are historical, not additional active assignments. Their physical release date is unknown.
insert into laundry_private.tags(code,display_code,state)
 select distinct on(lower(alias)) lower(alias),alias,'check' from public.laundry_products g cross join lateral jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]')) alias
 where not exists(select 1 from laundry_private.tags t where t.code=lower(alias)) order by lower(alias),alias;
insert into laundry_private.tag_assignments(tag_code,product_id,released_at,actor,source)
 select distinct lower(alias),g.id,now(),'system:migration','legacy_release_date_unknown' from public.laundry_products g cross join lateral jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]')) alias
 where not exists(select 1 from laundry_private.tag_assignments a where a.tag_code=lower(alias));


create function laundry_private.tag_conflict(pid text,code_value text) returns boolean language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from laundry_private.tags where code=lower(code_value)) then not exists(select 1 from laundry_private.tag_assignments where tag_code=lower(code_value) and product_id=pid and released_at is null)
 else exists(select 1 from public.laundry_products g where g.id is distinct from pid and (lower(g.id)=lower(code_value) or lower(coalesce(nullif(g.data->>'barcode',''),g.id))=lower(code_value) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]')) a where lower(a)=lower(code_value)))) end
$$;
create or replace function laundry_private.guard_product_barcode() returns trigger language plpgsql security definer set search_path='' as $$
declare code_value text; a laundry_private.assets; expected_tag text;
begin
 perform 1 from public.laundry_meta where id for update;
 if new.data->>'id' is distinct from new.id then raise exception 'PRODUCT_ID_IMMUTABLE';end if;
 if jsonb_typeof(coalesce(new.data->'barcodeAliases','[]'))<>'array' then raise exception 'INVALID_BARCODE';end if;
 select * into a from laundry_private.assets where product_id=new.id;
 if a.product_id is not null then
  if new.data->>'lifecycleState' is distinct from a.state or new.data->>'replacedBy' is distinct from a.replaced_by or new.data->>'replaces' is distinct from a.replaces then raise exception 'USE_ASSET_WORKFLOW';end if;
  if a.state in ('retired','bought_out') and old.data->>'lifecycleState' in ('retired','bought_out') and coalesce(nullif(new.data->>'barcode',''),new.id) is distinct from coalesce(nullif(old.data->>'barcode',''),old.id) and not starts_with(coalesce(new.data->>'barcode',''),'__untagged__:') then raise exception 'RETIRED_ASSET_IMMUTABLE';end if;
  if a.state in ('retired','bought_out') and (new.data->'rentalContract' is distinct from old.data->'rentalContract' or new.data->>'client' is distinct from old.data->>'client' or new.data->>'wash' is distinct from old.data->>'wash') then raise exception 'RETIRED_ASSET_IMMUTABLE';end if;
 end if;
 if tg_op='UPDATE' and coalesce(new.data->'barcodeAliases','[]') @> coalesce(old.data->'barcodeAliases','[]') is not true then raise exception 'BARCODE_HISTORY_IMMUTABLE';end if;
 code_value:=coalesce(nullif(new.data->>'barcode',''),new.id);
 if starts_with(code_value,'__untagged__:') or starts_with(code_value,'__retired__:') then
  if exists(select 1 from laundry_private.tag_assignments where product_id=new.id and released_at is null) then raise exception 'TAG_STILL_ASSIGNED';end if;
  if a.product_id is not null and starts_with(code_value,'__retired__:') and a.state not in ('retired','bought_out') then raise exception 'USE_ASSET_WORKFLOW';end if;
 else
  if length(code_value) not between 1 and 200 or code_value~'[[:cntrl:]]' then raise exception 'INVALID_BARCODE';end if;
  if laundry_private.tag_conflict(new.id,code_value) then raise exception 'BARCODE_ALREADY_EXISTS';end if;
 end if;
 if tg_op='UPDATE' and code_value is distinct from coalesce(nullif(old.data->>'barcode',''),old.id) then
  -- Ordinary barcode edits stay available only for legacy products. Managed tags use the registry.
  if a.product_id is not null and exists(select 1 from laundry_private.tag_assignments where product_id=new.id and released_at is null and tag_code<>lower(code_value)) then raise exception 'USE_TAG_REGISTRY';end if;
  new.data:=jsonb_set(new.data,'{barcodeAliases}',(select coalesce(jsonb_agg(distinct x),'[]') from jsonb_array_elements(coalesce(new.data->'barcodeAliases','[]')||jsonb_build_array(coalesce(nullif(old.data->>'barcode',''),old.id))) x));
 end if;
 return new;
end $$;
create function laundry_private.tag_sync_legacy() returns trigger language plpgsql security definer set search_path='' as $$
declare code_value text:=coalesce(nullif(new.data->>'barcode',''),new.id); old_tag text;
begin
 if starts_with(code_value,'__untagged__:') or starts_with(code_value,'__retired__:') then return new;end if;
 if exists(select 1 from laundry_private.tag_assignments where product_id=new.id and tag_code=lower(code_value) and released_at is null) then return new;end if;
 select tag_code into old_tag from laundry_private.tag_assignments where product_id=new.id and released_at is null;
 update laundry_private.tag_assignments set released_at=now() where product_id=new.id and released_at is null;
 update laundry_private.tags set state='check',verified_at=null,verified_by=null where code=old_tag;
 insert into laundry_private.tags(code,display_code,state) values(lower(code_value),code_value,'in_use');
 insert into laundry_private.tag_assignments(tag_code,product_id,assigned_at,actor) values(lower(code_value),new.id,now(),coalesce(auth.uid()::text,'system'));
 return new;
end $$;
create trigger tag_sync_legacy after insert or update on public.laundry_products for each row execute function laundry_private.tag_sync_legacy();
create function laundry_private.tag_lookup(code_value text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if starts_with(code_value,'__untagged__:') or starts_with(code_value,'__retired__:') then raise exception 'TAG_NOT_IN_USE';end if;
 if exists(select 1 from laundry_private.tags where code=lower(code_value)) then
  select g.data into result from laundry_private.tag_assignments a join public.laundry_products g on g.id=a.product_id where a.tag_code=lower(code_value) and a.released_at is null;
  if result is null then raise exception 'TAG_NOT_IN_USE';end if;
 else
  select g.data into result from public.laundry_products g where g.id=code_value;
  if result is null then select g.data into result from public.laundry_products g where lower(coalesce(nullif(g.data->>'barcode',''),g.id))=lower(code_value) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]')) a where lower(a)=lower(code_value)) order by g.id limit 1;end if;
 end if;
 if result->>'lifecycleState' in ('retired','bought_out','reconditioning') then raise exception 'ASSET_NOT_IN_SERVICE';end if;
 return result;
end $$;

create function laundry_private.asset_calculation(a laundry_private.assets,washes integer,reason text,as_of date) returns jsonb language plpgsql stable set search_path='' as $$
declare age_value integer; band jsonb; result jsonb;
begin
 result:=jsonb_build_object('reason',reason,'priceCents',a.price_cents,'serviceDate',a.service_date,'asOf',as_of,'washes',washes,'washBaseline',a.wash_baseline,'policy',a.policy);
 if reason not in ('improper_damage','lost','not_returned','buyout') then return result||jsonb_build_object('state','not_chargeable','amountCents',0);end if;
 if a.price_cents is null or a.service_date is null or a.policy is null or as_of<a.service_date then return result||jsonb_build_object('state','incomplete');end if;
 if a.policy->>'base'='months' then
  age_value:=((extract(year from as_of)-extract(year from a.service_date))*12+extract(month from as_of)-extract(month from a.service_date))::int;
  if as_of<(a.service_date+age_value*interval '1 month')::date then age_value:=age_value-1;end if;
 else age_value:=washes-a.wash_baseline;end if;
 if age_value<0 then return result||jsonb_build_object('state','incomplete');end if;
 select value into band from jsonb_array_elements(a.policy->'bands') where age_value>=(value->>'from')::integer and (value->>'to' is null or age_value<(value->>'to')::integer);
 if band is null then return result||jsonb_build_object('state','incomplete','age',age_value);end if;
 return result||jsonb_build_object('state','pending','age',age_value,'percent',(band->>'percent')::numeric,'amountCents',round(a.price_cents*(band->>'percent')::numeric/100)::bigint);
end $$;
create function laundry_private.asset_idle(pid text) returns void language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.laundry_wash_items i join public.laundry_wash_batches b on b.id=i.batch_id left join public.laundry_dry_cycles c on c.wash_batch_id=b.id where i.code=pid and (b.state<>'estimated' or c.state in ('running','blocked') or (b.requires_drying and coalesce(c.state,'pending')<>'estimated'))) then raise exception 'ASSET_MACHINE_BUSY';end if;
 if exists(select 1 from public.laundry_production p cross join lateral jsonb_array_elements(p.data->'tasks') t cross join lateral jsonb_array_elements(t->'items') i where i->>'code'=pid and t->>'status' in ('running','paused')) then raise exception 'ASSET_TASK_BUSY';end if;
end $$;
create function laundry_private.asset_project(pid text) returns void language plpgsql security definer set search_path='' as $$
declare a laundry_private.assets;
begin
 select * into strict a from laundry_private.assets where product_id=pid;
 update public.laundry_products set data=data||jsonb_build_object('lifecycleState',a.state,'replacedBy',a.replaced_by,'replaces',a.replaces) where id=pid;
end $$;
create function laundry_private.tag_release(pid text) returns text language plpgsql security definer set search_path='' as $$
declare code_value text;
begin
 select tag_code into code_value from laundry_private.tag_assignments where product_id=pid and released_at is null;
 update laundry_private.tag_assignments set released_at=now() where product_id=pid and released_at is null;
 update laundry_private.tags set state='check',verified_at=null,verified_by=null where code=code_value;
 update public.laundry_products set data=jsonb_set(data,'{barcode}',to_jsonb('__untagged__:'||id)) where id=pid;
 return code_value;
end $$;
create function laundry_private.tag_attach(pid text,code_value text,actor_value text,is_new boolean) returns void language plpgsql security definer set search_path='' as $$
declare t laundry_private.tags;
begin
 if nullif(trim(code_value),'') is null or length(code_value)>200 or code_value~'[[:cntrl:]]' or left(code_value,2)='__' then raise exception 'INVALID_BARCODE';end if;
 select * into t from laundry_private.tags where code=lower(code_value) for update;
 if t.code is null then
  if not is_new or laundry_private.tag_conflict(pid,code_value) then raise exception 'TAG_UNAVAILABLE';end if;
  insert into laundry_private.tags(code,display_code,state) values(lower(code_value),code_value,'in_use');
 else
  if is_new or t.state<>'free' or t.attachment<>'heatsealed_sewn' or t.verified_at is null then raise exception 'TAG_NOT_VERIFIED_FREE';end if;
  update laundry_private.tags set state='in_use' where code=t.code;
 end if;
 insert into laundry_private.tag_assignments(tag_code,product_id,assigned_at,actor) values(lower(code_value),pid,now(),actor_value);
 update public.laundry_products set data=jsonb_set(jsonb_set(data,'{barcode}',to_jsonb(code_value)),'{raw}',coalesce(data->'raw','{}')||jsonb_build_object('CODICE',code_value)) where id=pid;
end $$;

-- Protect terminal rows and the garment history against legacy save/import endpoints.
create function laundry_private.asset_lot_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare r jsonb; prior jsonb;
begin
 for r in select value from jsonb_array_elements(new.data->'rows') loop
  if tg_op='UPDATE' then select value into prior from jsonb_array_elements(old.data->'rows') where value->>'code'=r->>'code';end if;
  if r->>'state'='Dismesso' and coalesce(prior->>'state','')<>'Dismesso' and not exists(select 1 from laundry_private.assets where product_id=r->>'code' and state in ('retired','bought_out','reconditioning')) then raise exception 'USE_ASSET_WORKFLOW';end if;
  if exists(select 1 from laundry_private.assets where product_id=r->>'code' and state in ('retired','bought_out','reconditioning')) then
   if prior is null or r->>'state' not in ('Dismesso','Uscito') then raise exception 'ASSET_RETIRED';end if;
  end if;
  if prior->>'state'='Dismesso' and r is distinct from prior then raise exception 'DISMISSED_ROW_IMMUTABLE';end if;
 end loop;
 return new;
end $$;
create trigger zz_asset_lot_guard before insert or update on public.laundry_lots for each row execute function laundry_private.asset_lot_guard();

create function laundry_private.asset_control(action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare who jsonb; actor_value text; rev bigint; pid text:=p->>'productId'; a laundry_private.assets; g jsonb; replacement jsonb; next_id text; old_tag text; tag_record laundry_private.tags; policy_value jsonb; band jsonb; last_end integer:=0; idx integer:=0; event_value jsonb; calc_value jsonb; reason_value text:=p->>'reason'; d jsonb; task_ids text[]; response jsonb; request_id uuid;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';actor_value:=who->>'email';
 if action not in ('read','quote','policy','configure','retire','replace','verify_tag','assign_tag','release_tag','charge_decide','charge_complete','return','recondition','buyout') then raise exception 'INVALID_ACTION';end if;
 if action not in ('read','quote') then perform laundry_private.require_permission('products_manage');end if;
 select revision into rev from public.laundry_meta where id for update;
 if action not in ('read','quote') then
  request_id:=(p->>'requestId')::uuid;if request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;
  select r.response into response from laundry_private.asset_requests r where r.id=request_id and r.actor=actor_value;
  if found then return response;end if;
  if (p->>'revision')::bigint is distinct from rev then raise exception 'REVISION_CONFLICT';end if;
 end if;
 if action='policy' then
  if length(trim(coalesce(p->>'name','')))<1 or coalesce(p->>'base','') not in ('months','washes') or jsonb_typeof(p->'bands') is distinct from 'array' or jsonb_array_length(p->'bands')=0 then raise exception 'INVALID_POLICY';end if;
  for band in select value from jsonb_array_elements(p->'bands') loop
   if last_end is null or coalesce(band->>'from','') !~ '^[0-9]+$' or (band->>'from')::integer<>last_end or (band->>'to' is not null and ((band->>'to') !~ '^[0-9]+$' or (band->>'to')::integer<=last_end)) or nullif(band->>'percent','') is null or (band->>'percent')::numeric not between 0 and 100 then raise exception 'INVALID_POLICY_BANDS';end if;
   last_end:=(band->>'to')::integer;idx:=idx+1;
  end loop;
  if last_end is not null then raise exception 'POLICY_FINAL_BAND_OPEN';end if;
  insert into laundry_private.asset_policies(name,base,bands,created_by) values(trim(p->>'name'),p->>'base',p->'bands',actor_value);
 elsif action in ('verify_tag','assign_tag','release_tag') then
  if action='verify_tag' then
   select * into tag_record from laundry_private.tags where code=lower(p->>'tag') for update;
   if tag_record.code is null or tag_record.state not in ('check','free') then raise exception 'TAG_UNAVAILABLE';end if;
   if p->>'outcome'='destroyed' then update laundry_private.tags set state='destroyed',verified_at=null,verified_by=actor_value where code=tag_record.code;
   elsif p->>'outcome'='free' and p->>'attachment'='heatsealed_sewn' and p->>'checked'='true' then update laundry_private.tags set state='free',attachment='heatsealed_sewn',verified_at=now(),verified_by=actor_value where code=tag_record.code;
   else raise exception 'TAG_INSPECTION_REQUIRED';end if;
  else
   select data into strict g from public.laundry_products where id=pid for update;
   perform laundry_private.asset_idle(pid);
   if g->>'lifecycleState' in ('retired','bought_out') then raise exception 'ASSET_RETIRED';end if;
   if action='release_tag' then perform laundry_private.tag_release(pid);
   else
    if exists(select 1 from laundry_private.tag_assignments where product_id=pid and released_at is null) then raise exception 'RELEASE_CURRENT_TAG_FIRST';end if;
    perform laundry_private.tag_attach(pid,trim(p->>'tag'),actor_value,coalesce((p->>'newTag')::boolean,false));
   end if;
  end if;
 elsif action in ('charge_decide','charge_complete') then
  if action='charge_decide' then
   if coalesce(p->>'decision','') not in ('approved','rejected') or length(trim(coalesce(p->>'note','')))<3 then raise exception 'DECISION_REQUIRED';end if;
   update laundry_private.asset_charges set state=p->>'decision',decided_at=now(),decided_by=actor_value,decision_note=p->>'note' where id=(p->>'chargeId')::uuid and state='pending';
   if not found then raise exception 'CHARGE_NOT_PENDING';end if;
  else
   select product_id into pid from laundry_private.asset_charges where id=(p->>'chargeId')::uuid and state='incomplete' for update;
   if not found then raise exception 'CHARGE_NOT_INCOMPLETE';end if;
   select * into a from laundry_private.assets where product_id=pid;
   select data into g from public.laundry_products where id=pid;
   -- Completion supplies missing evidence on the proposal, never rewrites the frozen asset.
   a.price_cents:=coalesce(a.price_cents,(p->>'priceCents')::bigint);a.service_date:=coalesce(a.service_date,(p->>'serviceDate')::date);
   if a.policy is null then select to_jsonb(x) into a.policy from laundry_private.asset_policies x where id=(p->>'policyId')::uuid;end if;
   if a.price_cents<0 or a.service_date>(a.retired_at at time zone 'Europe/Rome')::date then raise exception 'INVALID_FINANCIAL_DATA';end if;
   calc_value:=laundry_private.asset_calculation(a,(g->>'wash')::integer,a.reason,(a.retired_at at time zone 'Europe/Rome')::date);
   update laundry_private.asset_charges set calculation=calc_value,state=calc_value->>'state',amount_cents=(calc_value->>'amountCents')::bigint where id=(p->>'chargeId')::uuid;
  end if;
 elsif action not in ('read','policy') then
  select data into g from public.laundry_products where id=pid for update;if g is null then raise exception 'UNKNOWN_PRODUCT';end if;
  select * into a from laundry_private.assets where product_id=pid for update;
  if action='quote' then
   if coalesce(reason_value,'') not in ('wear','wash_limit','breakage','permanent_stain','improper_damage','lost','not_returned','buyout') then raise exception 'DISCARD_REASON_REQUIRED';end if;
   if a.product_id is null then a.product_id:=pid;end if;
   return laundry_private.asset_calculation(a,(g->>'wash')::integer,reason_value,(now() at time zone 'Europe/Rome')::date);
  end if;
  if action='configure' then
   if a.state in ('retired','bought_out') or a.service_date is not null and a.state='in_service' then raise exception 'SERVICE_VALUES_FROZEN';end if;
   if coalesce(p->>'state','') not in ('stock','in_service') or (p->>'priceCents')::bigint<0 or (p->>'serviceDate')::date>(now() at time zone 'Europe/Rome')::date then raise exception 'INVALID_ASSET_DATA';end if;
   if nullif(p->>'policyId','') is not null then select to_jsonb(x) into policy_value from laundry_private.asset_policies x where id=(p->>'policyId')::uuid;if policy_value is null then raise exception 'POLICY_NOT_FOUND';end if;end if;
   if p->>'state'='in_service' and nullif(p->>'serviceDate','') is null then raise exception 'SERVICE_DATE_REQUIRED';end if;
   insert into laundry_private.assets(product_id,state,price_cents,service_date,wash_baseline,policy,events) values(pid,p->>'state',(p->>'priceCents')::bigint,(p->>'serviceDate')::date,coalesce((p->>'washBaseline')::integer,0),policy_value,'[]') on conflict(product_id) do update set state=excluded.state,price_cents=excluded.price_cents,service_date=excluded.service_date,wash_baseline=excluded.wash_baseline,policy=excluded.policy;
   if (p->>'state'='stock' and p->>'serviceDate' is not null) or (p->>'washBaseline')::integer>(g->>'wash')::integer then raise exception 'INVALID_WASH_BASELINE';end if;
   perform laundry_private.asset_project(pid);
   if p->>'state'='stock' then update public.laundry_products set data=jsonb_set(data,'{rentalContract}','null') where id=pid;end if;
  elsif action in ('retire','replace','return','buyout','recondition') then
   perform laundry_private.asset_idle(pid);
   if a.state='bought_out' or a.state='retired' and (action<>'replace' or a.replaced_by is not null) then raise exception 'ASSET_ALREADY_CLOSED';end if;
   if a.state='retired' and reason_value is distinct from a.reason then raise exception 'DISCARD_REASON_IMMUTABLE';end if;
   if action='recondition' then
    if a.state is distinct from 'reconditioning' or p->>'checked' is distinct from 'true' then raise exception 'RECONDITION_CHECK_REQUIRED';end if;
    update laundry_private.assets set state='stock',service_date=null,policy=null where product_id=pid;
    perform laundry_private.asset_project(pid);
    update public.laundry_products set data=data||jsonb_build_object('name','','dept','','rentalContract',null,'raw',coalesce(data->'raw','{}')||jsonb_build_object('NOME E COGNOME','','REPARTO','')) where id=pid;
   else
    if action in ('retire','replace') and (reason_value is null or reason_value not in ('wear','wash_limit','breakage','permanent_stain','improper_damage','lost','not_returned')) then raise exception 'DISCARD_REASON_REQUIRED';end if;
    if action='replace' and coalesce(p->>'tagMode','') not in ('reuse','new','free') then raise exception 'TAG_MODE_REQUIRED';end if;
    if action='buyout' then reason_value:='buyout';elsif action='return' then reason_value:='contract_return';end if;
    if action in ('return','buyout') and not exists(select 1 from public.laundry_clients c cross join lateral jsonb_array_elements(coalesce(c.data->'rentalContracts','[]')) k where c.id=g#>>'{rentalContract,clientId}' and k->>'id'=g#>>'{rentalContract,contractId}' and k->>'status'='closed') then raise exception 'CLOSE_CONTRACT_FIRST';end if;
    old_tag:=(select tag_code from laundry_private.tag_assignments where product_id=pid order by (released_at is null) desc,released_at desc nulls last limit 1);
    if action='replace' and p->>'tagMode'='reuse' and exists(select 1 from laundry_private.tag_assignments where tag_code=old_tag and released_at is null and product_id<>pid) then raise exception 'TAG_UNAVAILABLE';end if;
    if action='replace' and p->>'tagMode'='reuse' and (old_tag is null or reason_value in ('lost','not_returned') or p->>'checked' is distinct from 'true' or p->>'attachment' is distinct from 'heatsealed_sewn') then raise exception 'TAG_INSPECTION_REQUIRED';end if;
    insert into laundry_private.assets(product_id,state) values(pid,'in_service') on conflict do nothing;
    select * into a from laundry_private.assets where product_id=pid;
    event_value:=jsonb_build_object('at',now(),'action',action,'actor',actor_value,'reason',reason_value,'tag',old_tag,'contract',g->'rentalContract','serviceDate',a.service_date,'priceCents',a.price_cents,'policy',a.policy);
    if action='replace' then
     next_id:=nullif(p->>'replacementId','');
     if next_id is null then
      next_id:=gen_random_uuid()::text;
      replacement:=jsonb_build_object('id',next_id,'barcode','__untagged__:'||next_id,'barcodeAliases','[]'::jsonb,'wash',0,'max',(g->>'max')::integer,'history','[]'::jsonb,'raw','{}'::jsonb);
      insert into public.laundry_products(id,data) values(next_id,replacement);
      insert into laundry_private.assets(product_id,state) values(next_id,'stock');
     else
      select data into replacement from public.laundry_products where id=next_id for update;
      if not exists(select 1 from laundry_private.assets where product_id=next_id and state='stock') or next_id=pid or coalesce(replacement->'rentalContract','null')<>'null'::jsonb then raise exception 'REPLACEMENT_NOT_STOCK';end if;
      if exists(select 1 from jsonb_array_elements_text('["type","size","color"]') k where replacement->>k is distinct from g->>k) then raise exception 'STOCK_MISMATCH';end if;
      if upper(coalesce(replacement#>>'{raw,SCARTO}','NO')) in ('SI','SÌ','TRUE','1') or upper(coalesce(replacement#>>'{raw,SMARRITO}','NO')) in ('SI','SÌ','TRUE','1') or (replacement->>'wash')::integer>=(replacement->>'max')::integer then raise exception 'STOCK_UNUSABLE';end if;
      perform laundry_private.asset_idle(next_id);
      if exists(select 1 from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r where r->>'code'=next_id and r->>'state' not in ('Uscito','Dismesso')) then raise exception 'STOCK_IN_OPEN_LOT';end if;
      perform laundry_private.tag_release(next_id);
      -- Reload aliases added by tag release before projecting the replacement.
      select data into replacement from public.laundry_products where id=next_id;
     end if;
     if nullif(p->>'policyId','') is not null then select to_jsonb(x) into policy_value from laundry_private.asset_policies x where id=(p->>'policyId')::uuid;if policy_value is null then raise exception 'POLICY_NOT_FOUND';end if;end if;
     if (p->>'priceCents')::bigint<0 then raise exception 'INVALID_PRICE';end if;
     update laundry_private.assets set state='in_service',price_cents=(p->>'priceCents')::bigint,service_date=(now() at time zone 'Europe/Rome')::date,wash_baseline=(replacement->>'wash')::integer,policy=policy_value,replaces=pid,events=events||jsonb_build_array(event_value) where product_id=next_id;
     replacement:=replacement||jsonb_build_object('name',g->'name','dept',g->'dept','type',g->'type','size',g->'size','color',g->'color','client',g->'client','rental',g->'rental','rentalContract',g->'rentalContract','lifecycleState','in_service','replaces',pid,'replacedBy',null,'barcode','__untagged__:'||next_id);
     replacement:=jsonb_set(replacement,'{raw}',coalesce(replacement->'raw','{}')||jsonb_build_object('SCARTO','NO','SMARRITO','NO','NOME E COGNOME',g->'name','REPARTO',g->'dept','AZIENDA',g->'client','TIPO',g->'type','TAGLIA',g->'size','COLORE',g->'color'));
     update public.laundry_products set data=replacement where id=next_id;
    end if;
    update laundry_private.assets set state=case action when 'return' then 'reconditioning' when 'buyout' then 'bought_out' else 'retired' end,retired_at=case when action<>'return' then coalesce(retired_at,now()) else null end,reason=reason_value,replaced_by=next_id,events=events||jsonb_build_array(event_value) where product_id=pid;
    perform laundry_private.asset_project(pid);
    if action<>'buyout' then perform laundry_private.tag_release(pid);end if;
    if action in ('retire','replace','buyout') then
     if action<>'buyout' then update public.laundry_products set data=jsonb_set(data,'{raw}',coalesce(data->'raw','{}')||jsonb_build_object('SCARTO','SI')) where id=pid;end if;
     select * into a from laundry_private.assets where product_id=pid;
     calc_value:=laundry_private.asset_calculation(a,(g->>'wash')::integer,reason_value,(now() at time zone 'Europe/Rome')::date);
     if calc_value->>'state'<>'not_chargeable' then insert into laundry_private.asset_charges(product_id,reason,state,amount_cents,calculation) values(pid,reason_value,calc_value->>'state',(calc_value->>'amountCents')::bigint,calc_value) on conflict(product_id,reason) do nothing;end if;
    end if;
    if action='replace' then
     if p->>'tagMode'='reuse' then
      update laundry_private.tags set state='free',attachment='heatsealed_sewn',verified_at=now(),verified_by=actor_value where code=old_tag;
      perform laundry_private.tag_attach(next_id,(select display_code from laundry_private.tags where code=old_tag),actor_value,false);
     else perform laundry_private.tag_attach(next_id,trim(p->>'tag'),actor_value,p->>'tagMode'='new');end if;
    end if;
    -- Preserve every lot row, close it explicitly as dismissed (never as delivered).
    update public.laundry_lots l set data=jsonb_set(l.data,'{rows}',(select jsonb_agg(case when r->>'code'=pid and r->>'state' not in ('Uscito','Dismesso') then r||jsonb_build_object('state','Dismesso','discard',action in ('retire','replace'),'lifecycleClosed',true,'disposition',action,'discardReason',reason_value,'replacedBy',next_id) else r end order by n) from jsonb_array_elements(l.data->'rows') with ordinality x(r,n))) where exists(select 1 from jsonb_array_elements(l.data->'rows') r where r->>'code'=pid and r->>'state' not in ('Uscito','Dismesso'));
    if action='return' then update public.laundry_products set data=jsonb_set(data,'{rentalContract}','null') where id=pid;end if;
    -- Pending task rows are retained with an explicit closed-product marker; planners exclude them.
    select data into d from public.laundry_production where id for update;
    select coalesce(array_agg(t->>'id'),array[]::text[]) into task_ids from jsonb_array_elements(d->'tasks') t where t->>'status'='pending' and exists(select 1 from jsonb_array_elements(t->'items') i where i->>'code'=pid);
    d:=jsonb_set(d,'{tasks}',(select coalesce(jsonb_agg(case when t->>'id'=any(task_ids) then t||jsonb_build_object('items',remaining,'quantity',greatest(jsonb_array_length(remaining),1),'status',case when jsonb_array_length(remaining)=0 then 'cancelled' else 'pending' end,'events',coalesce(t->'events','[]')||jsonb_build_array(event_value||jsonb_build_object('previousItems',t->'items'))) else t end order by n),'[]') from jsonb_array_elements(d->'tasks') with ordinality x(t,n) cross join lateral (select coalesce(jsonb_agg(i),'[]') as remaining from jsonb_array_elements(t->'items') i where i->>'code' is distinct from pid) rest));
    if jsonb_typeof(d->'plan')='object' then
     d:=jsonb_set(d,'{planHistory}',coalesce(d->'planHistory','[]')||jsonb_build_array(d->'plan'));
     d:=jsonb_set(d,'{plan,allocations}',(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(d#>'{plan,allocations}') x where not(x->>'taskId'=any(task_ids))));
     d:=jsonb_set(d,'{plan,issues}',(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(d#>'{plan,issues}') x where not(x->>'taskId'=any(task_ids))));
    end if;
    if jsonb_typeof(d->'plan')='object' then d:=jsonb_set(d,'{plan,stale}','true');end if;
    update public.laundry_production set data=d,revision=revision+1 where id;
   end if;
  end if;
  if action<>'quote' then
   event_value:=coalesce(event_value,jsonb_build_object('at',now(),'action',action,'actor',actor_value,'previousContract',g->'rentalContract','previousAsset',to_jsonb(a)));
   if action in ('configure','recondition') then update laundry_private.assets set events=events||jsonb_build_array(event_value) where product_id=pid;end if;
   update public.laundry_products set data=jsonb_set(data,'{history}',coalesce(data->'history','[]')||jsonb_build_array(event_value||jsonb_build_object('time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'code',pid,'replacementId',next_id))) where id=pid or id=next_id;
  end if;
 end if;
 if action not in ('read','quote') then
  update public.laundry_meta set revision=revision+1 where id returning revision into rev;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor_value,auth.uid()::text,'asset_'||action,p-'revision');
 end if;
 response:=jsonb_build_object('revision',rev,'assets',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from laundry_private.assets x),'tags',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from laundry_private.tags x),'assignments',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from laundry_private.tag_assignments x),'policies',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from laundry_private.asset_policies x),'charges',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from laundry_private.asset_charges x),'replacementId',next_id);
 if action not in ('read','quote') then insert into laundry_private.asset_requests(id,response,actor) values(request_id,response,actor_value);end if;
 return response;
end $$;
create function public.laundry_assets(p_action text,p_payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select laundry_private.asset_control(p_action,p_payload)$$;
-- Private helpers are not directly callable by clients, including via the exposed public schema.
do $$declare f record;begin for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='laundry_private' and (p.proname like 'asset_%' or p.proname like 'tag_%') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated';end loop;end $$;
grant execute on function laundry_private.asset_control(text,jsonb) to authenticated;
revoke all on function public.laundry_assets(text,jsonb) from public,anon;
grant execute on function public.laundry_assets(text,jsonb) to authenticated;
