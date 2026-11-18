-- =============================================================================
-- Phase 3: company feed
--   * #hashtags and @mentions are read from the text by the SERVER (triggers),
--     so the app cannot fake them and they always match what people see.
--   * Mention markup in a post/comment body: @[Full Name](profile-uuid)
--   * Notifications rows for mentions, comments and replies (the notification
--     centre screen comes in Phase 6; the rows start collecting now).
--   * Read functions for the feed, comments and announcement "seen by".
-- All read functions are SECURITY INVOKER: the RLS rules from Phase 1 still
-- decide what each person can see.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Hashtags: allow Arabic letters explicitly (do not depend on server locale).
-- -----------------------------------------------------------------------------
alter table public.hashtags drop constraint if exists hashtags_tag_check;
alter table public.hashtags add constraint hashtags_tag_check
  check (tag ~ '^[[:alnum:]_؀-ۿ]{1,64}$' and tag = lower(tag));

create or replace function private.extract_hashtags(p_body text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(distinct lower(m[1])), '{}')
  from regexp_matches(coalesce(p_body, ''), '#([[:alnum:]_؀-ۿ]{1,64})', 'g') as m;
$$;

create or replace function private.extract_mention_ids(p_body text)
returns uuid[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(distinct private.try_uuid(m[1])) filter (where private.try_uuid(m[1]) is not null), '{}')
  from regexp_matches(
    coalesce(p_body, ''),
    '@\[[^\]\n]{1,120}\]\(([0-9a-fA-F-]{36})\)',
    'g'
  ) as m;
$$;

-- Can this (other) person see the post? Used so we never notify someone about
-- a post in a private group they are not part of.
create or replace function private.profile_can_view_post(p_profile_id uuid, p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.posts p
    join public.profiles pr on pr.id = p_profile_id and pr.is_active
    where p.id = p_post_id
      and p.deleted_at is null
      and (
        p.group_id is null
        or exists (select 1 from public.groups g where g.id = p.group_id and g.privacy = 'public')
        or exists (select 1 from public.group_members gm
                   where gm.group_id = p.group_id and gm.profile_id = p_profile_id)
      )
  );
$$;

-- -----------------------------------------------------------------------------
-- Keep post_hashtags + mentions in sync with the text.
-- -----------------------------------------------------------------------------
create or replace function private.sync_post_tags()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tags text[] := private.extract_hashtags(new.body);
  v_ids  uuid[] := private.extract_mention_ids(new.body);
begin
  -- Hashtags
  insert into public.hashtags (tag)
  select t from unnest(v_tags) as t
  on conflict (tag) do nothing;

  delete from public.post_hashtags ph
  using public.hashtags h
  where ph.post_id = new.id and h.id = ph.hashtag_id and not (h.tag = any (v_tags));

  insert into public.post_hashtags (post_id, hashtag_id)
  select new.id, h.id from public.hashtags h where h.tag = any (v_tags)
  on conflict do nothing;

  -- Mentions (never yourself; only people who can see the post)
  delete from public.mentions m
  where m.post_id = new.id and not (m.mentioned_id = any (v_ids));

  insert into public.mentions (post_id, mentioned_id)
  select new.id, pid
  from unnest(v_ids) as pid
  where pid <> new.author_id
    and private.profile_can_view_post(pid, new.id)
  on conflict do nothing;

  return null;
end;
$$;

create trigger posts_sync_tags
  after insert or update of body on public.posts
  for each row execute function private.sync_post_tags();

create or replace function private.sync_comment_mentions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := private.extract_mention_ids(new.body);
begin
  delete from public.mentions m
  where m.comment_id = new.id and not (m.mentioned_id = any (v_ids));

  insert into public.mentions (comment_id, mentioned_id)
  select new.id, pid
  from unnest(v_ids) as pid
  where pid <> new.author_id
    and private.profile_can_view_post(pid, new.post_id)
  on conflict do nothing;

  return null;
end;
$$;

create trigger comments_sync_mentions
  after insert or update of body on public.comments
  for each row execute function private.sync_comment_mentions();

-- Hashtags and mentions are now written only by the triggers above.
drop policy if exists mentions_insert_author on public.mentions;
drop policy if exists mentions_delete_author on public.mentions;
drop policy if exists hashtags_insert on public.hashtags;
drop policy if exists post_hashtags_insert_author on public.post_hashtags;
drop policy if exists post_hashtags_delete_author on public.post_hashtags;

-- -----------------------------------------------------------------------------
-- Notifications: mention, comment on my post, reply to my comment.
-- -----------------------------------------------------------------------------
create or replace function private.notify_mention()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post_id uuid;
  v_actor   uuid;
begin
  if new.post_id is not null then
    select p.id, p.author_id into v_post_id, v_actor from public.posts p where p.id = new.post_id;
  else
    select c.post_id, c.author_id into v_post_id, v_actor from public.comments c where c.id = new.comment_id;
  end if;

  insert into public.notifications (recipient_id, type, actor_id, target)
  values (
    new.mentioned_id, 'mention', v_actor,
    jsonb_strip_nulls(jsonb_build_object('post_id', v_post_id, 'comment_id', new.comment_id))
  );
  return null;
end;
$$;

create trigger mentions_notify
  after insert on public.mentions
  for each row execute function private.notify_mention();

create or replace function private.notify_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post_author   uuid;
  v_parent_author uuid;
  v_mentioned     uuid[] := private.extract_mention_ids(new.body);
begin
  select p.author_id into v_post_author from public.posts p where p.id = new.post_id;
  if new.parent_id is not null then
    select c.author_id into v_parent_author from public.comments c where c.id = new.parent_id;
  end if;

  -- Reply to my comment (skip if I'm also mentioned: that notification wins).
  if v_parent_author is not null and v_parent_author <> new.author_id
     and not (v_parent_author = any (v_mentioned)) then
    insert into public.notifications (recipient_id, type, actor_id, target)
    values (v_parent_author, 'reply', new.author_id,
            jsonb_build_object('post_id', new.post_id, 'comment_id', new.id));
  end if;

  -- Comment on my post.
  if v_post_author is not null and v_post_author <> new.author_id
     and v_post_author is distinct from v_parent_author
     and not (v_post_author = any (v_mentioned)) then
    insert into public.notifications (recipient_id, type, actor_id, target)
    values (v_post_author, 'comment', new.author_id,
            jsonb_build_object('post_id', new.post_id, 'comment_id', new.id));
  end if;

  return null;
end;
$$;

create trigger comments_notify
  after insert on public.comments
  for each row execute function private.notify_comment();

-- -----------------------------------------------------------------------------
-- Attachments must live in their own post's storage folder: post-media/<post_id>/...
-- -----------------------------------------------------------------------------
create or replace function private.guard_post_attachment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.is_trusted_role()
     and split_part(new.storage_path, '/', 1) <> new.post_id::text then
    raise exception 'Attachment path must start with the post id';
  end if;
  return new;
end;
$$;

create trigger post_attachments_guard
  before insert or update on public.post_attachments
  for each row execute function private.guard_post_attachment();

-- -----------------------------------------------------------------------------
-- Read functions
-- -----------------------------------------------------------------------------

-- Small public card for a person (never includes the phone number).
create or replace function private.person_card(p_profile_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', pr.id, 'full_name', pr.full_name,
    'job_title', pr.job_title, 'avatar_path', pr.avatar_path
  )
  from public.profiles pr
  where pr.id = p_profile_id
    and private.current_profile_id() is not null;
$$;

-- One page of a feed.
--   p_group_id : null = company feed (Phase 4 adds group feeds)
--   p_hashtag  : only posts with this #tag (without '#')
--   p_pinned   : true = pinned only, false = not pinned, null = both
--   p_before   : created_at of the last post already shown (paging)
--   p_post_id  : just this one post (e.g. opened from a notification);
--                p_group_id is ignored then
create or replace function public.get_feed(
  p_group_id uuid default null,
  p_hashtag  text default null,
  p_pinned   boolean default null,
  p_before   timestamptz default null,
  p_limit    integer default 20,
  p_post_id  uuid default null
)
returns table (
  id               uuid,
  group_id         uuid,
  author           jsonb,
  body             text,
  is_announcement  boolean,
  is_pinned        boolean,
  comments_locked  boolean,
  created_at       timestamptz,
  edited_at        timestamptz,
  attachments      jsonb,
  comment_count    integer,
  reactions        jsonb,
  my_reaction      text,
  seen_count       integer,
  seen_by_me       boolean,
  audience_count   integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  with me as (select private.current_profile_id() as id),
  page as (
    select p.*
    from public.posts p
    where p.deleted_at is null
      and (p.id = p_post_id or (p_post_id is null and p.group_id is not distinct from p_group_id))
      and (p_pinned is null or p.is_pinned = p_pinned)
      and (p_before is null or p.created_at < p_before)
      and (
        p_hashtag is null
        or exists (
          select 1 from public.post_hashtags ph
          join public.hashtags h on h.id = ph.hashtag_id
          where ph.post_id = p.id and h.tag = lower(ltrim(p_hashtag, '#'))
        )
      )
    order by p.created_at desc
    limit least(greatest(coalesce(p_limit, 20), 1), 50)
  )
  select
    p.id,
    p.group_id,
    private.person_card(p.author_id),
    p.body,
    p.is_announcement,
    p.is_pinned,
    p.comments_locked,
    p.created_at,
    p.edited_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'storage_path', a.storage_path, 'kind', a.kind,
               'mime_type', a.mime_type, 'file_name', a.file_name,
               'size_bytes', a.size_bytes, 'width', a.width, 'height', a.height
             ) order by a.sort_order, a.created_at)
      from public.post_attachments a where a.post_id = p.id
    ), '[]'::jsonb),
    (select count(*)::integer from public.comments c where c.post_id = p.id and c.deleted_at is null),
    coalesce((
      select jsonb_object_agg(r.emoji, r.n)
      from (select emoji, count(*) as n from public.reactions where post_id = p.id group by emoji) r
    ), '{}'::jsonb),
    (select r.emoji from public.reactions r, me where r.post_id = p.id and r.profile_id = me.id),
    -- RLS: only the author and moderators see the full count.
    (select count(*)::integer from public.announcement_views v where v.post_id = p.id),
    exists (select 1 from public.announcement_views v, me where v.post_id = p.id and v.profile_id = me.id),
    case when p.is_announcement then
      case when p.group_id is null
        then (select count(*)::integer from public.profiles pr where pr.is_active)
        else (select count(*)::integer from public.group_members gm where gm.group_id = p.group_id)
      end
    end
  from page p
  order by p.created_at desc;
$$;

create or replace function public.get_post_comments(p_post_id uuid)
returns table (
  id           uuid,
  post_id      uuid,
  parent_id    uuid,
  author       jsonb,
  body         text,
  created_at   timestamptz,
  edited_at    timestamptz,
  reactions    jsonb,
  my_reaction  text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    c.id, c.post_id, c.parent_id,
    private.person_card(c.author_id),
    c.body, c.created_at, c.edited_at,
    coalesce((
      select jsonb_object_agg(r.emoji, r.n)
      from (select emoji, count(*) as n from public.reactions where comment_id = c.id group by emoji) r
    ), '{}'::jsonb),
    (select r.emoji from public.reactions r
     where r.comment_id = c.id and r.profile_id = private.current_profile_id())
  from public.comments c
  where c.post_id = p_post_id
    and c.deleted_at is null
  order by c.created_at;
$$;

-- Who reacted with what (for the "reactions" list on a post or comment).
create or replace function public.get_reactors(p_post_id uuid default null, p_comment_id uuid default null)
returns table (person jsonb, emoji text, created_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select private.person_card(r.profile_id), r.emoji, r.created_at
  from public.reactions r
  where (p_post_id is not null and r.post_id = p_post_id)
     or (p_comment_id is not null and r.comment_id = p_comment_id)
  order by r.created_at desc;
$$;

-- "Seen by" list. RLS: only the author and moderators get rows (others get
-- only themselves).
create or replace function public.get_announcement_viewers(p_post_id uuid)
returns table (person jsonb, seen_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select private.person_card(v.profile_id), v.seen_at
  from public.announcement_views v
  where v.post_id = p_post_id
  order by v.seen_at desc;
$$;

-- Called by the app when an announcement appears on screen.
create or replace function public.mark_announcement_seen(p_post_id uuid)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  insert into public.announcement_views (post_id, profile_id)
  select p_post_id, private.current_profile_id()
  where exists (select 1 from public.posts p where p.id = p_post_id and p.is_announcement)
  on conflict (post_id, profile_id) do nothing;
$$;

-- Most used hashtags in the last 30 days (posts the caller can see).
create or replace function public.get_trending_hashtags(p_limit integer default 10)
returns table (tag text, post_count integer)
language sql
stable
security invoker
set search_path = ''
as $$
  select h.tag, count(*)::integer
  from public.post_hashtags ph
  join public.hashtags h on h.id = ph.hashtag_id
  join public.posts p on p.id = ph.post_id
  where p.deleted_at is null
    and p.created_at > now() - interval '30 days'
  group by h.tag
  order by count(*) desc, h.tag
  limit least(greatest(coalesce(p_limit, 10), 1), 30);
$$;

-- People to suggest after typing '@' (active employees, no phone numbers).
create or replace function public.search_people(p_query text, p_limit integer default 8)
returns table (person jsonb)
language sql
stable
security invoker
set search_path = ''
as $$
  select private.person_card(pr.id)
  from public.profiles pr
  where pr.is_active
    and pr.full_name ilike '%' || replace(replace(coalesce(p_query, ''), '%', ''), '_', '') || '%'
  order by lower(pr.full_name)
  limit least(greatest(coalesce(p_limit, 8), 1), 20);
$$;

revoke all on function
  private.extract_hashtags(text),
  private.extract_mention_ids(text),
  private.profile_can_view_post(uuid, uuid),
  private.person_card(uuid)
from public;
grant execute on function
  private.extract_hashtags(text),
  private.extract_mention_ids(text),
  private.profile_can_view_post(uuid, uuid),
  private.person_card(uuid)
to authenticated, service_role;

revoke execute on function
  public.get_feed(uuid, text, boolean, timestamptz, integer, uuid),
  public.get_post_comments(uuid),
  public.get_reactors(uuid, uuid),
  public.get_announcement_viewers(uuid),
  public.mark_announcement_seen(uuid),
  public.get_trending_hashtags(integer),
  public.search_people(text, integer)
from public, anon;
grant execute on function
  public.get_feed(uuid, text, boolean, timestamptz, integer, uuid),
  public.get_post_comments(uuid),
  public.get_reactors(uuid, uuid),
  public.get_announcement_viewers(uuid),
  public.mark_announcement_seen(uuid),
  public.get_trending_hashtags(integer),
  public.search_people(text, integer)
to authenticated;

-- Live updates for new attachments too (posts/comments/reactions already on).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.announcement_views;
  end if;
end;
$$;
