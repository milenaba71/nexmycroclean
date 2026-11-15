alter table laundry_private.bag_recipe add column client_id text not null default '',
 add column capacity integer not null default 1 check(capacity between 1 and 10000);
alter table laundry_private.bag_recipe drop constraint bag_recipe_pkey,
 add primary key(scope,target,client_id);
create table laundry_private.bag_packed_items (
 lot bigint not null, product text not null, group_key jsonb not null, primary key(lot,product)
);
create index bag_packed_groups on laundry_private.bag_packed_items(lot,group_key);
revoke all on laundry_private.bag_packed_items from public,anon,authenticated;
create or replace function laundry_private.consume_exit_bags() returns trigger
language plpgsql security definer set search_path='' as $$
declare item record; grouping jsonb; packed bigint;
begin
 if not exists(select 1 from laundry_private.bag_recipe) then return new; end if;
 for item in
  select g.id, g.data->>'type' as kind, recipe.*
  from jsonb_array_elements(new.data->'rows') with ordinality as x(r,idx)
  join public.laundry_products g on g.id=r->>'code'
  left join public.laundry_types t on lower(btrim(t.name))=lower(btrim(g.data->>'type'))
  join lateral (
    select b.* from laundry_private.bag_recipe b
    where ((b.scope='product' and b.target=g.id) or (b.scope='type' and b.target=t.id))
      and (b.client_id='' or exists(select 1 from public.laundry_clients c where c.id=b.client_id and c.data->>'name'=new.data->>'client'))
    order by (b.scope='product') desc,(b.client_id<>'') desc limit 1
  ) recipe on true
  where r->>'state'='Uscito' and not exists (
    select 1 from jsonb_array_elements(case when tg_op='UPDATE' then old.data->'rows' end) prev
    where prev->>'code'=g.id and prev->>'state'='Uscito')
  and not exists(select 1 from laundry_private.bag_moves m where m.lot=new.id and m.product=g.id)
  order by idx
 loop
  grouping:=jsonb_build_array(new.data->>'client',item.kind,item.bag,item.capacity,item.quantity);
  insert into laundry_private.bag_packed_items values(new.id,item.id,grouping) on conflict do nothing;
  if not found then continue; end if;
  if item.capacity>1 then
   select count(*) into packed from laundry_private.bag_packed_items where lot=new.id and group_key=grouping;
   if (packed-1)%item.capacity<>0 then continue;end if;
  end if;
  insert into laundry_private.bag_moves(bag,delta,lot,product,actor)
  values(item.bag,-item.quantity,new.id,item.id,auth.jwt()->>'email');
 end loop;
 return new;
end $$;
create or replace function public.laundry_bag_stock(action text,p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare who jsonb; target_id text; item uuid; amount integer; memo text; movement laundry_private.bag_moves;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 if who->>'role' is distinct from 'admin' then perform laundry_private.require_permission('production_manage'); end if;
 if action='read' then
  return jsonb_build_object(
   'bags',coalesce((select jsonb_agg(to_jsonb(b)||jsonb_build_object('stock',coalesce(s.stock,0)) order by b.name)
    from laundry_private.bags b left join (select bag,sum(delta) stock from laundry_private.bag_moves group by bag) s on s.bag=b.id),'[]'),
   'rules',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('label',coalesce(t.name,g.data->>'barcode',r.target)) order by r.scope,r.target)
    from laundry_private.bag_recipe r left join public.laundry_types t on r.scope='type' and t.id=r.target
    left join public.laundry_products g on r.scope='product' and g.id=r.target),'[]'),
   'history',coalesce((select jsonb_agg(to_jsonb(m) order by m.id desc) from
    (select * from laundry_private.bag_moves order by id desc limit 100) m),'[]'));
 end if;
 perform laundry_private.require_permission('products_manage');
 if action='create' then
  insert into laundry_private.bags(name) values(btrim(p->>'name')) on conflict do nothing;
 elsif action='move' then
  item:=(p->>'bag')::uuid; amount:=(p->>'quantity')::integer; memo:=btrim(p->>'note');
  if coalesce(amount,0)=0 or nullif(memo,'') is null or length(memo)>250 or p->>'request' is null then raise exception 'Movimento non valido'; end if;
  insert into laundry_private.bag_moves(bag,delta,note,request,actor)
   values(item,amount,memo,(p->>'request')::uuid,who->>'email') on conflict(request) do nothing;
  select * into strict movement from laundry_private.bag_moves where request=(p->>'request')::uuid;
  if (movement.bag,movement.delta,movement.note,movement.actor) is distinct from (item,amount,memo,who->>'email') then raise exception 'Richiesta già utilizzata';end if;
 elsif action in ('rule','remove') then
  target_id:=p->>'target';
  if coalesce(p->>'client_id','')<>'' and action='rule' and not exists(select 1 from public.laundry_clients c where c.id=p->>'client_id') then raise exception 'Cliente non disponibile';end if;
  if action='remove' then delete from laundry_private.bag_recipe where scope=p->>'scope' and target=target_id and client_id=coalesce(p->>'client_id','');
  else
   if p->>'scope'='product' then
    target_id:=laundry_private.tag_lookup(target_id)->>'id';
    if target_id is null then raise exception 'Prodotto non trovato';end if;
   elsif p->>'scope'='type' and not exists(select 1 from public.laundry_types where id=target_id and active) then raise exception 'Tipo di capo non disponibile';
   end if;
   insert into laundry_private.bag_recipe(scope,target,bag,quantity,client_id,capacity)
    values(p->>'scope',target_id,(p->>'bag')::uuid,(p->>'quantity')::integer,coalesce(p->>'client_id',''),coalesce((p->>'capacity')::integer,1))
    on conflict(scope,target,client_id) do update set bag=excluded.bag,quantity=excluded.quantity,capacity=excluded.capacity;
  end if;
 else raise exception 'Azione non valida';end if;
 return jsonb_build_object('ok',true);
end $$;
