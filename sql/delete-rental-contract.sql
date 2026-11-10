create or replace function laundry_private.delete_rental_contract(p_client text,p_contract text,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare who jsonb; rev bigint; customer jsonb; contract jsonb; vars jsonb;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('masters_manage');
 select revision into rev from public.laundry_meta where id for update;
 if p_revision is distinct from rev then raise exception 'REVISION_CONFLICT';end if;
 select data into customer from public.laundry_clients where id=p_client for update;
 select value into contract from jsonb_array_elements(coalesce(customer->'rentalContracts','[]')) where value->>'id'=p_contract;
 if contract is null then raise exception 'CONTRACT_NOT_FOUND';end if;
 vars:=jsonb_build_object('ref',p_contract);
 if exists(select 1 from public.laundry_products where jsonb_path_exists(data,'$.** ? (@ == $ref)',vars))
 or exists(select 1 from laundry_private.assets a where jsonb_path_exists(to_jsonb(a),'$.** ? (@ == $ref)',vars))
 or exists(select 1 from laundry_private.asset_charges a where jsonb_path_exists(to_jsonb(a),'$.** ? (@ == $ref)',vars))
 or exists(select 1 from public.laundry_lots where jsonb_path_exists(data,'$.** ? (@ == $ref)',vars))
 then raise exception 'CONTRACT_IN_USE';end if;
 customer:=jsonb_set(customer,'{rentalContracts}',(select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(customer->'rentalContracts') where value->>'id'<>p_contract));
 customer:=jsonb_set(customer,'{rentalEvents}',coalesce(customer->'rentalEvents','[]')||jsonb_build_array(jsonb_build_object('action','Contratto eliminato','at',now(),'actor',who->>'name','actorEmail',who->>'email','contractNumber',contract->>'number','details',jsonb_build_object('before',contract))));
 update public.laundry_clients set data=customer where id=p_client;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'rental_contract_deleted',jsonb_build_object('clientId',p_client,'before',contract));
 update public.laundry_meta set revision=revision+1 where id returning revision into rev;
 return jsonb_build_object('revision',rev,'deletedId',p_contract);
end $$;
revoke all on function laundry_private.delete_rental_contract(text,text,bigint) from public,anon;
grant execute on function laundry_private.delete_rental_contract(text,text,bigint) to authenticated;
create or replace function public.laundry_delete_rental_contract(p_client text,p_contract text,p_revision bigint) returns jsonb language sql security invoker set search_path='' as $$select laundry_private.delete_rental_contract(p_client,p_contract,p_revision)$$;
revoke all on function public.laundry_delete_rental_contract(text,text,bigint) from public,anon;
grant execute on function public.laundry_delete_rental_contract(text,text,bigint) to authenticated;
