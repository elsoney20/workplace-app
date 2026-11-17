-- =============================================================================
-- Phase 1 / Migration 6: file storage rules + realtime
--
-- Buckets (all private; the app uses short-lived signed URLs). Max 50 MB/file.
--   avatars/<profile_id>/<file>          readable by any active employee
--   post-media/<post_id>/<file>          readable by whoever can see the post
--   chat-media/<conversation_id>/<file>  readable ONLY by chat members
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit)
values
  ('avatars',    'avatars',    false, 5242880),   -- 5 MB
  ('post-media', 'post-media', false, 52428800),  -- 50 MB
  ('chat-media', 'chat-media', false, 52428800)   -- 50 MB
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit;

create or replace function private.is_post_author(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.posts p
    where p.id = p_post_id
      and p.author_id = private.current_profile_id()
      and p.deleted_at is null
  );
$$;

revoke all on function private.is_post_author(uuid) from public;
grant execute on function private.is_post_author(uuid) to authenticated, service_role;

-- Avatars -----------------------------------------------------------------------
create policy avatars_select on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and private.current_profile_id() is not null);

create policy avatars_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (private.try_uuid((storage.foldername(name))[1]) = private.current_profile_id() or private.is_admin())
  );

create policy avatars_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (private.try_uuid((storage.foldername(name))[1]) = private.current_profile_id() or private.is_admin())
  );

create policy avatars_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (private.try_uuid((storage.foldername(name))[1]) = private.current_profile_id() or private.is_admin())
  );

-- Post media ----------------------------------------------------------------------
create policy post_media_select on storage.objects
  for select to authenticated
  using (bucket_id = 'post-media' and private.can_view_post(private.try_uuid((storage.foldername(name))[1])));

create policy post_media_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'post-media' and private.is_post_author(private.try_uuid((storage.foldername(name))[1])));

create policy post_media_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'post-media'
    and (
      private.is_post_author(private.try_uuid((storage.foldername(name))[1]))
      or private.can_moderate_post(private.try_uuid((storage.foldername(name))[1]))
    )
  );

-- Chat media (members only, no admin exception) -----------------------------------
create policy chat_media_select on storage.objects
  for select to authenticated
  using (bucket_id = 'chat-media' and private.is_conversation_member(private.try_uuid((storage.foldername(name))[1])));

create policy chat_media_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'chat-media' and private.is_conversation_member(private.try_uuid((storage.foldername(name))[1])));

create policy chat_media_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'chat-media'
    and owner_id = auth.uid()::text
    and private.is_conversation_member(private.try_uuid((storage.foldername(name))[1]))
  );

-- Realtime ------------------------------------------------------------------------
-- Live updates respect the same RLS rules: you only receive rows you may read.
-- Typing indicators and online presence use Realtime channels, not tables.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.messages,
      public.message_receipts,
      public.message_reactions,
      public.conversation_members,
      public.conversations,
      public.notifications,
      public.posts,
      public.comments,
      public.reactions;
  end if;
end;
$$;
