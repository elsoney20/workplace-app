-- =============================================================================
-- Tests for Phase 4 (groups & departments). Runs after 01–03 and reuses
-- their fixtures (see 03_feed_test.sql header). tests.login_admin() is
-- defined in 03.
--   Department "Sales" (d..01): manager = Manager (a..02), member Employee1 (a..03)
-- =============================================================================
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

-- ----------------------------------------------------------- create group ---
select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
select tests.fails($$select public.create_group('Football club')$$, 'employees cannot create groups');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000b'); -- Manager
create temp table t_ids (name text primary key, id uuid);
grant all on t_ids to public;
insert into t_ids values ('public', public.create_group('Football club', 'Fridays 6pm', 'public'));
insert into t_ids values ('private', public.create_group('Project X', null, 'private'));
select tests.ok((select my_role from public.list_groups() where id = (select id from t_ids where name = 'public')) = 'owner',
  'the creator becomes the owner');
select tests.ok((select count(*) from public.list_groups(p_only_mine => true)) = 4,
  'my groups: two new groups + Sales department group + Phase 1 test group');
select tests.ok((select can_moderate from public.list_groups() g join public.departments d on d.id = g.department_id
                 where d.name_en = 'Sales'),
  'the department manager moderates the department group');
select tests.logout();

-- --------------------------------------------------------- public / private -
select tests.login('00000000-0000-0000-0000-00000000005e'); -- Employee3
select tests.ok((select count(*) from public.list_groups() where id = (select id from t_ids where name = 'public')) = 1,
  'everyone can find a public group');
select tests.ok((select count(*) from public.list_groups() where id = (select id from t_ids where name = 'private')) = 0,
  'private groups are hidden from non-members');
select tests.ok((select count(*) from public.list_groups() g where g.department_id is not null) = 0,
  'other departments'' groups are hidden');
select tests.fails($$insert into public.posts (author_id, group_id, body)
  values ('a0000000-0000-0000-0000-000000000005', (select id from t_ids where name = 'public'), 'hi')$$,
  'you must join a group before posting in it');
insert into public.group_members (group_id, profile_id)
values ((select id from t_ids where name = 'public'), 'a0000000-0000-0000-0000-000000000005');
select tests.ok((select my_role from public.list_groups() where id = (select id from t_ids where name = 'public')) = 'member',
  'anyone can join a public group');
insert into public.posts (id, author_id, group_id, body)
values ('b4000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000005',
        (select id from t_ids where name = 'public'), 'Match on Friday #football');
select tests.ok((select count(*) from public.get_feed(p_group_id => (select id from t_ids where name = 'public'))) = 1,
  'members can post in the group feed');
select tests.ok((select count(*) from public.get_feed() where id = 'b4000000-0000-0000-0000-000000000001') = 0,
  'group posts do not appear in the company feed');
select tests.fails($$insert into public.group_members (group_id, profile_id)
  values ((select id from t_ids where name = 'private'), 'a0000000-0000-0000-0000-000000000005')$$,
  'nobody can join a private group by themselves');
select tests.fails($$update public.group_members set role = 'moderator'
  where profile_id = 'a0000000-0000-0000-0000-000000000005'$$,
  'members cannot promote themselves');
select tests.logout();

-- ------------------------------------------------------------ invitations ---
select tests.login('00000000-0000-0000-0000-00000000000b'); -- Manager (owner of Project X)
insert into public.group_members (group_id, profile_id)
values ((select id from t_ids where name = 'private'), 'a0000000-0000-0000-0000-000000000005');
select tests.ok((select member_count from public.list_groups() where id = (select id from t_ids where name = 'private')) = 2,
  'a moderator can invite people into a private group');
update public.group_members set role = 'moderator'
where group_id = (select id from t_ids where name = 'private') and profile_id = 'a0000000-0000-0000-0000-000000000005';
select tests.fails($$delete from public.group_members
  where group_id = (select id from t_ids where name = 'private') and profile_id = 'a0000000-0000-0000-0000-000000000002'$$,
  'the last owner cannot leave the group');
select tests.fails($$delete from public.group_members gm using public.groups g
  where g.id = gm.group_id and g.department_id is not null and gm.profile_id = 'a0000000-0000-0000-0000-000000000003'$$,
  'department group members cannot be removed by hand (they follow the department)');
select tests.fails($$update public.groups set privacy = 'public' where department_id is not null$$,
  'department groups stay private');
select tests.logout();

select tests.ok((select count(*) from public.notifications where recipient_id = 'a0000000-0000-0000-0000-000000000005'
                 and type = 'group_invite' and target ->> 'group_id' = (select id::text from t_ids where name = 'private')) = 1,
  'the invited person gets a notification');
select tests.ok((select count(*) from public.notifications where type = 'group_invite'
                 and recipient_id = 'a0000000-0000-0000-0000-000000000002') = 0,
  'creating your own group does not notify you');

select tests.login('00000000-0000-0000-0000-00000000005e'); -- Employee3, now a moderator of Project X
select tests.ok((select count(*) from public.list_groups() where id = (select id from t_ids where name = 'private')) = 1,
  'invited members can see the private group');
select tests.ok((select count(*) from public.get_group_members((select id from t_ids where name = 'private'))) = 2,
  'members see the member list');
select tests.ok((select bool_and(not (person ? 'phone')) from public.get_group_members((select id from t_ids where name = 'private'))),
  'member list never shows phone numbers');
select tests.fails($$update public.group_members set role = 'owner'
  where group_id = (select id from t_ids where name = 'private') and profile_id = 'a0000000-0000-0000-0000-000000000005'$$,
  'moderators cannot make themselves owner');
select tests.fails($$insert into public.group_members (group_id, profile_id, role)
  values ((select id from t_ids where name = 'private'), 'a0000000-0000-0000-0000-000000000003', 'owner')$$,
  'moderators cannot add a new owner');
-- Moderator can pin an announcement in their group feed.
insert into public.posts (id, author_id, group_id, body, is_announcement, is_pinned)
values ('b4000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000005',
        (select id from t_ids where name = 'private'), 'Deadline moved', true, true);
select tests.ok((select audience_count from public.get_feed(p_group_id => (select id from t_ids where name = 'private'), p_pinned => true)) = 2,
  'group announcements count the group members as audience');
update public.group_members set muted = true
where group_id = (select id from t_ids where name = 'private') and profile_id = 'a0000000-0000-0000-0000-000000000005';
select tests.ok((select muted from public.list_groups() where id = (select id from t_ids where name = 'private')),
  'members can mute a group for themselves');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1, not in Project X
select tests.ok((select count(*) from public.get_feed(p_post_id => 'b4000000-0000-0000-0000-000000000002')) = 0,
  'non-members cannot read private group posts');
select tests.ok((select count(*) from public.get_group_members((select id from t_ids where name = 'private'))) = 0,
  'non-members cannot see who is in a private group');
select tests.logout();

-- Mentioning a non-member in a private group does not notify them.
select tests.login('00000000-0000-0000-0000-00000000005e');
insert into public.posts (author_id, group_id, body)
values ('a0000000-0000-0000-0000-000000000005', (select id from t_ids where name = 'private'),
        'FYI @[Employee1](a0000000-0000-0000-0000-000000000003)');
select tests.logout();
select tests.ok((select count(*) from public.notifications n where n.recipient_id = 'a0000000-0000-0000-0000-000000000003'
                 and n.type = 'mention' and (n.target ->> 'post_id')::uuid in
                 (select id from public.posts where group_id = (select id from t_ids where name = 'private'))) = 0,
  'people outside a private group are not notified about its posts');

-- ------------------------------------------------------------ departments --
select tests.login_admin();
update public.departments set name_en = 'Sales & Marketing' where id = 'd0000000-0000-0000-0000-000000000001';
select tests.ok((select name from public.groups where department_id = 'd0000000-0000-0000-0000-000000000001') = 'Sales & Marketing',
  'renaming a department renames its group');
update public.profiles set department_id = 'd0000000-0000-0000-0000-000000000001' where id = 'a0000000-0000-0000-0000-000000000005';
select tests.ok((select count(*) from public.get_group_members(
                  (select id from public.groups where department_id = 'd0000000-0000-0000-0000-000000000001'))
                 where person ->> 'id' = 'a0000000-0000-0000-0000-000000000005') = 1,
  'moving an employee into a department adds them to its group');
select tests.ok((select count(*) from public.list_groups()) >= 3, 'admins see all groups, including private ones');
select tests.logout();

set role anon;
select tests.fails('select * from public.list_groups()', 'logged-out users cannot list groups');
reset role;

\echo 'ALL PHASE 4 GROUP TESTS PASSED'
