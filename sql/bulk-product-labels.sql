create table laundry_private.product_copy_requests(
 actor_id uuid not null,
 request_id uuid not null,
 source_id text not null,
 quantity integer not null check(quantity between 1 and 200),
 product_ids text[] not null,
 created_at timestamptz not null default now(),
 primary key(actor_id,request_id)
);
alter table laundry_private.product_copy_requests enable row level security;
revoke all on laundry_private.product_copy_requests from public,anon,authenticated;

create function laundry_private.copy_products(p_source_id text,p_quantity integer,p_request_id uuid,p_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 identity_result jsonb; actor uuid; rev bigint; original jsonb; template jsonb; raw_data jsonb;
 client_data jsonb; contract_data jsonb; contract_ref jsonb; code text; ids text[]:='{}';
 prior laundry_private.product_copy_requests; i integer; response jsonb;
begin
 identity_result:=laundry_private.laundry_authenticated('version','{}');
 perform laundry_private.require_permission('products_manage');
 actor:=auth.uid();
 if p_quantity is null or p_quantity not between 1 and 200 then raise exception 'INVALID_QUANTITY';end if;
 if p_request_id is null or nullif(p_source_id,'') is null then raise exception 'INVALID_COPY_REQUEST';end if;
 select revision into rev from public.laundry_meta where id for update;
 select * into prior from laundry_private.product_copy_requests where actor_id=actor and request_id=p_request_id;
 if found then
  if prior.source_id<>p_source_id or prior.quantity<>p_quantity then raise exception 'COPY_REQUEST_MISMATCH';end if;
  ids:=prior.product_ids;
 else
  if p_revision is distinct from rev then raise exception 'REVISION_CONFLICT';end if;
  select data into original from public.laundry_products where id=p_source_id;
  if original is null then raise exception 'UNKNOWN_PRODUCT';end if;
  select data into client_data from public.laundry_clients where data->>'name'=original->>'client' and data->>'active' is distinct from 'false';
  if client_data is null then raise exception 'INVALID_CLIENT';end if;
  if coalesce((original->>'max')::int,0)<1 then raise exception 'INVALID_WASH_LIMIT';end if;
  -- Copy descriptive fields only. Identity, lifecycle, wash/repair history and old tags never carry over.
  select coalesce(jsonb_object_agg(key,value),'{}') into template from jsonb_each(original)
   where key in ('name','client','dept','type','size','color','rental','max');
  select coalesce(jsonb_object_agg(key,value),'{}') into raw_data from jsonb_each(coalesce(original->'raw','{}'))
   where key in ('ARMADIO','POSIZIONE','MATRICOLA','INIZIALI','ESTERNA','LOTTO','NOTE','ACCESSORI','ACCESSORI NOTE','ALLERGICO');
  raw_data:=raw_data||jsonb_build_object('NOME E COGNOME',original->>'name','AZIENDA',original->>'client','REPARTO',original->>'dept','TIPO',original->>'type','TAGLIA',original->>'size','COLORE',original->>'color','GESTIONE',original#>>'{raw,GESTIONE}','NUMERO LAVAGGI',0,'LAVAGGI MASSIMI',(original->>'max')::int,'SCARTO','NO','SMARRITO','NO','AL LIMITE ACCETTABILITA','NO','DATA DI PERSONALIZZAZIONE','');
  contract_ref:=null;
  if original->>'rental'='true' and original#>>'{rentalContract,clientId}'=client_data->>'id' then
   select c into contract_data from jsonb_array_elements(coalesce(client_data->'rentalContracts','[]')) c
   where c->>'id'=original#>>'{rentalContract,contractId}' and c->>'status'='active'
   and coalesce(nullif(c->>'start',''),'0001-01-01')<=to_char(now() at time zone 'Europe/Rome','YYYY-MM-DD')
   and coalesce(nullif(c->>'end',''),'9999-12-31')>=to_char(now() at time zone 'Europe/Rome','YYYY-MM-DD');
   if contract_data is not null then contract_ref:=original->'rentalContract';end if;
  end if;
  template:=template||jsonb_build_object('wash',0,'history','[]'::jsonb,'barcodeAliases','[]'::jsonb,'rentalContract',contract_ref);
  raw_data:=raw_data||jsonb_build_object('CONTRATTO NOLEGGIO',coalesce(contract_data->>'number',''));
  for i in 1..p_quantity loop
   code:=laundry_private.next_available_barcode();
   insert into public.laundry_products(id,data) values(code,template||jsonb_build_object('id',code,'barcode',code,'raw',raw_data||jsonb_build_object('CODICE',code)));
   ids:=array_append(ids,code);
  end loop;
  insert into laundry_private.product_copy_requests(actor_id,request_id,source_id,quantity,product_ids) values(actor,p_request_id,p_source_id,p_quantity,ids);
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(identity_result->'user'->>'email',actor::text,'products_copied',jsonb_build_object('source',p_source_id,'quantity',p_quantity,'ids',ids,'requestId',p_request_id));
 end if;
 perform set_config('laundry.compact_snapshot','on',true);
 perform set_config('laundry.product_scope','',true);
 perform set_config('laundry.product_ids',to_jsonb(ids)::text,true);
 response:=laundry_private.laundry_authenticated('snapshot','{}');
 return response||jsonb_build_object('created_ids',to_jsonb(ids),'created_count',cardinality(ids));
end $$;
revoke all on function laundry_private.copy_products(text,integer,uuid,bigint) from public,anon,authenticated;
grant execute on function laundry_private.copy_products(text,integer,uuid,bigint) to authenticated;
create function public.laundry_copy_products(p_source_id text,p_quantity integer,p_request_id uuid,p_revision bigint)
returns jsonb language sql security invoker set search_path='' as $$
 select laundry_private.copy_products(p_source_id,p_quantity,p_request_id,p_revision);
$$;
revoke all on function public.laundry_copy_products(text,integer,uuid,bigint) from public,anon,authenticated;
grant execute on function public.laundry_copy_products(text,integer,uuid,bigint) to authenticated;
