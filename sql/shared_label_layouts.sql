begin;
create table if not exists laundry_private.label_layouts (
 id boolean primary key default true check(id),
 revision bigint not null default 0,
 payload jsonb not null default '{"presets":{},"current":null}'::jsonb,
 updated_at timestamptz not null default now(),
 updated_by uuid
);
alter table laundry_private.label_layouts enable row level security;
revoke all on laundry_private.label_layouts from public,anon,authenticated;
insert into laundry_private.label_layouts(id) values(true) on conflict do nothing;
create or replace function public.laundry_label_layouts(p_action text, p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare saved laundry_private.label_layouts; body jsonb;
begin
 perform laundry_private.require_permission('products_manage');
 if p_action='read' then
  select * into saved from laundry_private.label_layouts where id;
 elsif p_action='save' then
  body:=p->'payload';
  if jsonb_typeof(body) is distinct from 'object'
   or jsonb_typeof(body->'presets') is distinct from 'object'
   or (body->'current' <> 'null'::jsonb and jsonb_typeof(body->'current') is distinct from 'object')
   or not(body ? 'current') or octet_length(body::text)>5000000
   then raise exception 'INVALID_LABEL_LAYOUT';end if;
  if exists(select 1 from jsonb_each(body->'presets') e where length(e.key)>150 or length(trim(e.key))=0 or jsonb_typeof(e.value) is distinct from 'object') then raise exception 'INVALID_LABEL_LAYOUT';end if;
  select * into saved from laundry_private.label_layouts where id for update;
  if (p->>'revision')::bigint is distinct from saved.revision then raise exception 'REVISION_CONFLICT';end if;
  update laundry_private.label_layouts set payload=body,revision=revision+1,updated_at=now(),updated_by=auth.uid() where id returning * into saved;
  insert into public.laundry_audit(actor_email,actor_id,action,details)
   select email,auth.uid()::text,'label_layouts_saved',jsonb_build_object('revision',saved.revision,'names',(select jsonb_agg(key) from jsonb_each(body->'presets'))) from auth.users where id=auth.uid();
 else raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('revision',saved.revision,'payload',saved.payload,'updated_at',saved.updated_at);
end $$;
revoke all on function public.laundry_label_layouts(text,jsonb) from public,anon;
grant execute on function public.laundry_label_layouts(text,jsonb) to authenticated;
commit;
