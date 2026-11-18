-- Private attachments and per-user archive; archiving never deletes a message or a file.
alter table laundry_private.chat_messages add column attachments jsonb not null default '[]', add column sender_archived_at timestamptz;
alter table laundry_private.chat_recipients add column archived_at timestamptz;
create index chat_attachment_paths on laundry_private.chat_messages using gin(attachments jsonb_path_ops);
insert into storage.buckets(id,name,public,file_size_limit) values('chat-attachments','chat-attachments',false,10485760);
create function laundry_private.chat_file_access(object_name text, uploading boolean default false) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare who text;
begin
 if auth.uid() is null then return false;end if;
 select lower(email) into who from auth.users where id=auth.uid();
 if not exists(select 1 from public.laundry_members where email=who and active) then return false;end if;
 if split_part(object_name,'/',1)=auth.uid()::text then return object_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}$';end if;
 if uploading then return false;end if;
 return exists(select 1 from laundry_private.chat_messages m where m.attachments @> jsonb_build_array(jsonb_build_object('path',object_name)) and (m.sender_email=who or exists(select 1 from laundry_private.chat_recipients r where r.message_id=m.id and r.email=who)));
end $$;
revoke all on function laundry_private.chat_file_access(text,boolean) from public,anon,authenticated;
grant execute on function laundry_private.chat_file_access(text,boolean) to authenticated;
create policy chat_file_upload on storage.objects for insert to authenticated with check(bucket_id='chat-attachments' and laundry_private.chat_file_access(name,true));
create policy chat_file_read on storage.objects for select to authenticated using(bucket_id='chat-attachments' and laundry_private.chat_file_access(name,false));
create or replace function laundry_private.chat_api(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare who text; member public.laundry_members; recipients text[]; mid uuid; lid bigint;
 label_value text; body_value text; result jsonb; box text; skip integer; existing laundry_private.chat_messages; attachments_value jsonb; item jsonb;
begin
 if auth.uid() is null then raise exception 'UNAUTHORIZED';end if;
 select lower(email) into who from auth.users where id=auth.uid();
 select * into member from public.laundry_members where email=who and active;
 if not found then raise exception 'FORBIDDEN';end if;
 if p_action='users' then
  select coalesce(jsonb_agg(jsonb_build_object('email',email,'name',name) order by name),'[]') into result from public.laundry_members where active and email<>who;
  return result;
 elsif p_action='send' then
  mid:=(p->>'id')::uuid;lid:=(p->>'lot_id')::bigint;body_value:=btrim(p->>'body');
  if mid is null or body_value is null or char_length(body_value) not between 1 and 4000 then raise exception 'INVALID_MESSAGE';end if;
  if jsonb_typeof(p->'recipients') is distinct from 'array' then raise exception 'INVALID_RECIPIENTS';end if;
  select array_agg(distinct lower(btrim(v))) into recipients from jsonb_array_elements_text(p->'recipients') v;
  if coalesce(cardinality(recipients),0) not between 1 and 20 or exists(select 1 from unnest(recipients) r where r is null or r=who or not exists(select 1 from public.laundry_members m where m.email=r and m.active)) then raise exception 'INVALID_RECIPIENTS';end if;
  if lid is not null then
   select 'Lotto '||id||' · '||coalesce(data->>'client','') into label_value from public.laundry_lots where id=lid;
   if not found then raise exception 'LOT_NOT_FOUND';end if;
  end if;
  attachments_value:=coalesce(p->'attachments','[]'::jsonb);
  if jsonb_typeof(attachments_value)<>'array' or jsonb_array_length(attachments_value)>5 then raise exception 'INVALID_ATTACHMENTS';end if;
  for item in select value from jsonb_array_elements(attachments_value) loop
   if jsonb_typeof(item)<>'object' or coalesce(char_length(item->>'name'),0) not between 1 and 255 or
    split_part(coalesce(item->>'path',''), '/',1)<>auth.uid()::text or
    coalesce((item->>'size')::bigint,0) not between 1 and 10485760 or
    not exists(select 1 from storage.objects o where o.bucket_id='chat-attachments' and o.name=item->>'path' and (o.metadata->>'size')::bigint=(item->>'size')::bigint) then raise exception 'INVALID_ATTACHMENTS';end if;
  end loop;
  if (select count(distinct value->>'path') from jsonb_array_elements(attachments_value))<>jsonb_array_length(attachments_value) then raise exception 'INVALID_ATTACHMENTS';end if;
  -- A retry reuses its id and can never duplicate delivery.
  perform pg_advisory_xact_lock(hashtextextended(mid::text,0));
  select * into existing from laundry_private.chat_messages where id=mid;
  if found then
   if existing.sender_email<>who or existing.body<>body_value or existing.lot_id is distinct from lid or existing.attachments is distinct from attachments_value or
    (select array_agg(email order by email) from laundry_private.chat_recipients where message_id=mid) is distinct from (select array_agg(r order by r) from unnest(recipients) r) then raise exception 'MESSAGE_ID_CONFLICT';end if;
   return jsonb_build_object('id',mid);
  end if;
  insert into laundry_private.chat_messages(id,sender_email,sender_name,lot_id,lot_label,body,attachments) values(mid,who,coalesce(member.name,who),lid,label_value,body_value,attachments_value);
  insert into laundry_private.chat_recipients(message_id,email,recipient_name) select mid,email,coalesce(name,email) from public.laundry_members where email=any(recipients);
  return jsonb_build_object('id',mid);
 elsif p_action in ('archive','restore') then
  mid:=(p->>'id')::uuid;
  if exists(select 1 from laundry_private.chat_messages where id=mid and sender_email=who) then
   update laundry_private.chat_messages set sender_archived_at=case when p_action='archive' then now() else null end where id=mid and sender_email=who;
  else
   update laundry_private.chat_recipients set archived_at=case when p_action='archive' then now() else null end where message_id=mid and email=who;
   if not found then raise exception 'MESSAGE_NOT_FOUND';end if;
  end if;
  return jsonb_build_object('ok',true);
 elsif p_action='read' then
  update laundry_private.chat_recipients set read_at=coalesce(read_at,now()) where message_id=(p->>'id')::uuid and email=who;
  if not found then raise exception 'MESSAGE_NOT_FOUND';end if;
  return jsonb_build_object('ok',true);
 elsif p_action='list' then
  box:=coalesce(p->>'box','inbox');skip:=greatest(0,least(coalesce((p->>'offset')::integer,0),100000));
  if box not in ('inbox','sent','archived') then raise exception 'INVALID_BOX';end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]') into result from (
   select m.*,r.read_at,case when m.sender_email=who then m.sender_archived_at else r.archived_at end as archived_at,(select jsonb_agg(jsonb_build_object('email',q.email,'name',q.recipient_name,'read_at',q.read_at) order by q.recipient_name) from laundry_private.chat_recipients q where q.message_id=m.id) as recipients
   from laundry_private.chat_messages m left join laundry_private.chat_recipients r on r.message_id=m.id and r.email=who
   where (box='sent' and m.sender_email=who and m.sender_archived_at is null) or (box='inbox' and r.email=who and r.archived_at is null) or (box='archived' and ((m.sender_email=who and m.sender_archived_at is not null) or (r.email=who and r.archived_at is not null)))
   order by m.created_at desc,m.id desc limit 50 offset skip
  ) x;
  return jsonb_build_object('messages',result,'unread',(select count(*) from laundry_private.chat_recipients where email=who and read_at is null and archived_at is null),
   'alerts',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from (select m.id,m.sender_name,m.body,m.lot_label from laundry_private.chat_messages m join laundry_private.chat_recipients r on r.message_id=m.id where r.email=who and r.read_at is null and r.archived_at is null order by m.created_at desc,m.id desc limit 10) a));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
