-- Private messages: explicit participants only; no direct table access.
create table laundry_private.chat_messages(
 id uuid primary key, sender_email text not null, sender_name text not null,
 lot_id bigint, lot_label text, body text not null check(char_length(body) between 1 and 4000),
 created_at timestamptz not null default now()
);
create table laundry_private.chat_recipients(
 message_id uuid references laundry_private.chat_messages(id) on delete cascade,
 email text not null, recipient_name text not null, read_at timestamptz,
 primary key(message_id,email)
);
alter table laundry_private.chat_messages enable row level security;
alter table laundry_private.chat_recipients enable row level security;
revoke all on laundry_private.chat_messages,laundry_private.chat_recipients from public,anon,authenticated;
create index chat_sender_created on laundry_private.chat_messages(sender_email,created_at desc);
create index chat_recipient_unread on laundry_private.chat_recipients(email,read_at,message_id);
create function laundry_private.chat_api(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare who text; member public.laundry_members; recipients text[]; mid uuid; lid bigint;
 label_value text; body_value text; result jsonb; box text; skip integer; existing laundry_private.chat_messages;
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
  -- A retry reuses its id and can never duplicate delivery.
  perform pg_advisory_xact_lock(hashtextextended(mid::text,0));
  select * into existing from laundry_private.chat_messages where id=mid;
  if found then
   if existing.sender_email<>who or existing.body<>body_value or existing.lot_id is distinct from lid or
    (select array_agg(email order by email) from laundry_private.chat_recipients where message_id=mid) is distinct from (select array_agg(r order by r) from unnest(recipients) r) then raise exception 'MESSAGE_ID_CONFLICT';end if;
   return jsonb_build_object('id',mid);
  end if;
  insert into laundry_private.chat_messages(id,sender_email,sender_name,lot_id,lot_label,body) values(mid,who,coalesce(member.name,who),lid,label_value,body_value);
  insert into laundry_private.chat_recipients(message_id,email,recipient_name) select mid,email,coalesce(name,email) from public.laundry_members where email=any(recipients);
  return jsonb_build_object('id',mid);
 elsif p_action='read' then
  update laundry_private.chat_recipients set read_at=coalesce(read_at,now()) where message_id=(p->>'id')::uuid and email=who;
  if not found then raise exception 'MESSAGE_NOT_FOUND';end if;
  return jsonb_build_object('ok',true);
 elsif p_action='list' then
  box:=coalesce(p->>'box','inbox');skip:=greatest(0,least(coalesce((p->>'offset')::integer,0),100000));
  if box not in ('inbox','sent') then raise exception 'INVALID_BOX';end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]') into result from (
   select m.*,r.read_at,(select jsonb_agg(jsonb_build_object('email',q.email,'name',q.recipient_name,'read_at',q.read_at) order by q.recipient_name) from laundry_private.chat_recipients q where q.message_id=m.id) as recipients
   from laundry_private.chat_messages m left join laundry_private.chat_recipients r on r.message_id=m.id and r.email=who
   where (box='sent' and m.sender_email=who) or (box='inbox' and r.email=who)
   order by m.created_at desc,m.id desc limit 50 offset skip
  ) x;
  return jsonb_build_object('messages',result,'unread',(select count(*) from laundry_private.chat_recipients where email=who and read_at is null),
   'alerts',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from (select m.id,m.sender_name,m.body,m.lot_label from laundry_private.chat_messages m join laundry_private.chat_recipients r on r.message_id=m.id where r.email=who and r.read_at is null order by m.created_at desc,m.id desc limit 10) a));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function laundry_private.chat_api(text,jsonb) from public,anon,authenticated;
grant usage on schema laundry_private to authenticated;
grant execute on function laundry_private.chat_api(text,jsonb) to authenticated;
create function public.laundry_chat(p_action text,p jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select laundry_private.chat_api(p_action,p)$$;
revoke all on function public.laundry_chat(text,jsonb) from public,anon;
grant execute on function public.laundry_chat(text,jsonb) to authenticated;
