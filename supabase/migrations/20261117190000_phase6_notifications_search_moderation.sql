-- =============================================================================
-- Phase 6: notifications, search, employee directory, moderation
--   * More notifications: reactions on my post, new announcements, report
--     handled. Muted groups send no notifications.
--   * Notification centre RPCs (list, unread count, mark read).
--   * Search: people, posts (only ones you can see), messages (only your
--     own chats — RLS, no admin exception).
--   * Employee directory with each person's phone visibility choice.
--   * Moderation: reports queue for admins / group moderators.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Muted groups: no notifications from them.
-- -----------------------------------------------------------------------------
create or replace function private.is_muted_for(p_profile_id uuid, p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.posts p
    join public.group_members gm on gm.group_id = p.group_id and gm.profile_id = p_profile_id
    where p.id = p_post_id and gm.muted
  );
$$;

-- Drop notifications about muted groups (runs for every notification insert).
create or replace function private.filter_muted_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post uuid := private.try_uuid(new.target ->> 'post_id');
begin
  if v_post is not null and private.is_muted_for(new.recipient_id, v_post) then
    return null; -- skip
  end if;
  return new;
end;
$$;

create trigger notifications_filter_muted
  before insert on public.notifications
  for each row execute function private.filter_muted_notification();

-- Reaction on my post (one notification per person per post; changing the
-- emoji does not notify again).
create or replace function private.notify_reaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_author uuid;
begin
  if new.post_id is null then
    return null;
  end if;
  select p.author_id into v_author from public.posts p where p.id = new.post_id;
  if v_author is null or v_author = new.profile_id then
    return null;
  end if;
  if not exists (
    select 1 from public.notifications n
    where n.recipient_id = v_author and n.type = 'reaction' and n.actor_id = new.profile_id
      and n.target ->> 'post_id' = new.post_id::text
  ) then
    insert into public.notifications (recipient_id, type, actor_id, target)
    values (v_author, 'reaction', new.profile_id,
            jsonb_build_object('post_id', new.post_id, 'emoji', new.emoji));
  end if;
  return null;
end;
$$;

create trigger reactions_notify
  after insert on public.reactions
  for each row execute function private.notify_reaction();

-- New announcement: notify everyone who can see it (company or group).
create or replace function private.notify_announcement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_announcement and new.deleted_at is null
     and (tg_op = 'INSERT' or not old.is_announcement) then
    insert into public.notifications (recipient_id, type, actor_id, target)
    select pr.id, 'announcement', new.author_id, jsonb_build_object('post_id', new.id, 'group_id', new.group_id)
    from public.profiles pr
    where pr.is_active
      and pr.id <> new.author_id
      and (
        new.group_id is null
        or exists (select 1 from public.group_members gm where gm.group_id = new.group_id and gm.profile_id = pr.id)
      );
  end if;
  return null;
end;
$$;

create trigger posts_notify_announcement
  after insert or update of is_announcement on public.posts
  for each row execute function private.notify_announcement();

-- Report handled: tell the person who reported it.
create or replace function private.notify_report_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is distinct from old.status and new.status <> 'open' then
    insert into public.notifications (recipient_id, type, actor_id, target)
    values (new.reporter_id, 'report_update', null,
            jsonb_strip_nulls(jsonb_build_object(
              'report_id', new.id, 'status', new.status,
              'post_id', coalesce(new.post_id, private.post_of_comment(new.comment_id)),
              'comment_id', new.comment_id)));
  end if;
  return null;
end;
$$;

create trigger reports_notify_update
  after update of status on public.reports
  for each row execute function private.notify_report_update();

-- -----------------------------------------------------------------------------
-- Notification centre
-- -----------------------------------------------------------------------------
create or replace function public.list_notifications(p_before timestamptz default null, p_limit integer default 30)
returns table (
  id          uuid,
  type        public.notification_type,
  actor       jsonb,
  target      jsonb,
  preview     text,
  read_at     timestamptz,
  created_at  timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    n.id, n.type,
    case when n.actor_id is not null then private.person_card(n.actor_id) end,
    n.target,
    -- Short text of the post/comment (only if I can still see it).
    left(coalesce(
      (select c.body from public.comments c
       where c.id = private.try_uuid(n.target ->> 'comment_id') and c.deleted_at is null
         and private.can_view_post(c.post_id)),
      (select p.body from public.posts p
       where p.id = private.try_uuid(n.target ->> 'post_id') and p.deleted_at is null
         and private.can_view_post(p.id)),
      (select g.name from public.groups g where g.id = private.try_uuid(n.target ->> 'group_id'))
    ), 160),
    n.read_at, n.created_at
  from public.notifications n
  where n.recipient_id = private.current_profile_id()
    and (p_before is null or n.created_at < p_before)
  order by n.created_at desc
  limit least(greatest(coalesce(p_limit, 30), 1), 100);
$$;

create or replace function public.unread_notification_count()
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select count(*)::integer from public.notifications
  where recipient_id = private.current_profile_id() and read_at is null;
$$;

create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  update public.notifications
  set read_at = now()
  where recipient_id = private.current_profile_id()
    and read_at is null
    and (p_ids is null or id = any (p_ids));
$$;

-- -----------------------------------------------------------------------------
-- Search
-- -----------------------------------------------------------------------------
create or replace function private.like_pattern(p_query text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '%' || replace(replace(replace(trim(coalesce(p_query, '')), '\', ''), '%', ''), '_', '') || '%';
$$;

create or replace function public.search_posts(p_query text, p_limit integer default 20)
returns table (id uuid, group_id uuid, group_name text, author jsonb, body text, created_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.group_id, g.name, private.person_card(p.author_id), left(p.body, 300), p.created_at
  from public.posts p
  left join public.groups g on g.id = p.group_id
  where p.deleted_at is null
    and length(trim(coalesce(p_query, ''))) >= 2
    and p.body ilike private.like_pattern(p_query)
  order by p.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

-- PRIVACY: RLS on messages = members only, so this only ever searches the
-- caller's own chats.
create or replace function public.search_messages(p_query text, p_limit integer default 20)
returns table (id uuid, conversation_id uuid, conversation_title text, sender jsonb, body text, created_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select m.id, m.conversation_id,
    coalesce(c.title, (
      select pr.full_name from public.conversation_members cm
      join public.profiles pr on pr.id = cm.profile_id
      where cm.conversation_id = c.id and cm.profile_id <> private.current_profile_id()
      limit 1)),
    private.person_card(m.sender_id), left(m.body, 300), m.created_at
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  where m.deleted_at is null
    and length(trim(coalesce(p_query, ''))) >= 2
    and m.body ilike private.like_pattern(p_query)
  order by m.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

-- -----------------------------------------------------------------------------
-- Employee directory (phone only when the person allows it)
-- -----------------------------------------------------------------------------
create or replace function public.list_directory(p_query text default null, p_department_id uuid default null)
returns table (
  person           jsonb,
  department_id    uuid,
  department_ar    text,
  department_en    text,
  role             public.app_role,
  bio              text,
  phone            text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    private.person_card(p.id), p.department_id, d.name_ar, d.name_en, p.role, p.bio,
    (select pc.phone from public.profile_contacts pc where pc.profile_id = p.id)
  from public.profiles p
  left join public.departments d on d.id = p.department_id
  where p.is_active
    and (p_department_id is null or p.department_id = p_department_id)
    and (
      p_query is null or trim(p_query) = ''
      or p.full_name ilike private.like_pattern(p_query)
      or p.job_title ilike private.like_pattern(p_query)
      or d.name_en ilike private.like_pattern(p_query)
      or d.name_ar ilike private.like_pattern(p_query)
    )
  order by lower(p.full_name);
$$;

-- My own editable settings (bio, phone visibility, avatar).
create or replace function public.get_my_settings()
returns table (bio text, phone_visibility public.phone_visibility, avatar_path text)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.bio, p.phone_visibility, p.avatar_path
  from public.profiles p
  where p.id = private.current_profile_id();
$$;

-- -----------------------------------------------------------------------------
-- Moderation queue (RLS: admins see all, group moderators their groups,
-- reporters only their own reports).
-- -----------------------------------------------------------------------------
create or replace function public.list_reports(p_status public.report_status default 'open')
returns table (
  id            uuid,
  status        public.report_status,
  reason        text,
  created_at    timestamptz,
  handled_at    timestamptz,
  reporter      jsonb,
  handled_by    jsonb,
  post_id       uuid,
  comment_id    uuid,
  content       text,
  content_author jsonb,
  content_deleted boolean,
  group_name    text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    r.id, r.status, r.reason, r.created_at, r.handled_at,
    private.person_card(r.reporter_id),
    case when r.handled_by is not null then private.person_card(r.handled_by) end,
    coalesce(r.post_id, c.post_id),
    r.comment_id,
    left(coalesce(c.body, p.body), 500),
    private.person_card(coalesce(c.author_id, p.author_id)),
    coalesce(c.deleted_at, p.deleted_at) is not null,
    g.name
  from public.reports r
  left join public.comments c on c.id = r.comment_id
  left join public.posts p on p.id = coalesce(r.post_id, c.post_id)
  left join public.groups g on g.id = p.group_id
  where p_status is null or r.status = p_status
  order by r.created_at desc;
$$;

-- Handle a report; optionally delete the reported content in one step.
create or replace function public.handle_report(
  p_report_id      uuid,
  p_status         public.report_status,
  p_delete_content boolean default false
)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_post uuid;
  v_comment uuid;
begin
  select r.post_id, r.comment_id into v_post, v_comment from public.reports r where r.id = p_report_id;
  if not found then
    raise exception 'Report not found' using errcode = '42501';
  end if;
  if p_delete_content then
    if v_comment is not null then
      update public.comments set deleted_at = now() where id = v_comment;
    else
      update public.posts set deleted_at = now() where id = v_post;
    end if;
  end if;
  update public.reports set status = p_status where id = p_report_id;
  if not found then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
end;
$$;

-- One report per person per item while open: reporting again just updates nothing.
create or replace function public.report_content(p_post_id uuid default null, p_comment_id uuid default null, p_reason text default '')
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  insert into public.reports (reporter_id, post_id, comment_id, reason)
  values (private.current_profile_id(), p_post_id, p_comment_id, trim(p_reason))
  on conflict do nothing;
$$;

revoke all on function
  private.is_muted_for(uuid, uuid),
  private.like_pattern(text)
from public;
grant execute on function
  private.is_muted_for(uuid, uuid),
  private.like_pattern(text)
to authenticated, service_role;

revoke execute on function
  public.list_notifications(timestamptz, integer),
  public.unread_notification_count(),
  public.mark_notifications_read(uuid[]),
  public.search_posts(text, integer),
  public.search_messages(text, integer),
  public.list_directory(text, uuid),
  public.get_my_settings(),
  public.list_reports(public.report_status),
  public.handle_report(uuid, public.report_status, boolean),
  public.report_content(uuid, uuid, text)
from public, anon;
grant execute on function
  public.list_notifications(timestamptz, integer),
  public.unread_notification_count(),
  public.mark_notifications_read(uuid[]),
  public.search_posts(text, integer),
  public.search_messages(text, integer),
  public.list_directory(text, uuid),
  public.get_my_settings(),
  public.list_reports(public.report_status),
  public.handle_report(uuid, public.report_status, boolean),
  public.report_content(uuid, uuid, text)
to authenticated;
