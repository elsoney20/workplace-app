-- =============================================================================
-- Security + behaviour tests for Phase 3 (feed). Runs after 01 and 02 on the
-- same throwaway database and reuses their fixtures:
--   Admin     profile a..01 / login ..0a  (has an authenticator app → aal2)
--   Manager   profile a..02 / login ..0b
--   Employee1 profile a..03 / login ..0c
--   Employee2 profile a..04 / login ..0d
--   Employee3 profile a..05 / login ..5e (changed in 02)
-- =============================================================================
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

create function tests.login_admin() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-00000000000a', 'role', 'authenticated', 'aal', 'aal2')::text, false);
  execute 'set role authenticated';
end;
$$;
grant execute on function tests.login_admin() to public;

-- ------------------------------------------------------------- hashtags ------
select tests.ok(
  (select array_agg(t order by t) from unnest(private.extract_hashtags('Hello #Sales and #مبيعات_2026 #sales')) t)
  = array['sales', 'مبيعات_2026'],
  'hashtags are found in English and Arabic, lower-cased, without duplicates');
select tests.ok(
  private.extract_mention_ids('Hi @[Employee3](a0000000-0000-0000-0000-000000000005) and @[x](not-a-uuid)')
  = array['a0000000-0000-0000-0000-000000000005'::uuid],
  'mention markup is parsed; invalid ids are ignored');

-- ------------------------------------------------------------ new post -------
select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
insert into public.posts (id, author_id, body) values (
  'b3000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003',
  'Great quarter #Sales #مبيعات thanks @[Employee3](a0000000-0000-0000-0000-000000000005) @[Me](a0000000-0000-0000-0000-000000000003)');

select tests.ok((select count(*) from public.post_hashtags where post_id = 'b3000000-0000-0000-0000-000000000001') = 2,
  'hashtags of a new post are saved automatically');
select tests.ok((select count(*) from public.mentions where post_id = 'b3000000-0000-0000-0000-000000000001') = 1,
  'mentions are saved automatically (mentioning yourself is ignored)');
select tests.fails($$insert into public.mentions (post_id, mentioned_id)
  values ('b3000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002')$$,
  'the app cannot insert fake mentions directly');
select tests.fails($$insert into public.hashtags (tag) values ('spam')$$,
  'the app cannot insert hashtags directly');

select tests.ok((select count(*) from public.get_feed(p_hashtag => 'sales') where id = 'b3000000-0000-0000-0000-000000000001') = 1,
  'feed can be filtered by hashtag');
select tests.ok((select count(*) from public.get_feed(p_hashtag => '#مبيعات')) = 1,
  'Arabic hashtag filter works (leading # is ignored)');
select tests.ok((select count(*) from public.get_trending_hashtags() where tag = 'sales') = 1,
  'trending hashtags include the new tag');
select tests.ok((select author ->> 'full_name' from public.get_feed() where id = 'b3000000-0000-0000-0000-000000000001') = 'Employee1',
  'feed rows include the author name');
select tests.ok((select author ? 'phone' from public.get_feed() where id = 'b3000000-0000-0000-0000-000000000001') = false,
  'feed rows never include phone numbers');

select tests.ok((select count(*) from public.get_feed(p_post_id => 'b3000000-0000-0000-0000-000000000001')) = 1,
  'a single post can be opened by id');

-- Editing the text updates hashtags and mentions.
update public.posts set body = 'Edited #Q4 for @[Manager](a0000000-0000-0000-0000-000000000002)'
where id = 'b3000000-0000-0000-0000-000000000001';
select tests.ok((select array_agg(h.tag) from public.post_hashtags ph join public.hashtags h on h.id = ph.hashtag_id
                 where ph.post_id = 'b3000000-0000-0000-0000-000000000001') = array['q4'],
  'editing a post replaces its hashtags');
select tests.ok((select array_agg(mentioned_id) from public.mentions where post_id = 'b3000000-0000-0000-0000-000000000001')
                = array['a0000000-0000-0000-0000-000000000002'::uuid],
  'editing a post replaces its mentions');
select tests.logout();

select tests.ok((select count(*) from public.notifications
                 where recipient_id = 'a0000000-0000-0000-0000-000000000005' and type = 'mention'
                   and target ->> 'post_id' = 'b3000000-0000-0000-0000-000000000001') = 1,
  'a mentioned person gets a notification');
select tests.ok((select count(*) from public.notifications
                 where recipient_id = 'a0000000-0000-0000-0000-000000000003' and type = 'mention') = 0,
  'mentioning yourself does not notify you');

-- --------------------------------------------------------- attachments -------
select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
insert into public.post_attachments (post_id, storage_path, kind, mime_type, file_name, size_bytes)
values ('b3000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001/photo.jpg', 'image', 'image/jpeg', 'photo.jpg', 1000);
select tests.ok((select jsonb_array_length(attachments) from public.get_feed() where id = 'b3000000-0000-0000-0000-000000000001') = 1,
  'feed rows include attachments');
select tests.fails($$insert into public.post_attachments (post_id, storage_path, kind, size_bytes)
  values ('b3000000-0000-0000-0000-000000000001', 'someone-else/photo.jpg', 'image', 1000)$$,
  'attachments must be stored in their own post folder');
select tests.fails($$insert into public.post_attachments (post_id, storage_path, kind, size_bytes)
  values ('b3000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001/big.mp4', 'video', 52428801)$$,
  'files over 50 MB are refused');
insert into storage.objects (bucket_id, name) values ('post-media', 'b3000000-0000-0000-0000-000000000001/photo.jpg');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000005e'); -- Employee3
select tests.fails($$insert into storage.objects (bucket_id, name) values ('post-media', 'b3000000-0000-0000-0000-000000000001/evil.jpg')$$,
  'only the author can upload files into a post');
select tests.ok((select count(*) from storage.objects where bucket_id = 'post-media'
                 and name = 'b3000000-0000-0000-0000-000000000001/photo.jpg') = 1,
  'other employees can open the files of a post they can see');

-- ---------------------------------------------------- comments & reactions ---
insert into public.comments (id, post_id, author_id, body)
values ('c3000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000005', 'Congrats!');
insert into public.reactions (profile_id, post_id, emoji)
values ('a0000000-0000-0000-0000-000000000005', 'b3000000-0000-0000-0000-000000000001', '🎉');
select tests.ok((select reactions ->> '🎉' from public.get_feed() where id = 'b3000000-0000-0000-0000-000000000001') = '1',
  'reaction counts are grouped by emoji');
select tests.ok((select my_reaction from public.get_feed() where id = 'b3000000-0000-0000-0000-000000000001') = '🎉',
  'feed shows my own reaction');
update public.reactions set emoji = '❤️'
where profile_id = 'a0000000-0000-0000-0000-000000000005' and post_id = 'b3000000-0000-0000-0000-000000000001';
select tests.ok((select reactions from public.get_feed() where id = 'b3000000-0000-0000-0000-000000000001') = '{"❤️": 1}'::jsonb,
  'changing my reaction replaces it');
select tests.fails($$insert into public.reactions (profile_id, post_id, emoji)
  values ('a0000000-0000-0000-0000-000000000005', 'b3000000-0000-0000-0000-000000000001', '😂')$$,
  'one reaction per person per post');
select tests.ok((select count(*) from public.get_reactors(p_post_id => 'b3000000-0000-0000-0000-000000000001')) = 1,
  'the reactions list shows who reacted');
select tests.ok((select comment_count from public.get_feed() where id = 'b3000000-0000-0000-0000-000000000001') = 1,
  'feed shows the comment count');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1 replies
insert into public.comments (post_id, author_id, parent_id, body)
values ('b3000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003',
        'c3000000-0000-0000-0000-000000000001', 'Thanks @[Employee2](a0000000-0000-0000-0000-000000000004)');
select tests.ok((select count(*) from public.get_post_comments('b3000000-0000-0000-0000-000000000001')) = 2,
  'comments and replies are listed');
select tests.logout();

select tests.ok((select count(*) from public.notifications where recipient_id = 'a0000000-0000-0000-0000-000000000003'
                 and type = 'comment' and target ->> 'comment_id' = 'c3000000-0000-0000-0000-000000000001') = 1,
  'the post author is notified about a new comment');
select tests.ok((select count(*) from public.notifications where recipient_id = 'a0000000-0000-0000-0000-000000000005'
                 and type = 'reply') = 1,
  'the comment author is notified about a reply');
select tests.ok((select count(*) from public.notifications where recipient_id = 'a0000000-0000-0000-0000-000000000004'
                 and type = 'mention' and target ? 'comment_id') = 1,
  'mentions inside comments notify too');

-- ----------------------------------------------------- announcements --------
select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
select tests.fails($$insert into public.posts (author_id, body, is_announcement, is_pinned)
  values ('a0000000-0000-0000-0000-000000000003', 'Fake announcement', true, true)$$,
  'employees cannot post company announcements');
select tests.logout();

select tests.login_admin();
insert into public.posts (id, author_id, body, is_announcement, is_pinned)
values ('b3000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Office closed Thursday', true, true);
select tests.ok((select count(*) from public.get_feed(p_pinned => true) where id = 'b3000000-0000-0000-0000-000000000002') = 1,
  'pinned announcements are listed separately');
select tests.ok((select count(*) from public.get_feed(p_pinned => false) where id = 'b3000000-0000-0000-0000-000000000002') = 0,
  'pinned announcements are not repeated in the normal feed');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1 sees it
select public.mark_announcement_seen('b3000000-0000-0000-0000-000000000002');
select public.mark_announcement_seen('b3000000-0000-0000-0000-000000000002'); -- twice is fine
select public.mark_announcement_seen('b3000000-0000-0000-0000-000000000001'); -- not an announcement: ignored
select tests.ok((select seen_by_me from public.get_feed(p_pinned => true) where id = 'b3000000-0000-0000-0000-000000000002'),
  'marking an announcement as seen works');
select tests.ok((select count(*) from public.announcement_views where post_id = 'b3000000-0000-0000-0000-000000000001') = 0,
  'normal posts do not get a seen-by list');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000005e'); -- Employee3
select public.mark_announcement_seen('b3000000-0000-0000-0000-000000000002');
select tests.ok((select count(*) from public.get_announcement_viewers('b3000000-0000-0000-0000-000000000002')) = 1,
  'employees only see themselves in the seen-by list');
select tests.logout();

select tests.login_admin();
select tests.ok((select count(*) from public.get_announcement_viewers('b3000000-0000-0000-0000-000000000002')) = 2,
  'the announcement author sees everyone who saw it');
select tests.ok((select seen_count from public.get_feed(p_pinned => true) where id = 'b3000000-0000-0000-0000-000000000002') = 2,
  'the author sees the seen count');
select tests.ok((select audience_count from public.get_feed(p_pinned => true) where id = 'b3000000-0000-0000-0000-000000000002') >= 5,
  'the author sees how many employees could see it');
update public.posts set is_pinned = false where id = 'b3000000-0000-0000-0000-000000000002';
select tests.ok((select count(*) from public.get_feed(p_pinned => true) where id = 'b3000000-0000-0000-0000-000000000002') = 0,
  'admin can unpin an announcement');
update public.posts set comments_locked = true where id = 'b3000000-0000-0000-0000-000000000001';
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000005e'); -- Employee3
select tests.fails($$insert into public.comments (post_id, author_id, body)
  values ('b3000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000005', 'late')$$,
  'nobody can comment once comments are locked');
select tests.ok((select count(*) from public.search_people('employ')) >= 3, 'people search finds employees for @mentions');
select tests.ok((select bool_and(not (person ? 'phone')) from public.search_people('')), 'people search never returns phones');
select tests.logout();

-- -------------------------------------------------------- soft delete -------
select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1 deletes own post
update public.posts set deleted_at = now() where id = 'b3000000-0000-0000-0000-000000000001';
select tests.ok((select count(*) from public.get_feed() where id = 'b3000000-0000-0000-0000-000000000001') = 0,
  'a deleted post disappears from the feed');
select tests.logout();

set role anon;
select tests.fails('select * from public.get_feed()', 'logged-out users cannot read the feed');
select tests.fails('select * from public.search_people(''a'')', 'logged-out users cannot search people');
reset role;

\echo 'ALL PHASE 3 FEED TESTS PASSED'
