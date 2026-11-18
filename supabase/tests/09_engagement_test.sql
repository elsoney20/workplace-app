-- =============================================================================
-- Birthdays, events, kudos, polls and the home side columns.
-- =============================================================================
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

create temp table t_e (k text primary key, id uuid);
grant all on t_e to authenticated;

-- Employee1 sets a birthday; the year never shows.
select tests.login('00000000-0000-0000-0000-00000000000c');
insert into t_e values ('emp1', private.current_profile_id());
select public.set_my_birthday((current_date - interval '25 years')::date);
select tests.ok(public.get_my_birthday() = (current_date - interval '25 years')::date, 'I can set my birthday');
select tests.fails('select birthday from public.profiles limit 1', 'birthdays are not readable directly');
select tests.fails($$select public.set_my_birthday(current_date + 1)$$, 'birthday cannot be in the future');
select tests.fails($$update public.profiles set hired_on = current_date where id = private.current_profile_id()$$,
  'employees cannot change their hire date');
select tests.ok(jsonb_array_length(public.get_home_sidebar() -> 'birthdays') = 1, 'today''s birthday is in the side column');
select tests.ok((public.get_home_sidebar() -> 'birthdays' -> 0 ->> 'days_until')::int = 0, 'it says today');
select tests.ok(not (public.get_home_sidebar() -> 'birthdays' -> 0 ? 'birthday'), 'no birth year in the side column');
select tests.fails($$insert into public.events (title, starts_at) values ('x', now() + interval '1 day')$$,
  'employees cannot create events');
select tests.logout();

-- Admin: hire dates, events.
select tests.login_admin();
insert into t_e values ('admin', private.current_profile_id());
select public.admin_set_hired_on((select id from t_e where k = 'emp1'), (current_date + 2 - interval '4 years')::date);
select tests.ok((public.get_home_sidebar() -> 'anniversaries' -> 0 ->> 'years')::int = 4, 'work anniversary with years');
with x as (insert into public.events (title, starts_at, kind) values ('بطولة', now() + interval '2 days', 'tournament') returning id)
insert into t_e select 'event', id from x;
insert into public.events (title, starts_at) values ('قديم', now() - interval '2 days');
select tests.ok(jsonb_array_length(public.get_home_sidebar() -> 'events') = 1, 'only upcoming events show');
select tests.logout();

-- Employee1: going, kudos, polls.
select tests.login('00000000-0000-0000-0000-00000000000c');
insert into public.event_attendees (event_id) values ((select id from t_e where k = 'event'));
select tests.ok((public.get_home_sidebar() -> 'events' -> 0 ->> 'i_am_going')::boolean, 'I am going');
delete from public.events where id = (select id from t_e where k = 'event');
select tests.ok(exists (select 1 from public.events where id = (select id from t_e where k = 'event')),
  'employees cannot delete others'' events');
select tests.fails($$insert into public.kudos (to_id, badge) values (private.current_profile_id(), 'mvp')$$,
  'no kudos to myself');
insert into public.kudos (to_id, badge, message) values ((select id from t_e where k = 'admin'), 'thanks', 'شكراً');
select tests.fails($$insert into public.kudos (from_id, to_id, badge) values ((select id from t_e where k = 'admin'), private.current_profile_id(), 'mvp')$$,
  'cannot send kudos as someone else');
select tests.ok((public.get_home_sidebar() -> 'heroes' -> 0 -> 'person' ->> 'id')::uuid = (select id from t_e where k = 'admin'),
  'kudos make a hero of the week');
with x as (insert into public.posts (author_id, body) values (private.current_profile_id(), 'غدا؟') returning id)
insert into t_e select 'poll', id from x;
select tests.fails($$select public.create_poll((select id from t_e where k = 'poll'), 'نطلب إيه؟', array['بيتزا'])$$,
  'a poll needs two choices');
select public.create_poll((select id from t_e where k = 'poll'), 'نطلب إيه؟', array['بيتزا', 'كشري', ' ']);
select tests.ok(jsonb_array_length((select poll -> 'options' from public.get_polls(array[(select id from t_e where k = 'poll')]))) = 2,
  'empty choices are dropped');
select tests.logout();

select tests.login_admin();
select tests.ok((select count(*) from public.notifications where recipient_id = private.current_profile_id() and type = 'kudos') = 1,
  'kudos notify the colleague');
select tests.fails($$select public.create_poll((select id from t_e where k = 'poll'), 'x', array['a', 'b'])$$,
  'only the author adds a poll');
select public.vote_poll((select id from t_e where k = 'poll'),
  (select (poll -> 'options' -> 0 ->> 'id')::uuid from public.get_polls(array[(select id from t_e where k = 'poll')])));
select public.vote_poll((select id from t_e where k = 'poll'),
  (select (poll -> 'options' -> 1 ->> 'id')::uuid from public.get_polls(array[(select id from t_e where k = 'poll')])));
select tests.ok((select (poll ->> 'total')::int from public.get_polls(array[(select id from t_e where k = 'poll')])) = 1,
  'changing my vote keeps one vote');
select tests.ok((select poll -> 'options' -> 1 ->> 'votes' from public.get_polls(array[(select id from t_e where k = 'poll')])) = '1',
  'the vote moved');
select tests.fails($$insert into public.poll_votes (post_id, option_id) values ((select id from t_e where k = 'poll'),
  (select (poll -> 'options' -> 0 ->> 'id')::uuid from public.get_polls(array[(select id from t_e where k = 'poll')])))$$,
  'votes only through vote_poll');
select tests.ok(jsonb_array_length(public.get_people(array[(select id from t_e where k = 'emp1')])) = 1, 'people cards by id');

-- Demo extras.
select tests.fails('select public.seed_demo_extras()', 'extras need the demo content first');
select public.seed_demo_content();
select public.seed_demo_extras();
select public.seed_demo_extras(); -- twice is fine
select tests.ok((select count(*) from public.events where id::text like 'de800000-%') = 3, 'demo events');
select tests.ok(jsonb_array_length(public.get_home_sidebar() -> 'new_joiners') = 2, 'demo new joiners');
select tests.ok((select count(*) from public.get_polls(array['de700000-0000-0000-0000-0000000000a1'::uuid])) = 1, 'demo poll');
select public.remove_demo_content();
select tests.ok((select count(*) from public.events where id::text like 'de800000-%') = 0, 'remove clears demo events');
select tests.ok(not exists (select 1 from public.kudos k join public.profiles p on p.id = k.from_id where p.id::text like 'de300000-%'),
  'remove clears demo kudos');
select tests.ok(not exists (select 1 from public.posts where id = 'de700000-0000-0000-0000-0000000000a1'), 'remove clears the demo poll');
select tests.logout();

\echo 'ALL ENGAGEMENT TESTS PASSED'
