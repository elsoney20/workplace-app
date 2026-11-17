-- =============================================================================
-- Phase 5: realtime chat
-- Tables, membership rules and receipts already exist (Phase 1). This adds:
--   * read functions for the chat list, messages and "seen by" details
--   * attachment path guard (chat-media/<conversation_id>/...)
--   * leaving / renaming group chats
--   * Realtime Authorization for typing + online presence channels, so only
--     chat members can join a chat's live channel (no admin exception).
-- PRIVACY: every function below is SECURITY INVOKER (RLS = members only),
-- except where noted, and none has an admin exception.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Attachments must be in their chat's folder.
-- -----------------------------------------------------------------------------
create or replace function private.guard_message_attachment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.is_trusted_role()
     and split_part(new.storage_path, '/', 1)
         <> (select m.conversation_id::text from public.messages m where m.id = new.message_id) then
    raise exception 'Attachment path must start with the conversation id';
  end if;
  return new;
end;
$$;

create trigger message_attachments_guard
  before insert or update on public.message_attachments
  for each row execute function private.guard_message_attachment();

-- -----------------------------------------------------------------------------
-- Chat list
-- -----------------------------------------------------------------------------
create or replace function public.list_conversations()
returns table (
  id               uuid,
  kind             public.conversation_kind,
  title            text,
  other_person     jsonb,
  member_count     integer,
  my_role          public.conversation_role,
  muted            boolean,
  last_message     jsonb,
  last_message_at  timestamptz,
  unread_count     integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  with me as (select private.current_profile_id() as id)
  select
    c.id,
    c.kind,
    c.title,
    case when c.kind = 'direct' then (
      select private.person_card(cm.profile_id)
      from public.conversation_members cm, me
      where cm.conversation_id = c.id and cm.profile_id <> me.id
      limit 1
    ) end,
    (select count(*)::integer from public.conversation_members cm where cm.conversation_id = c.id),
    mine.role,
    mine.muted,
    (
      select jsonb_build_object(
        'id', m.id, 'body', m.body, 'sender_id', m.sender_id,
        'sender_name', (select p.full_name from public.profiles p where p.id = m.sender_id),
        'deleted', m.deleted_at is not null,
        'has_attachment', exists (select 1 from public.message_attachments a where a.message_id = m.id),
        'created_at', m.created_at
      )
      from public.messages m
      where m.conversation_id = c.id
      order by m.created_at desc
      limit 1
    ),
    c.last_message_at,
    (
      select count(*)::integer
      from public.messages m, me
      where m.conversation_id = c.id
        and m.sender_id <> me.id
        and m.deleted_at is null
        and (mine.last_read_at is null or m.created_at > mine.last_read_at)
    )
  from public.conversations c
  join public.conversation_members mine
    on mine.conversation_id = c.id and mine.profile_id = private.current_profile_id()
  order by coalesce(c.last_message_at, c.created_at) desc;
$$;

-- -----------------------------------------------------------------------------
-- Messages (newest first, paged with p_before)
-- -----------------------------------------------------------------------------
create or replace function public.get_messages(
  p_conversation_id uuid,
  p_before          timestamptz default null,
  p_limit           integer default 40
)
returns table (
  id               uuid,
  conversation_id  uuid,
  sender           jsonb,
  body             text,
  reply_to         jsonb,
  created_at       timestamptz,
  edited_at        timestamptz,
  deleted_at       timestamptz,
  attachments      jsonb,
  reactions        jsonb,
  recipient_count  integer,
  delivered_count  integer,
  seen_count       integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  with page as (
    select m.*
    from public.messages m
    where m.conversation_id = p_conversation_id
      and (p_before is null or m.created_at < p_before)
    order by m.created_at desc
    limit least(greatest(coalesce(p_limit, 40), 1), 100)
  ),
  members as (
    select count(*)::integer as n
    from public.conversation_members cm
    where cm.conversation_id = p_conversation_id
  )
  select
    m.id,
    m.conversation_id,
    private.person_card(m.sender_id),
    m.body,
    (
      select jsonb_build_object(
        'id', r.id, 'body', left(r.body, 200), 'deleted', r.deleted_at is not null,
        'sender_name', (select p.full_name from public.profiles p where p.id = r.sender_id)
      )
      from public.messages r where r.id = m.reply_to_id
    ),
    m.created_at,
    m.edited_at,
    m.deleted_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'storage_path', a.storage_path, 'kind', a.kind,
               'mime_type', a.mime_type, 'file_name', a.file_name,
               'size_bytes', a.size_bytes, 'width', a.width, 'height', a.height
             ) order by a.created_at)
      from public.message_attachments a where a.message_id = m.id
    ), '[]'::jsonb),
    -- {"👍": ["profile-id", ...]}
    coalesce((
      select jsonb_object_agg(x.emoji, x.people)
      from (
        select mr.emoji, jsonb_agg(mr.profile_id order by mr.created_at) as people
        from public.message_reactions mr
        where mr.message_id = m.id
        group by mr.emoji
      ) x
    ), '{}'::jsonb),
    greatest((select n from members) - 1, 0),
    (select count(*)::integer from public.message_receipts rc where rc.message_id = m.id),
    (select count(*)::integer from public.message_receipts rc where rc.message_id = m.id and rc.seen_at is not null)
  from page m
  order by m.created_at desc;
$$;

-- Who received / saw one message and when (✓ / ✓✓ details).
create or replace function public.get_message_receipts(p_message_id uuid)
returns table (person jsonb, delivered_at timestamptz, seen_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select private.person_card(cm.profile_id), rc.delivered_at, rc.seen_at
  from public.messages m
  join public.conversation_members cm on cm.conversation_id = m.conversation_id
  left join public.message_receipts rc on rc.message_id = m.id and rc.profile_id = cm.profile_id
  where m.id = p_message_id
    and cm.profile_id <> m.sender_id
  order by rc.seen_at desc nulls last, rc.delivered_at desc nulls last;
$$;

create or replace function public.get_conversation_members(p_conversation_id uuid)
returns table (person jsonb, role public.conversation_role, joined_at timestamptz, last_read_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select private.person_card(cm.profile_id), cm.role, cm.joined_at, cm.last_read_at
  from public.conversation_members cm
  join public.profiles p on p.id = cm.profile_id
  where cm.conversation_id = p_conversation_id
  order by (cm.role = 'owner') desc, lower(p.full_name);
$$;

-- -----------------------------------------------------------------------------
-- Leaving a group chat: if the owner leaves, the longest member becomes owner.
-- SECURITY DEFINER because members cannot change roles themselves.
-- -----------------------------------------------------------------------------
create or replace function public.leave_group_conversation(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me   uuid := private.current_profile_id();
  v_role public.conversation_role;
begin
  select cm.role into v_role
  from public.conversation_members cm
  join public.conversations c on c.id = cm.conversation_id and c.kind = 'group'
  where cm.conversation_id = p_conversation_id and cm.profile_id = v_me;

  if v_role is null then
    raise exception 'Not a member of this group chat' using errcode = '42501';
  end if;

  delete from public.conversation_members
  where conversation_id = p_conversation_id and profile_id = v_me;

  if v_role = 'owner' and not exists (
    select 1 from public.conversation_members
    where conversation_id = p_conversation_id and role = 'owner'
  ) then
    update public.conversation_members
    set role = 'owner'
    where conversation_id = p_conversation_id
      and profile_id = (
        select profile_id from public.conversation_members
        where conversation_id = p_conversation_id
        order by joined_at
        limit 1
      );
  end if;
end;
$$;

revoke execute on function
  public.list_conversations(),
  public.get_messages(uuid, timestamptz, integer),
  public.get_message_receipts(uuid),
  public.get_conversation_members(uuid),
  public.leave_group_conversation(uuid)
from public, anon;
grant execute on function
  public.list_conversations(),
  public.get_messages(uuid, timestamptz, integer),
  public.get_message_receipts(uuid),
  public.get_conversation_members(uuid),
  public.leave_group_conversation(uuid)
to authenticated;

-- -----------------------------------------------------------------------------
-- Realtime Authorization (Supabase only; skipped on plain Postgres in tests).
--   chat:<conversation_id>  typing indicator  -> members only
--   presence:online          who is online     -> any active employee
-- -----------------------------------------------------------------------------
create or replace function private.can_use_realtime_topic(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_profile_id() is not null
     and (
       p_topic = 'presence:online'
       or (p_topic like 'chat:%'
           and private.is_conversation_member(private.try_uuid(substr(p_topic, 6))))
     );
$$;

revoke all on function private.can_use_realtime_topic(text) from public;
grant execute on function private.can_use_realtime_topic(text) to authenticated, service_role;

do $$
begin
  if exists (select 1 from pg_tables where schemaname = 'realtime' and tablename = 'messages') then
    execute 'drop policy if exists workplace_realtime_read on realtime.messages';
    execute 'drop policy if exists workplace_realtime_write on realtime.messages';
    execute $p$
      create policy workplace_realtime_read on realtime.messages
        for select to authenticated
        using (private.can_use_realtime_topic(realtime.topic()))
    $p$;
    execute $p$
      create policy workplace_realtime_write on realtime.messages
        for insert to authenticated
        with check (private.can_use_realtime_topic(realtime.topic()))
    $p$;
  end if;
end;
$$;
