-- =============================================================================
-- Phase 1 / Migration 5: phone allowlist + deactivation at the login level
--
-- Two Supabase Auth hooks (switched on in the dashboard in Phase 2:
-- Authentication -> Hooks):
--   1. "Before User Created" -> public.hook_before_user_created
--      Rejects any phone number that an admin has not registered (or that is
--      deactivated) BEFORE an account is created or any SMS is sent.
--   2. "Custom Access Token"  -> public.hook_custom_access_token
--      Refuses to issue/refresh a session for deactivated employees and adds
--      the employee's app role to the token.
-- RLS already blocks deactivated users on every table; the hooks add a second
-- wall and stop SMS costs for unknown numbers.
-- =============================================================================

-- Auth stores phones as digits without '+'; profiles store E.164 with '+'.
create or replace function private.normalize_phone(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(regexp_replace(p_phone, '\D', '', 'g'), '') = '' then null
    else '+' || regexp_replace(p_phone, '\D', '', 'g')
  end;
$$;

create or replace function public.hook_before_user_created(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := private.normalize_phone(event -> 'user' ->> 'phone');
begin
  if v_phone is null then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', 'Sign-in is only allowed with a registered phone number.'));
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.phone = v_phone
      and p.is_active
      and p.auth_user_id is null
  ) then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', 'This phone number is not registered. Please contact your administrator.'));
  end if;

  return '{}'::jsonb;
end;
$$;

create or replace function public.hook_custom_access_token(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  v_role   public.app_role;
begin
  select p.role into v_role
  from public.profiles p
  where p.auth_user_id = (event ->> 'user_id')::uuid
    and p.is_active;

  if v_role is null then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', 'Your account is not active. Please contact your administrator.'));
  end if;

  v_claims := jsonb_set(v_claims, '{app_role}', to_jsonb(v_role::text));
  return jsonb_build_object('claims', v_claims);
end;
$$;

revoke execute on function public.hook_before_user_created(jsonb) from public, anon, authenticated;
revoke execute on function public.hook_custom_access_token(jsonb) from public, anon, authenticated;
grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;
grant execute on function public.hook_custom_access_token(jsonb) to supabase_auth_admin;
grant usage on schema public to supabase_auth_admin;

-- When the auth account is created on first login, link it to the profile.
create or replace function private.link_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.normalize_phone(new.phone) is not null then
    update public.profiles p
    set auth_user_id = new.id
    where p.phone = private.normalize_phone(new.phone)
      and p.auth_user_id is null;
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created_link_profile
  after insert or update of phone on auth.users
  for each row execute function private.link_auth_user();
