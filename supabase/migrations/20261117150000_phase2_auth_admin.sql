-- =============================================================================
-- Phase 2 / Migration 1: login security + admin panel helpers
--
--   1. Authenticator app (TOTP) as a second factor: once an employee turns it
--      on, the database refuses them until they also enter the 6-digit code
--      from Google/Microsoft Authenticator in this session (AAL2).
--   2. Changing an employee's phone number unlinks the old login, so only the
--      new number can sign in.
--   3. get_my_profile(): the signed-in employee's own profile (with phone).
--   4. admin_list_employees(): full employee list for the admin panel,
--      including phone numbers and deactivated employees. Admins only.
--   5. hook_send_sms_dev(): "SMS sender" for development that sends nothing
--      (free). Only test numbers (fixed codes) can log in while it is on.
--      Replaced by a real provider (Twilio SMS / WhatsApp) before the pilot.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Second factor (TOTP)
-- -----------------------------------------------------------------------------
-- True when the user either has no authenticator app, or already entered its
-- code in this session.
create or replace function private.mfa_satisfied()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
      or not exists (
        select 1
        from auth.mfa_factors f
        where f.user_id = auth.uid()
          and f.status::text = 'verified'
      );
$$;

-- Same golden rule as Phase 1, plus the second-factor check. Every RLS policy
-- goes through these two functions, so this protects every table at once.
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
    and p.is_active
    and private.mfa_satisfied();
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
    and p.is_active
    and private.mfa_satisfied();
$$;

-- -----------------------------------------------------------------------------
-- 2. Profile update guard (Phase 1 version + phone change unlinks the login)
-- -----------------------------------------------------------------------------
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
       and (new.role is distinct from old.role
            or new.is_active is distinct from old.is_active
            or new.phone is distinct from old.phone) then
      raise exception 'Admins cannot change their own role, phone or active status';
    end if;
    if new.auth_user_id is distinct from old.auth_user_id then
      raise exception 'The login link is managed automatically';
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

  -- A new phone number means a new login: the old one stops working.
  if new.phone is distinct from old.phone then
    new.auth_user_id := null;
  end if;

  if new.is_active is distinct from old.is_active then
    new.deactivated_at := case when new.is_active then null else now() end;
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. The signed-in employee's own profile
-- -----------------------------------------------------------------------------
create or replace function public.get_my_profile()
returns table (
  id             uuid,
  full_name      text,
  phone          text,
  department_id  uuid,
  job_title      text,
  role           public.app_role,
  locale         text,
  avatar_path    text
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.full_name, p.phone, p.department_id, p.job_title, p.role,
         p.locale, p.avatar_path
  from public.profiles p
  where p.id = private.current_profile_id();
$$;

-- -----------------------------------------------------------------------------
-- 4. Admin panel: all employees with phone numbers
-- -----------------------------------------------------------------------------
create or replace function public.admin_list_employees()
returns table (
  id              uuid,
  full_name       text,
  phone           text,
  department_id   uuid,
  job_title       text,
  role            public.app_role,
  is_active       boolean,
  deactivated_at  timestamptz,
  has_logged_in   boolean,
  created_at      timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only admins can list employees' using errcode = '42501';
  end if;

  return query
    select p.id, p.full_name, p.phone, p.department_id, p.job_title, p.role,
           p.is_active, p.deactivated_at, p.auth_user_id is not null,
           p.created_at
    from public.profiles p
    order by p.is_active desc, lower(p.full_name);
end;
$$;

revoke all on function private.mfa_satisfied() from public;
grant execute on function private.mfa_satisfied() to authenticated, service_role;
revoke execute on function public.get_my_profile() from public, anon;
revoke execute on function public.admin_list_employees() from public, anon;
grant execute on function public.get_my_profile() to authenticated;
grant execute on function public.admin_list_employees() to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Development SMS sender: sends nothing, costs nothing.
-- -----------------------------------------------------------------------------
create or replace function public.hook_send_sms_dev(event jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select '{}'::jsonb;
$$;

revoke execute on function public.hook_send_sms_dev(jsonb) from public, anon, authenticated;
grant execute on function public.hook_send_sms_dev(jsonb) to supabase_auth_admin;
