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
select tests.ok((select count(*) from public.get_feed() where id::text like 'de700000-%') = 4, 'demo posts show in the company feed');
select tests.ok((select count(*) from public.list_conversations() where id::text like 'de500000-%') = 3, 'the admin has three demo chats');
select tests.ok((select unread_count from public.list_conversations() where id = 'de500000-0000-0000-0000-000000000002') = 2,
  'unread demo messages are counted');
select tests.ok((select count(*) from public.notifications where recipient_id = private.current_profile_id() and type = 'mention') >= 1,
  'the admin is notified about the demo mention');
select tests.fails('select public.seed_demo_content()', 'loading twice is refused');

-- A photo post made by the admin is handed to a demo colleague.
create temp table t_demo (id uuid);
grant all on t_demo to authenticated;
with x as (
  insert into public.posts (author_id, body)
  values (private.current_profile_id(), 'PS5 Pro وصل #PS5') returning id
)
insert into t_demo select id from x;
select public.adopt_demo_post(
  (select id from t_demo), 'de300000-0000-0000-0000-000000000002', 90,
  '[{"by": "de300000-0000-0000-0000-000000000004", "body": "تحفة 🔥", "minutes_ago": 30}]'::jsonb
);
select tests.ok((select author_id from public.posts where id = (select id from t_demo)) = 'de300000-0000-0000-0000-000000000002',
  'adopted post now belongs to the demo colleague');
select tests.ok((select count(*) from public.comments where post_id = (select id from t_demo)) = 1, 'adopted post gets its comments');
select tests.ok((select count(*) from public.reactions where post_id = (select id from t_demo)) = 5, 'the other colleagues react');
select tests.fails($$select public.adopt_demo_post('de700000-0000-0000-0000-000000000001', 'de300000-0000-0000-0000-000000000002', 1)$$,
  'cannot adopt a post that is not mine');
select tests.fails($$select public.adopt_demo_post((select id from t_demo), private.current_profile_id(), 1)$$,
  'can only hand posts to demo colleagues');
select public.remove_demo_content();
select tests.ok((select count(*) from public.profiles where id::text like 'de300000-%') = 0, 'remove deletes the demo colleagues');
select tests.ok((select count(*) from public.conversations where id::text like 'de500000-%') = 0, 'remove deletes the demo chats');
select tests.ok((select count(*) from public.departments where id::text like 'de400000-%') = 0, 'remove deletes the demo departments');
select tests.ok(not exists (select 1 from public.posts where id = (select id from t_demo)), 'remove deletes adopted posts');
select tests.logout();

\echo 'ALL DEMO CONTENT TESTS PASSED'
