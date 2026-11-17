-- =============================================================================
-- Phase 1 / Migration 3: Row Level Security policies + guard triggers
-- RLS decides WHICH ROWS a user may touch; guard triggers decide WHICH COLUMNS
-- a user may change (e.g. an employee cannot make themselves admin).
-- =============================================================================

-- Enable RLS on every table. With RLS on and no policy, access is denied.
alter table public.departments          enable row level security;
alter table public.profiles             enable row level security;
alter table public.groups               enable row level security;
alter table public.group_members        enable row level security;
alter table public.posts                enable row level security;
alter table public.post_attachments     enable row level security;
alter table public.comments             enable row level security;
alter table public.reactions            enable row level security;
alter table public.announcement_views   enable row level security;
alter table public.mentions             enable row level security;
alter table public.hashtags             enable row level security;
alter table public.post_hashtags        enable row level security;
alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;
alter table public.message_attachments  enable row level security;
alter table public.message_receipts     enable row level security;
alter table public.message_reactions    enable row level security;
alter table public.reports              enable row level security;
alter table public.notifications        enable row level security;

-- The app never talks to the database while logged out.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;

-- =============================================================================
-- Departments
-- =============================================================================
create policy departments_select on public.departments
  for select to authenticated
  using (private.current_profile_id() is not null);

create policy departments_admin_insert on public.departments
  for insert to authenticated with check (private.is_admin());
create policy departments_admin_update on public.departments
  for update to authenticated using (private.is_admin()) with check (private.is_admin());
create policy departments_admin_delete on public.departments
  for delete to authenticated using (private.is_admin());

-- =============================================================================
-- Profiles
-- Phone numbers are NOT readable from this table by the app (column grant
-- below); they are served through public.profile_contacts, which applies each
-- employee's phone_visibility setting.
-- =============================================================================
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    private.current_profile_id() is not null
    and (is_active or private.is_admin())
  );

create policy profiles_admin_insert on public.profiles
  for insert to authenticated with check (private.is_admin());

create policy profiles_update_self_or_admin on public.profiles
  for update to authenticated
  using (id = private.current_profile_id() or private.is_admin())
  with check (id = private.current_profile_id() or private.is_admin());

create policy profiles_admin_delete on public.profiles
  for delete to authenticated using (private.is_admin() and id <> private.current_profile_id());

revoke select on public.profiles from authenticated;
grant select (
  id, full_name, department_id, job_title, role, is_active, deactivated_at,
  phone_visibility, avatar_path, bio, locale, created_at, updated_at
) on public.profiles to authenticated;

-- Phone numbers, filtered by each person's visibility choice.
create or replace view public.profile_contacts
with (security_barrier = true)
as
  select p.id as profile_id, p.phone
  from public.profiles p
  where private.current_profile_id() is not null
    and p.is_active
    and (
      p.id = private.current_profile_id()
      or private.is_admin()
      or p.phone_visibility = 'everyone'
      or (p.phone_visibility = 'managers' and private.is_manager_or_admin())
    );

revoke all on public.profile_contacts from anon, public;
grant select on public.profile_contacts to authenticated;

-- Employees may edit only their own avatar, bio, language and phone visibility.
create or replace function private.guard_profile_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_trusted_role() then
    null;
  elsif private.is_admin() then
    -- An admin cannot lock themselves out by accident.
    if new.id = private.current_profile_id()
       and (new.role is distinct from old.role or new.is_active is distinct from old.is_active) then
      raise exception 'Admins cannot change their own role or active status';
    end if;
  else
    if new.phone          is distinct from old.phone
    or new.full_name      is distinct from old.full_name
    or new.department_id  is distinct from old.department_id
    or new.job_title      is distinct from old.job_title
    or new.role           is distinct from old.role
    or new.is_active      is distinct from old.is_active
    or new.deactivated_at is distinct from old.deactivated_at
    or new.auth_user_id   is distinct from old.auth_user_id then
      raise exception 'Only an admin can change these profile fields';
    end if;
  end if;

  if new.is_active is distinct from old.is_active then
    new.deactivated_at := case when new.is_active then null else now() end;
  end if;
  return new;
end;
$$;

create trigger profiles_guard_update before update on public.profiles
  for each row execute function private.guard_profile_update();

-- =============================================================================
-- Groups & members
-- =============================================================================
create policy groups_select on public.groups
  for select to authenticated using (private.can_view_group(id));

create policy groups_insert_managers on public.groups
  for insert to authenticated
  with check (private.is_manager_or_admin() and created_by = private.current_profile_id());

create policy groups_update_moderators on public.groups
  for update to authenticated
  using (private.can_moderate_group(id)) with check (private.can_moderate_group(id));

create policy groups_delete_admin on public.groups
  for delete to authenticated using (private.is_admin());

create or replace function private.guard_group_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.is_trusted_role() and not private.is_admin() then
    if tg_op = 'INSERT' and new.department_id is not null then
      raise exception 'Only an admin can create a department group';
    end if;
    if tg_op = 'UPDATE' and new.department_id is distinct from old.department_id then
      raise exception 'Only an admin can change a group''s department';
    end if;
  end if;
  return new;
end;
$$;

create trigger groups_guard_write before insert or update on public.groups
  for each row execute function private.guard_group_write();

-- The creator becomes the group's owner.
create or replace function private.add_group_creator()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.created_by is not null then
    insert into public.group_members (group_id, profile_id, role)
    values (new.id, new.created_by, 'owner')
    on conflict (group_id, profile_id) do update set role = 'owner';
  end if;
  return new;
end;
$$;

create trigger groups_add_creator after insert on public.groups
  for each row execute function private.add_group_creator();

create policy group_members_select on public.group_members
  for select to authenticated using (private.can_view_group(group_id));

-- Join a public group yourself, or be added by a moderator (private = invite).
create policy group_members_insert on public.group_members
  for insert to authenticated
  with check (
    private.can_moderate_group(group_id)
    or (
      profile_id = private.current_profile_id()
      and role = 'member'
      and exists (select 1 from public.groups g where g.id = group_id and g.privacy = 'public')
    )
  );

create policy group_members_update on public.group_members
  for update to authenticated
  using (profile_id = private.current_profile_id() or private.can_moderate_group(group_id))
  with check (profile_id = private.current_profile_id() or private.can_moderate_group(group_id));

-- Leave yourself, or be removed by a moderator.
create policy group_members_delete on public.group_members
  for delete to authenticated
  using (profile_id = private.current_profile_id() or private.can_moderate_group(group_id));

create or replace function private.guard_group_member_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_trusted_role() then
    return new;
  end if;
  if new.group_id is distinct from old.group_id or new.profile_id is distinct from old.profile_id then
    raise exception 'Membership keys cannot change';
  end if;
  if new.role is distinct from old.role then
    if not private.can_moderate_group(new.group_id) then
      raise exception 'Only group moderators can change roles';
    end if;
    if (new.role = 'owner' or old.role = 'owner')
       and not (private.is_admin() or private.group_role_of(new.group_id) = 'owner') then
      raise exception 'Only the owner or an admin can change ownership';
    end if;
  end if;
  if new.muted is distinct from old.muted and new.profile_id <> private.current_profile_id() then
    raise exception 'You can only mute a group for yourself';
  end if;
  return new;
end;
$$;

create trigger group_members_guard_update before update on public.group_members
  for each row execute function private.guard_group_member_update();

-- Department groups: created automatically, members follow profiles.department_id.
create or replace function private.create_department_group()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.groups (name, privacy, department_id)
  values (coalesce(nullif(new.name_en, ''), new.name_ar), 'private', new.id);
  return new;
end;
$$;

create trigger departments_create_group after insert on public.departments
  for each row execute function private.create_department_group();

create or replace function private.sync_department_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.department_id is distinct from new.department_id and old.department_id is not null then
    delete from public.group_members gm
    using public.groups g
    where g.department_id = old.department_id
      and gm.group_id = g.id
      and gm.profile_id = new.id;
  end if;
  if new.department_id is not null then
    insert into public.group_members (group_id, profile_id, role)
    select g.id, new.id, 'member'
    from public.groups g
    where g.department_id = new.department_id
    on conflict (group_id, profile_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger profiles_sync_department after insert or update of department_id on public.profiles
  for each row execute function private.sync_department_membership();

-- =============================================================================
-- Posts
-- =============================================================================
create policy posts_select on public.posts
  for select to authenticated using (private.can_view_post(id));

create policy posts_insert on public.posts
  for insert to authenticated
  with check (author_id = private.current_profile_id() and private.can_post_in_feed(group_id));

create policy posts_update on public.posts
  for update to authenticated
  using (
    private.can_view_post(id)
    and (author_id = private.current_profile_id() or private.can_moderate_feed(group_id))
  )
  with check (author_id = private.current_profile_id() or private.can_moderate_feed(group_id));

-- Hard delete is admin-only; everyone else soft-deletes (sets deleted_at).
create policy posts_delete_admin on public.posts
  for delete to authenticated using (private.is_admin());

create or replace function private.guard_post_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
begin
  if private.is_trusted_role() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if (new.is_pinned or new.is_announcement or new.comments_locked)
       and not private.can_moderate_feed(new.group_id) then
      raise exception 'Only moderators can pin, announce or lock comments';
    end if;
    new.deleted_at := null;
    new.deleted_by := null;
    new.edited_at := null;
    return new;
  end if;

  if new.author_id is distinct from old.author_id
  or new.group_id is distinct from old.group_id
  or new.created_at is distinct from old.created_at then
    raise exception 'author, group and creation time cannot change';
  end if;

  if (new.is_pinned is distinct from old.is_pinned
      or new.is_announcement is distinct from old.is_announcement
      or new.comments_locked is distinct from old.comments_locked)
     and not private.can_moderate_feed(new.group_id) then
    raise exception 'Only moderators can pin, announce or lock comments';
  end if;

  if new.body is distinct from old.body then
    if old.author_id <> v_me then
      raise exception 'Only the author can edit a post';
    end if;
    new.edited_at := now();
  end if;

  if new.deleted_at is distinct from old.deleted_at then
    if new.deleted_at is null and not private.can_moderate_feed(new.group_id) then
      raise exception 'Only moderators can restore a deleted post';
    end if;
    new.deleted_by := case when new.deleted_at is null then null else v_me end;
  elsif new.deleted_by is distinct from old.deleted_by then
    raise exception 'deleted_by is set automatically';
  end if;

  return new;
end;
$$;

create trigger posts_guard_write before insert or update on public.posts
  for each row execute function private.guard_post_write();

-- Attachments follow their post.
create policy post_attachments_select on public.post_attachments
  for select to authenticated using (private.can_view_post(post_id));

create policy post_attachments_insert on public.post_attachments
  for insert to authenticated
  with check (exists (
    select 1 from public.posts p
    where p.id = post_id and p.author_id = private.current_profile_id() and p.deleted_at is null
  ));

create policy post_attachments_delete on public.post_attachments
  for delete to authenticated
  using (
    exists (select 1 from public.posts p where p.id = post_id and p.author_id = private.current_profile_id())
    or private.can_moderate_post(post_id)
  );

-- =============================================================================
-- Comments
-- =============================================================================
create policy comments_select on public.comments
  for select to authenticated
  using (
    private.can_view_post(post_id)
    and (deleted_at is null or private.can_moderate_post(post_id))
  );

create policy comments_insert on public.comments
  for insert to authenticated
  with check (author_id = private.current_profile_id() and private.can_view_post(post_id));

create policy comments_update on public.comments
  for update to authenticated
  using (
    private.can_view_post(post_id)
    and (author_id = private.current_profile_id() or private.can_moderate_post(post_id))
  )
  with check (author_id = private.current_profile_id() or private.can_moderate_post(post_id));

create policy comments_delete_admin on public.comments
  for delete to authenticated using (private.is_admin());

create or replace function private.guard_comment_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
begin
  if private.is_trusted_role() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if exists (select 1 from public.posts p where p.id = new.post_id and (p.comments_locked or p.deleted_at is not null))
       and not private.can_moderate_post(new.post_id) then
      raise exception 'Comments are locked on this post';
    end if;
    if new.parent_id is not null
       and not exists (select 1 from public.comments c where c.id = new.parent_id and c.post_id = new.post_id) then
      raise exception 'A reply must belong to the same post';
    end if;
    new.deleted_at := null;
    new.deleted_by := null;
    new.edited_at := null;
    return new;
  end if;

  if new.post_id is distinct from old.post_id
  or new.author_id is distinct from old.author_id
  or new.parent_id is distinct from old.parent_id
  or new.created_at is distinct from old.created_at then
    raise exception 'post, author, parent and creation time cannot change';
  end if;

  if new.body is distinct from old.body then
    if old.author_id <> v_me then
      raise exception 'Only the author can edit a comment';
    end if;
    new.edited_at := now();
  end if;

  if new.deleted_at is distinct from old.deleted_at then
    if new.deleted_at is null and not private.can_moderate_post(new.post_id) then
      raise exception 'Only moderators can restore a deleted comment';
    end if;
    new.deleted_by := case when new.deleted_at is null then null else v_me end;
  elsif new.deleted_by is distinct from old.deleted_by then
    raise exception 'deleted_by is set automatically';
  end if;

  return new;
end;
$$;

create trigger comments_guard_write before insert or update on public.comments
  for each row execute function private.guard_comment_write();

-- =============================================================================
-- Reactions, seen-by, mentions, hashtags
-- =============================================================================
create policy reactions_select on public.reactions
  for select to authenticated
  using (private.can_view_post(coalesce(post_id, private.post_of_comment(comment_id))));

create policy reactions_insert on public.reactions
  for insert to authenticated
  with check (
    profile_id = private.current_profile_id()
    and private.can_view_post(coalesce(post_id, private.post_of_comment(comment_id)))
  );

create policy reactions_update_own on public.reactions
  for update to authenticated
  using (profile_id = private.current_profile_id())
  with check (profile_id = private.current_profile_id());

create policy reactions_delete_own on public.reactions
  for delete to authenticated using (profile_id = private.current_profile_id());

create or replace function private.guard_reaction_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.is_trusted_role()
     and (new.post_id is distinct from old.post_id
          or new.comment_id is distinct from old.comment_id
          or new.profile_id is distinct from old.profile_id) then
    raise exception 'Only the emoji of a reaction can change';
  end if;
  return new;
end;
$$;

create trigger reactions_guard_update before update on public.reactions
  for each row execute function private.guard_reaction_update();

-- Seen-by list: visible to the viewer themself, the post's author and moderators.
create policy announcement_views_select on public.announcement_views
  for select to authenticated
  using (
    profile_id = private.current_profile_id()
    or (
      private.can_view_post(post_id)
      and (
        exists (select 1 from public.posts p where p.id = post_id and p.author_id = private.current_profile_id())
        or private.can_moderate_post(post_id)
      )
    )
  );

create policy announcement_views_insert_self on public.announcement_views
  for insert to authenticated
  with check (
    profile_id = private.current_profile_id()
    and private.can_view_post(post_id)
    and exists (select 1 from public.posts p where p.id = post_id and p.is_announcement)
  );

create policy mentions_select on public.mentions
  for select to authenticated
  using (private.can_view_post(coalesce(post_id, private.post_of_comment(comment_id))));

-- Only the author of the post/comment can record who they mentioned.
create policy mentions_insert_author on public.mentions
  for insert to authenticated
  with check (
    (post_id is not null and exists (
      select 1 from public.posts p where p.id = post_id and p.author_id = private.current_profile_id()))
    or (comment_id is not null and exists (
      select 1 from public.comments c where c.id = comment_id and c.author_id = private.current_profile_id()))
  );

create policy mentions_delete_author on public.mentions
  for delete to authenticated
  using (
    (post_id is not null and exists (
      select 1 from public.posts p where p.id = post_id and p.author_id = private.current_profile_id()))
    or (comment_id is not null and exists (
      select 1 from public.comments c where c.id = comment_id and c.author_id = private.current_profile_id()))
  );

create policy hashtags_select on public.hashtags
  for select to authenticated using (private.current_profile_id() is not null);

create policy hashtags_insert on public.hashtags
  for insert to authenticated with check (private.current_profile_id() is not null);

create policy post_hashtags_select on public.post_hashtags
  for select to authenticated using (private.can_view_post(post_id));

create policy post_hashtags_insert_author on public.post_hashtags
  for insert to authenticated
  with check (exists (
    select 1 from public.posts p where p.id = post_id and p.author_id = private.current_profile_id()));

create policy post_hashtags_delete_author on public.post_hashtags
  for delete to authenticated
  using (exists (
    select 1 from public.posts p where p.id = post_id and p.author_id = private.current_profile_id()));

-- =============================================================================
-- Chat. PRIVACY: every policy requires conversation membership.
-- No admin exception anywhere in this section.
-- New conversations are created only through the functions at the end
-- (get_or_create_direct_conversation / create_group_conversation).
-- =============================================================================
create policy conversations_select_members on public.conversations
  for select to authenticated using (private.is_conversation_member(id));

create policy conversations_update_owner on public.conversations
  for update to authenticated
  using (kind = 'group' and private.conversation_role_of(id) = 'owner')
  with check (kind = 'group' and private.conversation_role_of(id) = 'owner');

create or replace function private.guard_conversation_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.is_trusted_role()
     and (new.kind is distinct from old.kind
          or new.direct_key is distinct from old.direct_key
          or new.created_by is distinct from old.created_by
          or new.last_message_at is distinct from old.last_message_at) then
    raise exception 'Only the title of a conversation can change';
  end if;
  return new;
end;
$$;

create trigger conversations_guard_update before update on public.conversations
  for each row execute function private.guard_conversation_update();

create policy conversation_members_select on public.conversation_members
  for select to authenticated using (private.is_conversation_member(conversation_id));

-- The owner of a group chat can add people (only active employees).
create policy conversation_members_insert_owner on public.conversation_members
  for insert to authenticated
  with check (
    private.conversation_role_of(conversation_id) = 'owner'
    and role = 'member'
    and exists (select 1 from public.conversations c where c.id = conversation_id and c.kind = 'group')
    and exists (select 1 from public.profiles p where p.id = profile_id and p.is_active)
  );

create policy conversation_members_update_self on public.conversation_members
  for update to authenticated
  using (profile_id = private.current_profile_id())
  with check (profile_id = private.current_profile_id());

create policy conversation_members_delete on public.conversation_members
  for delete to authenticated
  using (
    exists (select 1 from public.conversations c where c.id = conversation_id and c.kind = 'group')
    and (
      profile_id = private.current_profile_id()
      or private.conversation_role_of(conversation_id) = 'owner'
    )
  );

create or replace function private.guard_conversation_member_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.is_trusted_role()
     and (new.conversation_id is distinct from old.conversation_id
          or new.profile_id is distinct from old.profile_id
          or new.role is distinct from old.role
          or new.joined_at is distinct from old.joined_at) then
    raise exception 'You can only change mute and read position';
  end if;
  return new;
end;
$$;

create trigger conversation_members_guard_update before update on public.conversation_members
  for each row execute function private.guard_conversation_member_update();

create policy messages_select_members on public.messages
  for select to authenticated using (private.is_conversation_member(conversation_id));

create policy messages_insert_members on public.messages
  for insert to authenticated
  with check (
    sender_id = private.current_profile_id()
    and private.is_conversation_member(conversation_id)
  );

create policy messages_update_sender on public.messages
  for update to authenticated
  using (sender_id = private.current_profile_id() and private.is_conversation_member(conversation_id))
  with check (sender_id = private.current_profile_id());

create or replace function private.guard_message_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_trusted_role() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.reply_to_id is not null and not exists (
      select 1 from public.messages m where m.id = new.reply_to_id and m.conversation_id = new.conversation_id) then
      raise exception 'Reply must be in the same conversation';
    end if;
    new.edited_at := null;
    new.deleted_at := null;
    new.created_at := now();
    return new;
  end if;

  if new.conversation_id is distinct from old.conversation_id
  or new.sender_id is distinct from old.sender_id
  or new.created_at is distinct from old.created_at
  or new.reply_to_id is distinct from old.reply_to_id then
    raise exception 'Only the text of a message can change';
  end if;

  if old.deleted_at is not null then
    raise exception 'A deleted message cannot be changed';
  end if;

  if new.deleted_at is not null then
    -- "Delete for everyone": the text is wiped so nobody can read it any more.
    new.deleted_at := now();
    new.body := '';
  elsif new.body is distinct from old.body then
    new.edited_at := now();
  end if;
  return new;
end;
$$;

create trigger messages_guard_write before insert or update on public.messages
  for each row execute function private.guard_message_write();

-- Keep the chat list ordered by latest message.
create or replace function private.touch_conversation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversations
  set last_message_at = new.created_at
  where id = new.conversation_id
    and (last_message_at is null or last_message_at < new.created_at);
  return new;
end;
$$;

create trigger messages_touch_conversation after insert on public.messages
  for each row execute function private.touch_conversation();

-- When a message is deleted for everyone, its attachment records go too.
create or replace function private.purge_deleted_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.message_attachments where message_id = new.id;
  delete from public.message_reactions where message_id = new.id;
  return new;
end;
$$;

create trigger messages_purge_deleted after update of deleted_at on public.messages
  for each row when (old.deleted_at is null and new.deleted_at is not null)
  execute function private.purge_deleted_message();

create policy message_attachments_select on public.message_attachments
  for select to authenticated
  using (private.is_conversation_member(private.conversation_of_message(message_id)));

create policy message_attachments_insert_sender on public.message_attachments
  for insert to authenticated
  with check (exists (
    select 1 from public.messages m
    where m.id = message_id
      and m.sender_id = private.current_profile_id()
      and m.deleted_at is null
      and private.is_conversation_member(m.conversation_id)
  ));

-- Everyone in the chat can see who received / saw each message and when.
create policy message_receipts_select on public.message_receipts
  for select to authenticated
  using (private.is_conversation_member(private.conversation_of_message(message_id)));

-- You record receipts only for yourself, only for other people's messages.
create policy message_receipts_insert_self on public.message_receipts
  for insert to authenticated
  with check (
    profile_id = private.current_profile_id()
    and exists (
      select 1 from public.messages m
      where m.id = message_id
        and m.sender_id <> private.current_profile_id()
        and private.is_conversation_member(m.conversation_id)
    )
  );

create policy message_receipts_update_self on public.message_receipts
  for update to authenticated
  using (profile_id = private.current_profile_id())
  with check (profile_id = private.current_profile_id());

create or replace function private.guard_receipt_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_trusted_role() then
    return new;
  end if;
  if new.message_id is distinct from old.message_id
  or new.profile_id is distinct from old.profile_id
  or new.delivered_at is distinct from old.delivered_at then
    raise exception 'Only seen_at can change';
  end if;
  -- "Seen" is recorded once and never moved or removed.
  if old.seen_at is not null then
    new.seen_at := old.seen_at;
  elsif new.seen_at is not null then
    new.seen_at := now();
  end if;
  return new;
end;
$$;

create trigger message_receipts_guard_update before update on public.message_receipts
  for each row execute function private.guard_receipt_update();

create policy message_reactions_select on public.message_reactions
  for select to authenticated
  using (private.is_conversation_member(private.conversation_of_message(message_id)));

create policy message_reactions_insert_self on public.message_reactions
  for insert to authenticated
  with check (
    profile_id = private.current_profile_id()
    and private.is_conversation_member(private.conversation_of_message(message_id))
  );

create policy message_reactions_delete_self on public.message_reactions
  for delete to authenticated using (profile_id = private.current_profile_id());

-- =============================================================================
-- Reports (posts & comments only; private chats are never reportable to admins)
-- =============================================================================
create policy reports_select on public.reports
  for select to authenticated
  using (
    reporter_id = private.current_profile_id()
    or private.can_moderate_post(coalesce(post_id, private.post_of_comment(comment_id)))
  );

create policy reports_insert on public.reports
  for insert to authenticated
  with check (
    reporter_id = private.current_profile_id()
    and status = 'open'
    and handled_by is null
    and private.can_view_post(coalesce(post_id, private.post_of_comment(comment_id)))
  );

create policy reports_update_moderators on public.reports
  for update to authenticated
  using (private.can_moderate_post(coalesce(post_id, private.post_of_comment(comment_id))))
  with check (private.can_moderate_post(coalesce(post_id, private.post_of_comment(comment_id))));

create or replace function private.guard_report_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_trusted_role() then
    return new;
  end if;
  if new.reporter_id is distinct from old.reporter_id
  or new.post_id is distinct from old.post_id
  or new.comment_id is distinct from old.comment_id
  or new.reason is distinct from old.reason
  or new.created_at is distinct from old.created_at then
    raise exception 'Only the status of a report can change';
  end if;
  if new.status is distinct from old.status then
    new.handled_by := private.current_profile_id();
    new.handled_at := now();
  end if;
  return new;
end;
$$;

create trigger reports_guard_update before update on public.reports
  for each row execute function private.guard_report_update();

-- =============================================================================
-- Notifications: each person sees only their own. They are created by the
-- server (triggers / functions in later phases), never directly by the app.
-- =============================================================================
create policy notifications_select_own on public.notifications
  for select to authenticated using (recipient_id = private.current_profile_id());

create policy notifications_update_own on public.notifications
  for update to authenticated
  using (recipient_id = private.current_profile_id())
  with check (recipient_id = private.current_profile_id());

create policy notifications_delete_own on public.notifications
  for delete to authenticated using (recipient_id = private.current_profile_id());

revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;
