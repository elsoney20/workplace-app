-- =============================================================================
-- Phase 1 / Migration 4: chat functions (called from the app with .rpc())
-- Conversations are created only here, so membership is always consistent.
-- =============================================================================

-- Open (or reuse) the 1:1 chat with another employee. Returns the conversation id.
create or replace function public.get_or_create_direct_conversation(p_other_profile_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me  uuid := private.current_profile_id();
  v_key text;
  v_id  uuid;
begin
  if v_me is null then
    raise exception 'Not an active employee' using errcode = '42501';
  end if;
  if p_other_profile_id is null or p_other_profile_id = v_me then
    raise exception 'Choose another employee';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_other_profile_id and p.is_active) then
    raise exception 'Employee not found';
  end if;

  v_key := least(v_me::text, p_other_profile_id::text) || ':' || greatest(v_me::text, p_other_profile_id::text);

  insert into public.conversations (kind, direct_key, created_by)
  values ('direct', v_key, v_me)
  on conflict (direct_key) do nothing
  returning id into v_id;

  if v_id is null then
    select c.id into v_id from public.conversations c where c.direct_key = v_key;
  end if;

  insert into public.conversation_members (conversation_id, profile_id, role)
  values (v_id, v_me, 'member'), (v_id, p_other_profile_id, 'member')
  on conflict (conversation_id, profile_id) do nothing;

  return v_id;
end;
$$;

-- Create a group chat. The creator becomes its owner.
create or replace function public.create_group_conversation(p_title text, p_member_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
  v_id uuid;
begin
  if v_me is null then
    raise exception 'Not an active employee' using errcode = '42501';
  end if;
  if coalesce(length(trim(p_title)), 0) = 0 then
    raise exception 'A group chat needs a title';
  end if;

  insert into public.conversations (kind, title, created_by)
  values ('group', trim(p_title), v_me)
  returning id into v_id;

  insert into public.conversation_members (conversation_id, profile_id, role)
  values (v_id, v_me, 'owner');

  insert into public.conversation_members (conversation_id, profile_id, role)
  select v_id, p.id, 'member'
  from public.profiles p
  where p.id = any (coalesce(p_member_ids, '{}'))
    and p.is_active
    and p.id <> v_me
  on conflict (conversation_id, profile_id) do nothing;

  return v_id;
end;
$$;

-- Mark every message from others in a chat as delivered (✓) to me.
create or replace function public.mark_conversation_delivered(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
begin
  if not private.is_conversation_member(p_conversation_id) then
    raise exception 'Not a member of this conversation' using errcode = '42501';
  end if;

  insert into public.message_receipts (message_id, profile_id, delivered_at)
  select m.id, v_me, now()
  from public.messages m
  where m.conversation_id = p_conversation_id
    and m.sender_id <> v_me
    and m.deleted_at is null
  on conflict (message_id, profile_id) do nothing;
end;
$$;

-- Mark every message from others in a chat as seen (✓✓) by me, with the time.
create or replace function public.mark_conversation_seen(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
begin
  if not private.is_conversation_member(p_conversation_id) then
    raise exception 'Not a member of this conversation' using errcode = '42501';
  end if;

  insert into public.message_receipts (message_id, profile_id, delivered_at, seen_at)
  select m.id, v_me, now(), now()
  from public.messages m
  where m.conversation_id = p_conversation_id
    and m.sender_id <> v_me
    and m.deleted_at is null
  on conflict (message_id, profile_id)
    do update set seen_at = coalesce(public.message_receipts.seen_at, now());

  update public.conversation_members
  set last_read_at = now()
  where conversation_id = p_conversation_id
    and profile_id = v_me;
end;
$$;

revoke execute on function public.get_or_create_direct_conversation(uuid) from public, anon;
revoke execute on function public.create_group_conversation(text, uuid[]) from public, anon;
revoke execute on function public.mark_conversation_delivered(uuid) from public, anon;
revoke execute on function public.mark_conversation_seen(uuid) from public, anon;
grant execute on function public.get_or_create_direct_conversation(uuid) to authenticated;
grant execute on function public.create_group_conversation(text, uuid[]) to authenticated;
grant execute on function public.mark_conversation_delivered(uuid) to authenticated;
grant execute on function public.mark_conversation_seen(uuid) to authenticated;
