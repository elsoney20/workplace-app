-- =============================================================================
-- Phase 4: groups & departments
--   * Public groups: any employee can find and join them.
--   * Private groups: hidden; only members (invited by a moderator) see them.
--   * Department groups: created automatically (Phase 1), private, members
--     follow each employee's department, the department manager moderates.
--   * Group feeds reuse get_feed(p_group_id => ...) from Phase 3.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Membership guards
-- -----------------------------------------------------------------------------
create or replace function private.guard_group_member_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_department boolean;
begin
  if private.is_trusted_role() then
    return coalesce(new, old);
  end if;

  select g.department_id is not null into v_is_department
  from public.groups g where g.id = coalesce(new.group_id, old.group_id);

  if tg_op = 'INSERT' then
    if v_is_department and not private.is_admin() then
      raise exception 'Department group members follow the employee''s department';
    end if;
    if new.role = 'owner' and not (private.is_admin() or private.group_role_of(new.group_id) = 'owner') then
      raise exception 'Only the owner or an admin can add another owner';
    end if;
    if not exists (select 1 from public.profiles p where p.id = new.profile_id and p.is_active) then
      raise exception 'Only active employees can be added to a group';
    end if;
    new.muted := false;
    return new;
  end if;

  -- DELETE
  if v_is_department and not private.is_admin() then
    raise exception 'Department group members follow the employee''s department';
  end if;
  if old.role = 'owner'
     and not exists (select 1 from public.group_members gm
                     where gm.group_id = old.group_id and gm.role = 'owner' and gm.profile_id <> old.profile_id)
     and not private.is_admin() then
    raise exception 'A group needs at least one owner. Make someone else owner first.';
  end if;
  return old;
end;
$$;

create trigger group_members_guard_write
  before insert or delete on public.group_members
  for each row execute function private.guard_group_member_write();

-- Notify people who were added by someone else (not by automatic department
-- sync, which runs as a trusted role).
-- The trigger function runs as its owner, so check the CALLER's role first.
create or replace function private.notify_group_invite_caller()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.is_trusted_role() then
    perform private.insert_group_invite(new.group_id, new.profile_id);
  end if;
  return null;
end;
$$;

create or replace function private.insert_group_invite(p_group_id uuid, p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
begin
  if v_me is not null and p_profile_id <> v_me then
    insert into public.notifications (recipient_id, type, actor_id, target)
    values (p_profile_id, 'group_invite', v_me, jsonb_build_object('group_id', p_group_id));
  end if;
end;
$$;

create trigger group_members_notify_invite
  after insert on public.group_members
  for each row execute function private.notify_group_invite_caller();

-- Department groups stay private and keep their department.
create or replace function private.guard_department_group()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.is_trusted_role() and old.department_id is not null and new.privacy <> 'private' then
    raise exception 'Department groups are always private';
  end if;
  return new;
end;
$$;

create trigger groups_guard_department
  before update on public.groups
  for each row execute function private.guard_department_group();

-- Keep department group names in sync with the department name.
create or replace function private.rename_department_group()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.name_en is distinct from old.name_en or new.name_ar is distinct from old.name_ar then
    update public.groups
    set name = coalesce(nullif(new.name_en, ''), new.name_ar)
    where department_id = new.id;
  end if;
  return null;
end;
$$;

create trigger departments_rename_group
  after update on public.departments
  for each row execute function private.rename_department_group();

-- -----------------------------------------------------------------------------
-- Read functions
-- -----------------------------------------------------------------------------

-- Groups the caller can see (RLS hides private groups they are not in).
create or replace function public.list_groups(
  p_query     text default null,
  p_only_mine boolean default false
)
returns table (
  id             uuid,
  name           text,
  description    text,
  privacy        public.group_privacy,
  department_id  uuid,
  cover_path     text,
  member_count   integer,
  my_role        public.group_role,
  can_moderate   boolean,
  muted          boolean,
  created_at     timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    g.id, g.name, g.description, g.privacy, g.department_id, g.cover_path,
    (select count(*)::integer from public.group_members gm where gm.group_id = g.id),
    mine.role,
    private.can_moderate_group(g.id),
    coalesce(mine.muted, false),
    g.created_at
  from public.groups g
  left join public.group_members mine
    on mine.group_id = g.id and mine.profile_id = private.current_profile_id()
  where (not coalesce(p_only_mine, false) or mine.profile_id is not null)
    and (p_query is null or g.name ilike '%' || replace(replace(p_query, '%', ''), '_', '') || '%')
  order by (mine.profile_id is null), (g.department_id is null), lower(g.name);
$$;

create or replace function public.get_group_members(p_group_id uuid)
returns table (person jsonb, role public.group_role, joined_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select private.person_card(gm.profile_id), gm.role, gm.joined_at
  from public.group_members gm
  join public.profiles p on p.id = gm.profile_id
  where gm.group_id = p_group_id
    and p.is_active
  order by case gm.role when 'owner' then 0 when 'moderator' then 1 else 2 end, lower(p.full_name);
$$;

-- Creates a group; the creator becomes its owner (trigger from Phase 1).
-- SECURITY DEFINER because the new row is not yet visible to the caller's
-- own read rule inside the same statement; the same check as the insert
-- policy (managers and admins only) is done here.
create or replace function public.create_group(
  p_name        text,
  p_description text default null,
  p_privacy     public.group_privacy default 'public'
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not private.is_manager_or_admin() then
    raise exception 'Only managers and admins can create groups' using errcode = '42501';
  end if;
  insert into public.groups (name, description, privacy, created_by)
  values (trim(p_name), nullif(trim(coalesce(p_description, '')), ''), p_privacy, private.current_profile_id())
  returning id into v_id;
  return v_id;
end;
$$;

revoke execute on function
  public.list_groups(text, boolean),
  public.get_group_members(uuid),
  public.create_group(text, text, public.group_privacy)
from public, anon;
grant execute on function
  public.list_groups(text, boolean),
  public.get_group_members(uuid),
  public.create_group(text, text, public.group_privacy)
to authenticated;

revoke all on function private.insert_group_invite(uuid, uuid) from public;
grant execute on function private.insert_group_invite(uuid, uuid) to authenticated, service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.group_members, public.groups;
  end if;
end;
$$;
