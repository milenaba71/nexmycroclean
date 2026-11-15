create table laundry_private.bags (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 120)
);
create unique index bags_name on laundry_private.bags(lower(btrim(name)));
create table laundry_private.bag_recipe (
 scope text not null check(scope in ('type','product')), target text not null,
 bag uuid not null references laundry_private.bags, quantity integer not null check(quantity between 1 and 1000),
 primary key(scope,target)
);
create table laundry_private.bag_moves (
 id bigint generated always as identity primary key, bag uuid not null references laundry_private.bags,
 delta integer not null check(delta<>0), lot bigint, product text, request uuid unique,
 note text, actor text, at timestamptz not null default now(), unique(lot,product)
);
create index bag_moves_bag on laundry_private.bag_moves(bag);
revoke all on laundry_private.bags,laundry_private.bag_recipe,laundry_private.bag_moves from public,anon,authenticated;

create function laundry_private.consume_exit_bags() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from laundry_private.bag_recipe) then return new; end if;
 insert into laundry_private.bag_moves(bag,delta,lot,product,actor)
 select recipe.bag,-recipe.quantity,new.id,g.id,auth.jwt()->>'email'
 from jsonb_array_elements(new.data->'rows') r
 join public.laundry_products g on g.id=r->>'code'
 left join public.laundry_types t on lower(btrim(t.name))=lower(btrim(g.data->>'type'))
 join lateral (
   select b.bag,b.quantity from laundry_private.bag_recipe b
   where (b.scope='product' and b.target=g.id) or (b.scope='type' and b.target=t.id)
   order by (b.scope='product') desc limit 1
 ) recipe on true
 where r->>'state'='Uscito' and not exists (
   select 1 from jsonb_array_elements(case when tg_op='UPDATE' then old.data->'rows' end) prev
   where prev->>'code'=g.id and prev->>'state'='Uscito'
 )
 on conflict(lot,product) do nothing;
 return new;
end $$;
revoke all on function laundry_private.consume_exit_bags() from public,anon,authenticated;
create trigger consume_exit_bags after insert or update of data on public.laundry_lots
 for each row execute function laundry_private.consume_exit_bags();

create function public.laundry_bag_stock(action text,p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare who jsonb; target_id text; item uuid; amount integer; memo text; movement laundry_private.bag_moves;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
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
  if action='remove' then delete from laundry_private.bag_recipe where scope=p->>'scope' and target=target_id;
  else
   if p->>'scope'='product' then
    target_id:=laundry_private.tag_lookup(target_id)->>'id';
    if target_id is null then raise exception 'Prodotto non trovato';end if;
   elsif p->>'scope'='type' and not exists(select 1 from public.laundry_types where id=target_id and active) then raise exception 'Tipo di capo non disponibile';
   end if;
   insert into laundry_private.bag_recipe(scope,target,bag,quantity)
    values(p->>'scope',target_id,(p->>'bag')::uuid,(p->>'quantity')::integer)
    on conflict(scope,target) do update set bag=excluded.bag,quantity=excluded.quantity;
  end if;
 else raise exception 'Azione non valida';end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.laundry_bag_stock(text,jsonb) from public,anon;
grant execute on function public.laundry_bag_stock(text,jsonb) to authenticated;
