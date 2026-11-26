create table laundry_private.assistant_knowledge(
 id uuid primary key,
 title text not null check(length(title) between 3 and 120),
 body text not null check(length(body) between 10 and 4000),
 source text not null default '' check(length(source)<=300),
 active boolean not null default true,
 revision bigint not null default 1,
 approved_by uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 search_document tsvector generated always as (to_tsvector('italian'::regconfig,title||' '||body)) stored
);
alter table laundry_private.assistant_knowledge enable row level security;
create policy deny_direct_access on laundry_private.assistant_knowledge for all to anon,authenticated using(false) with check(false);
revoke all on laundry_private.assistant_knowledge from public,anon,authenticated;
create index assistant_knowledge_search on laundry_private.assistant_knowledge using gin(search_document) where active;

create function laundry_private.assistant_knowledge(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare who jsonb; old_row laundry_private.assistant_knowledge; item laundry_private.assistant_knowledge;
 target uuid; q text:=left(btrim(coalesce(p->>'query','')),1000); terms tsquery; result jsonb; can_train boolean;
begin
 perform public.laundry_assistant_quota(false);
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 can_train:=coalesce((who->>'isSuperAdmin')::boolean,false);
 if p_action in ('save','archive') then
  perform laundry_private.require_permission('super');
  target:=(p->>'id')::uuid;if target is null then raise exception 'INVALID_KNOWLEDGE';end if;
  -- Serialize only edits of the same instruction, not scans or the global production row.
  perform pg_advisory_xact_lock(hashtextextended(target::text,26));
  select * into old_row from laundry_private.assistant_knowledge where id=target for update;
  if coalesce(old_row.revision,0) is distinct from (p->>'revision')::bigint then raise exception 'KNOWLEDGE_CONFLICT';end if;
  if p_action='archive' then
   if old_row.id is null then raise exception 'KNOWLEDGE_NOT_FOUND';end if;
   update laundry_private.assistant_knowledge set active=false,revision=revision+1,updated_at=now(),approved_by=auth.uid() where id=target returning * into item;
  else
   if p->>'approved' is distinct from 'true' or jsonb_typeof(p->'title') is distinct from 'string' or jsonb_typeof(p->'body') is distinct from 'string' then raise exception 'APPROVAL_REQUIRED';end if;
   insert into laundry_private.assistant_knowledge(id,title,body,source,approved_by)
   values(target,btrim(p->>'title'),btrim(p->>'body'),btrim(coalesce(p->>'source','')),auth.uid())
   on conflict(id) do update set title=excluded.title,body=excluded.body,source=excluded.source,active=true,revision=assistant_knowledge.revision+1,updated_at=now(),approved_by=excluded.approved_by returning * into item;
  end if;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'assistant_knowledge_'||p_action,jsonb_build_object('id',target,'before',to_jsonb(old_row)-'search_document','after',to_jsonb(item)-'search_document'));
  return jsonb_build_object('id',item.id,'revision',item.revision,'saved',true);
 elsif p_action='search' then
  if q='' then return jsonb_build_object('documents','[]'::jsonb);end if;
  terms:=websearch_to_tsquery('italian',regexp_replace(q,'\s+',' OR ','g'));
  select coalesce(jsonb_agg(x),'[]') into result from (
   select id,title,body,source,revision,updated_at from laundry_private.assistant_knowledge
   where active and search_document @@ terms order by ts_rank(search_document,terms) desc,updated_at desc,id limit 5
  ) x;
  return jsonb_build_object('documents',result);
 elsif p_action='status' then
  return jsonb_build_object('canTrain',can_train,'total',(select count(*) from laundry_private.assistant_knowledge where active));
 elsif p_action='list' then
  select coalesce(jsonb_agg(x),'[]') into result from (
   select id,title,body,source,revision,updated_at from laundry_private.assistant_knowledge where active and (q='' or title ilike '%'||q||'%' or body ilike '%'||q||'%') order by updated_at desc,id limit 100
  ) x;
  return jsonb_build_object('documents',result,'canTrain',can_train,'total',(select count(*) from laundry_private.assistant_knowledge where active));
 else raise exception 'INVALID_ACTION';end if;
end $$;
revoke all on function laundry_private.assistant_knowledge(text,jsonb) from public,anon,authenticated;
grant execute on function laundry_private.assistant_knowledge(text,jsonb) to authenticated;
create function public.laundry_assistant_knowledge(p_action text default 'list',p jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select laundry_private.assistant_knowledge(p_action,p)$$;
revoke all on function public.laundry_assistant_knowledge(text,jsonb) from public,anon,authenticated;
grant execute on function public.laundry_assistant_knowledge(text,jsonb) to authenticated;
