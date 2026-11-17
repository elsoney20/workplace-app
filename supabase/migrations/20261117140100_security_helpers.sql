-- =============================================================================
-- Phase 1 / Migration 2: security helper functions
-- They live in a "private" schema that the API does not expose, and run as
-- SECURITY DEFINER so policies can look up roles without recursive RLS checks.
--
-- Golden rule: private.current_profile_id() returns NULL for anyone who is not
-- an ACTIVE, registered employee. Every policy depends on it, so deactivating
-- an employee removes all access immediately, even with a still-valid session.
-- =============================================================================

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- True when the current database role is a trusted server-side role
-- (migrations, dashboard, service key, auth hooks), not an app user.
create or replace function private.is_trusted_role()
returns boolean
language sql
stable
set search_path = ''
as $$
  select current_user not in ('authenticated', 'anon');
$$;

create or replace function private.current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id
  from public.profiles p
  where p.auth_user_id = auth.uid()
    and p.is_active;
$$;

create or replace function private.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  where p.auth_user_id = auth.uid()
    and p.is_active;
$$;

create or replace function private.is_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(private.current_app_role() = 'admin', false);
$$;

create or replace function private.is_manager_or_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(private.current_app_role() in ('admin', 'manager'), false);
$$;

-- Role of the current user inside a group (null = not a member).
create or replace function private.group_role_of(p_group_id uuid)
returns public.group_role
language sql
stable
security definer
set search_path = ''
as $$
  select gm.role
  from public.group_members gm
  where gm.group_id = p_group_id
    and gm.profile_id = private.current_profile_id();
$$;

create or replace function private.is_group_member(p_group_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.group_role_of(p_group_id) is not null;
$$;

-- Admin, group owner/moderator, or manager of the group's department.
create or replace function private.can_moderate_group(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_profile_id() is not null
     and (
       private.is_admin()
       or private.group_role_of(p_group_id) in ('owner', 'moderator')
       or exists (
         select 1
         from public.groups g
         join public.departments d on d.id = g.department_id
         where g.id = p_group_id
           and d.manager_id = private.current_profile_id()
       )
     );
$$;

-- Public groups: every active employee. Private groups: members (and admins,
-- who moderate all company content; note this never applies to chats).
create or replace function private.can_view_group(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_profile_id() is not null
     and exists (
       select 1
       from public.groups g
       where g.id = p_group_id
         and (
           g.privacy = 'public'
           or private.is_group_member(g.id)
           or private.can_moderate_group(g.id)
         )
     );
$$;

-- Who may moderate a feed: the company feed (group null) = admins only.
create or replace function private.can_moderate_feed(p_group_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when p_group_id is null then private.is_admin()
    else private.can_moderate_group(p_group_id)
  end;
$$;

-- Who may post into a feed: company feed = any active employee;
-- group feed = members (or moderators).
create or replace function private.can_post_in_feed(p_group_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.current_profile_id() is not null
     and (
       p_group_id is null
       or private.is_group_member(p_group_id)
       or private.can_moderate_group(p_group_id)
     );
$$;

create or replace function private.can_view_post(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_profile_id() is not null
     and exists (
       select 1
       from public.posts p
       where p.id = p_post_id
         and (p.group_id is null or private.can_view_group(p.group_id))
         and (p.deleted_at is null or private.can_moderate_feed(p.group_id))
     );
$$;

create or replace function private.can_moderate_post(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.posts p
    where p.id = p_post_id
      and private.can_moderate_feed(p.group_id)
  );
$$;

create or replace function private.post_of_comment(p_comment_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.post_id from public.comments c where c.id = p_comment_id;
$$;

-- Chat membership. There is deliberately NO admin exception here:
-- only members of a conversation can ever read it.
create or replace function private.is_conversation_member(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = p_conversation_id
      and cm.profile_id = private.current_profile_id()
  );
$$;

create or replace function private.conversation_role_of(p_conversation_id uuid)
returns public.conversation_role
language sql
stable
security definer
set search_path = ''
as $$
  select cm.role
  from public.conversation_members cm
  where cm.conversation_id = p_conversation_id
    and cm.profile_id = private.current_profile_id();
$$;

create or replace function private.conversation_of_message(p_message_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.conversation_id from public.messages m where m.id = p_message_id;
$$;

-- Safe text -> uuid cast (returns null instead of raising). Used by storage paths.
create or replace function private.try_uuid(p_value text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return p_value::uuid;
exception when others then
  return null;
end;
$$;

revoke all on all functions in schema private from public;
grant execute on all functions in schema private to authenticated, service_role;
