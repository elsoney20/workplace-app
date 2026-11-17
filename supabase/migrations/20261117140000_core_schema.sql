-- =============================================================================
-- Phase 1 / Migration 1: core schema (types, tables, indexes, basic triggers)
-- Security (RLS policies) lives in the next migration. Every table created here
-- gets RLS enabled there, so nothing is readable until a policy allows it.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- Enum types
-- -----------------------------------------------------------------------------
create type public.app_role as enum ('admin', 'manager', 'employee');
create type public.phone_visibility as enum ('everyone', 'managers', 'nobody');
create type public.group_privacy as enum ('public', 'private');
create type public.group_role as enum ('owner', 'moderator', 'member');
create type public.attachment_kind as enum ('image', 'video', 'file');
create type public.conversation_kind as enum ('direct', 'group');
create type public.conversation_role as enum ('owner', 'member');
create type public.report_status as enum ('open', 'resolved', 'dismissed');
create type public.notification_type as enum (
  'mention', 'comment', 'reply', 'reaction', 'message', 'announcement',
  'group_invite', 'report_update'
);

-- -----------------------------------------------------------------------------
-- Shared trigger: keep updated_at current
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Employees & departments
-- -----------------------------------------------------------------------------
create table public.departments (
  id          uuid primary key default gen_random_uuid(),
  name_ar     text not null check (length(trim(name_ar)) between 1 and 100),
  name_en     text not null check (length(trim(name_en)) between 1 and 100),
  manager_id  uuid, -- FK added after profiles exists
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- One row per employee. This table IS the allowlist: an admin adds the
-- employee's phone number here first; the auth account is linked on first login.
create table public.profiles (
  id                uuid primary key default gen_random_uuid(),
  auth_user_id      uuid unique references auth.users (id) on delete set null,
  -- E.164 format, e.g. +201001234567
  phone             text not null unique check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  full_name         text not null check (length(trim(full_name)) between 1 and 120),
  department_id     uuid references public.departments (id) on delete set null,
  job_title         text check (job_title is null or length(job_title) <= 120),
  role              public.app_role not null default 'employee',
  is_active         boolean not null default true,
  deactivated_at    timestamptz,
  phone_visibility  public.phone_visibility not null default 'everyone',
  avatar_path       text,
  bio               text check (bio is null or length(bio) <= 500),
  locale            text not null default 'ar' check (locale in ('ar', 'en')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

alter table public.departments
  add constraint departments_manager_id_fkey
  foreign key (manager_id) references public.profiles (id) on delete set null;

create index profiles_department_id_idx on public.profiles (department_id);
create index profiles_full_name_idx on public.profiles (lower(full_name));
create index departments_manager_id_idx on public.departments (manager_id);

create trigger departments_set_updated_at before update on public.departments
  for each row execute function public.set_updated_at();
create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Groups
-- -----------------------------------------------------------------------------
create table public.groups (
  id             uuid primary key default gen_random_uuid(),
  name           text not null check (length(trim(name)) between 1 and 120),
  description    text check (description is null or length(description) <= 2000),
  privacy        public.group_privacy not null default 'public',
  -- Set when this is a department's own group (one per department).
  department_id  uuid unique references public.departments (id) on delete cascade,
  cover_path     text,
  created_by     uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table public.group_members (
  group_id    uuid not null references public.groups (id) on delete cascade,
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  role        public.group_role not null default 'member',
  muted       boolean not null default false,
  joined_at   timestamptz not null default now(),
  primary key (group_id, profile_id)
);

create index group_members_profile_id_idx on public.group_members (profile_id);

create trigger groups_set_updated_at before update on public.groups
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Feed: posts, attachments, comments, reactions, seen-by, mentions, hashtags
-- -----------------------------------------------------------------------------
create table public.posts (
  id               uuid primary key default gen_random_uuid(),
  author_id        uuid not null references public.profiles (id) on delete cascade,
  -- null = company-wide feed; otherwise the group's own feed.
  group_id         uuid references public.groups (id) on delete cascade,
  body             text not null default '' check (length(body) <= 20000),
  is_announcement  boolean not null default false,
  is_pinned        boolean not null default false,
  comments_locked  boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  edited_at        timestamptz,
  deleted_at       timestamptz,
  deleted_by       uuid references public.profiles (id) on delete set null
);

create index posts_feed_idx on public.posts (group_id, created_at desc) where deleted_at is null;
create index posts_pinned_idx on public.posts (group_id) where is_pinned and deleted_at is null;
create index posts_author_id_idx on public.posts (author_id);

create table public.post_attachments (
  id            uuid primary key default gen_random_uuid(),
  post_id       uuid not null references public.posts (id) on delete cascade,
  storage_path  text not null,
  kind          public.attachment_kind not null,
  mime_type     text,
  file_name     text,
  size_bytes    bigint not null check (size_bytes > 0 and size_bytes <= 52428800), -- 50 MB
  width         integer,
  height        integer,
  sort_order    smallint not null default 0,
  created_at    timestamptz not null default now()
);

create index post_attachments_post_id_idx on public.post_attachments (post_id);

create table public.comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.posts (id) on delete cascade,
  author_id   uuid not null references public.profiles (id) on delete cascade,
  parent_id   uuid references public.comments (id) on delete cascade,
  body        text not null check (length(trim(body)) between 1 and 5000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  edited_at   timestamptz,
  deleted_at  timestamptz,
  deleted_by  uuid references public.profiles (id) on delete set null
);

create index comments_post_id_idx on public.comments (post_id, created_at);
create index comments_parent_id_idx on public.comments (parent_id);
create index comments_author_id_idx on public.comments (author_id);

-- One reaction per person per post/comment (any emoji; changing it = update).
create table public.reactions (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  post_id     uuid references public.posts (id) on delete cascade,
  comment_id  uuid references public.comments (id) on delete cascade,
  emoji       text not null check (length(emoji) between 1 and 32),
  created_at  timestamptz not null default now(),
  check (num_nonnulls(post_id, comment_id) = 1)
);

create unique index reactions_one_per_post on public.reactions (profile_id, post_id) where post_id is not null;
create unique index reactions_one_per_comment on public.reactions (profile_id, comment_id) where comment_id is not null;
create index reactions_post_id_idx on public.reactions (post_id);
create index reactions_comment_id_idx on public.reactions (comment_id);

-- "Seen by" for announcements.
create table public.announcement_views (
  post_id     uuid not null references public.posts (id) on delete cascade,
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  seen_at     timestamptz not null default now(),
  primary key (post_id, profile_id)
);

create index announcement_views_profile_id_idx on public.announcement_views (profile_id);

create table public.mentions (
  id            uuid primary key default gen_random_uuid(),
  post_id       uuid references public.posts (id) on delete cascade,
  comment_id    uuid references public.comments (id) on delete cascade,
  mentioned_id  uuid not null references public.profiles (id) on delete cascade,
  created_at    timestamptz not null default now(),
  check (num_nonnulls(post_id, comment_id) = 1)
);

create unique index mentions_unique_post on public.mentions (post_id, mentioned_id) where post_id is not null;
create unique index mentions_unique_comment on public.mentions (comment_id, mentioned_id) where comment_id is not null;
create index mentions_mentioned_id_idx on public.mentions (mentioned_id);

create table public.hashtags (
  id          uuid primary key default gen_random_uuid(),
  -- Stored lower-case without '#'. Letters (incl. Arabic), digits, underscore.
  tag         text not null unique check (tag ~ '^[[:alnum:]_]{1,64}$' and tag = lower(tag)),
  created_at  timestamptz not null default now()
);

create table public.post_hashtags (
  post_id     uuid not null references public.posts (id) on delete cascade,
  hashtag_id  uuid not null references public.hashtags (id) on delete cascade,
  primary key (post_id, hashtag_id)
);

create index post_hashtags_hashtag_id_idx on public.post_hashtags (hashtag_id);

create trigger posts_set_updated_at before update on public.posts
  for each row execute function public.set_updated_at();
create trigger comments_set_updated_at before update on public.comments
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Chat
-- -----------------------------------------------------------------------------
create table public.conversations (
  id               uuid primary key default gen_random_uuid(),
  kind             public.conversation_kind not null,
  title            text check (title is null or length(title) <= 120),
  -- For direct chats: the two profile ids sorted, so a pair has only one chat.
  direct_key       text unique,
  created_by       uuid references public.profiles (id) on delete set null,
  last_message_at  timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check ((kind = 'direct') = (direct_key is not null))
);

create table public.conversation_members (
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  profile_id       uuid not null references public.profiles (id) on delete cascade,
  role             public.conversation_role not null default 'member',
  muted            boolean not null default false,
  last_read_at     timestamptz,
  joined_at        timestamptz not null default now(),
  primary key (conversation_id, profile_id)
);

create index conversation_members_profile_id_idx on public.conversation_members (profile_id);

create table public.messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  sender_id        uuid not null references public.profiles (id) on delete cascade,
  body             text not null default '' check (length(body) <= 10000),
  reply_to_id      uuid references public.messages (id) on delete set null,
  created_at       timestamptz not null default now(),
  edited_at        timestamptz,
  deleted_at       timestamptz
);

create index messages_conversation_idx on public.messages (conversation_id, created_at desc);
create index messages_sender_id_idx on public.messages (sender_id);

create table public.message_attachments (
  id            uuid primary key default gen_random_uuid(),
  message_id    uuid not null references public.messages (id) on delete cascade,
  storage_path  text not null,
  kind          public.attachment_kind not null,
  mime_type     text,
  file_name     text,
  size_bytes    bigint not null check (size_bytes > 0 and size_bytes <= 52428800), -- 50 MB
  width         integer,
  height        integer,
  created_at    timestamptz not null default now()
);

create index message_attachments_message_id_idx on public.message_attachments (message_id);

-- Per-message, per-person delivery and "seen" time (✓ delivered, ✓✓ seen).
create table public.message_receipts (
  message_id    uuid not null references public.messages (id) on delete cascade,
  profile_id    uuid not null references public.profiles (id) on delete cascade,
  delivered_at  timestamptz not null default now(),
  seen_at       timestamptz,
  primary key (message_id, profile_id)
);

create index message_receipts_profile_id_idx on public.message_receipts (profile_id);

-- Chat reactions: a person may add several different emojis to one message.
create table public.message_reactions (
  message_id  uuid not null references public.messages (id) on delete cascade,
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  emoji       text not null check (length(emoji) between 1 and 32),
  created_at  timestamptz not null default now(),
  primary key (message_id, profile_id, emoji)
);

create index message_reactions_profile_id_idx on public.message_reactions (profile_id);

create trigger conversations_set_updated_at before update on public.conversations
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Moderation & notifications
-- -----------------------------------------------------------------------------
create table public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references public.profiles (id) on delete cascade,
  post_id      uuid references public.posts (id) on delete cascade,
  comment_id   uuid references public.comments (id) on delete cascade,
  reason       text not null check (length(trim(reason)) between 1 and 1000),
  status       public.report_status not null default 'open',
  handled_by   uuid references public.profiles (id) on delete set null,
  handled_at   timestamptz,
  created_at   timestamptz not null default now(),
  check (num_nonnulls(post_id, comment_id) = 1)
);

create unique index reports_one_open_per_post on public.reports (reporter_id, post_id)
  where post_id is not null and status = 'open';
create unique index reports_one_open_per_comment on public.reports (reporter_id, comment_id)
  where comment_id is not null and status = 'open';
create index reports_status_idx on public.reports (status, created_at desc);

create table public.notifications (
  id            uuid primary key default gen_random_uuid(),
  recipient_id  uuid not null references public.profiles (id) on delete cascade,
  type          public.notification_type not null,
  actor_id      uuid references public.profiles (id) on delete set null,
  -- What to open when tapped, e.g. {"post_id": "...", "comment_id": "..."}.
  target        jsonb not null default '{}'::jsonb,
  read_at       timestamptz,
  created_at    timestamptz not null default now()
);

create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);
create index notifications_unread_idx on public.notifications (recipient_id) where read_at is null;
