-- =============================================================================
-- Regression test: the app creates posts with INSERT ... RETURNING id.
-- Reuses fixtures from 01–06 (tests.login_admin() is defined in 03).
-- =============================================================================
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

select tests.login_admin();
do $$
declare v uuid;
begin
  insert into public.posts (author_id, body, is_announcement, is_pinned)
  values (private.current_profile_id(), 'Bonus today ❤️', true, true)
  returning id into v;
  perform tests.ok(v is not null, 'an admin can create a pinned announcement and get its id back');
end $$;
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
do $$
declare v uuid;
begin
  insert into public.posts (author_id, body)
  values (private.current_profile_id(), 'Hello team')
  returning id into v;
  perform tests.ok(v is not null, 'an employee can create a post and get its id back');
end $$;
select tests.fails($$insert into public.posts (author_id, body, is_announcement)
  values (private.current_profile_id(), 'fake', true)$$,
  'employees still cannot post announcements');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000005e'); -- Employee3 (not in Project X)
select tests.ok((select count(*) from public.posts p join public.groups g on g.id = p.group_id
                 where g.privacy = 'private' and not exists (
                   select 1 from public.group_members gm where gm.group_id = g.id
                     and gm.profile_id = private.current_profile_id())) = 0,
  'private group posts stay hidden from non-members');
select tests.logout();

\echo 'ALL POST INSERT TESTS PASSED'
