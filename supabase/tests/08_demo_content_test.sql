-- =============================================================================
-- Demo content loader (admin only) and its clean removal.
-- =============================================================================
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
select tests.fails('select public.seed_demo_content()', 'employees cannot load demo content');
select tests.logout();

select tests.login_admin();
select public.seed_demo_content();
select tests.ok((select count(*) from public.profiles where id::text like 'de300000-%') = 6, 'six demo colleagues are added');
select tests.ok((select count(*) from public.get_feed() where id::text like 'de700000-%') = 5, 'demo posts show in the company feed');
select tests.ok((select count(*) from public.list_conversations() where id::text like 'de500000-%') = 3, 'the admin has three demo chats');
select tests.ok((select unread_count from public.list_conversations() where id = 'de500000-0000-0000-0000-000000000002') = 2,
  'unread demo messages are counted');
select tests.ok((select count(*) from public.notifications where recipient_id = private.current_profile_id() and type = 'mention') >= 1,
  'the admin is notified about the demo mention');
select tests.fails('select public.seed_demo_content()', 'loading twice is refused');
select public.remove_demo_content();
select tests.ok((select count(*) from public.profiles where id::text like 'de300000-%') = 0, 'remove deletes the demo colleagues');
select tests.ok((select count(*) from public.conversations where id::text like 'de500000-%') = 0, 'remove deletes the demo chats');
select tests.ok((select count(*) from public.departments where id::text like 'de400000-%') = 0, 'remove deletes the demo departments');
select tests.logout();

\echo 'ALL DEMO CONTENT TESTS PASSED'
