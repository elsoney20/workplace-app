-- =============================================================================
-- Fix: creating a post failed with "new row violates row-level security".
-- The app inserts a post and asks for its id back (INSERT ... RETURNING).
-- The read rule called private.can_view_post(id), which looks the post up in
-- the table again, but a brand-new row is not visible to that lookup inside the
-- same statement. So every post creation was refused.
-- The read rule now checks the row's own columns instead (same meaning).
-- Authors also keep seeing their own deleted post, so deleting it (an UPDATE
-- whose new row must stay readable) works; the feed still hides deleted posts.
-- =============================================================================
create or replace function private.can_view_post_row(p_group_id uuid, p_deleted_at timestamptz, p_author_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_profile_id() is not null
     and (p_group_id is null or private.can_view_group(p_group_id))
     and (p_deleted_at is null or p_author_id = private.current_profile_id() or private.can_moderate_feed(p_group_id));
$$;

revoke all on function private.can_view_post_row(uuid, timestamptz, uuid) from public;
grant execute on function private.can_view_post_row(uuid, timestamptz, uuid) to authenticated, service_role;

drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts
  for select to authenticated using (private.can_view_post_row(group_id, deleted_at, author_id));
