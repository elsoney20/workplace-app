-- =============================================================================
-- Security tests for the Phase 1 schema. Run on a THROWAWAY database after
-- 00_supabase_stub.sql and all migrations (see scripts/test_db.sh).
-- Any failed check stops the script with "TEST FAILED: ...".
-- =============================================================================
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

create schema tests;
grant usage on schema tests to public;

create function tests.ok(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'TEST FAILED: %', p_label using errcode = 'T0001';
  end if;
  raise notice 'ok - %', p_label;
end;
$$;

-- Runs a statement that MUST fail.
create function tests.fails(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'ok - % (blocked: %)', p_label, sqlerrm;
    return;
  end;
  raise exception 'TEST FAILED: % (statement was allowed)', p_label using errcode = 'T0001';
end;
$$;

-- Switch to an app user (by auth id), or back to the server role.
create function tests.login(p_auth_id uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_auth_id, 'role', 'authenticated')::text, false);
  execute 'set role authenticated';
end;
$$;

create function tests.logout() returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', false);
end;
$$;

grant execute on all functions in schema tests to public;

-- -----------------------------------------------------------------------------
-- Fixtures (as the server): one department, 5 employees.
-- -----------------------------------------------------------------------------
insert into public.departments (id, name_ar, name_en)
values ('d0000000-0000-0000-0000-000000000001', 'المبيعات', 'Sales');

insert into public.profiles (id, phone, full_name, role, department_id, phone_visibility) values
  ('a0000000-0000-0000-0000-000000000001', '+201000000001', 'Admin',    'admin',    null, 'everyone'),
  ('a0000000-0000-0000-0000-000000000002', '+201000000002', 'Manager',  'manager',  'd0000000-0000-0000-0000-000000000001', 'everyone'),
  ('a0000000-0000-0000-0000-000000000003', '+201000000003', 'Employee1','employee', 'd0000000-0000-0000-0000-000000000001', 'nobody'),
  ('a0000000-0000-0000-0000-000000000004', '+201000000004', 'Employee2','employee', null, 'managers'),
  ('a0000000-0000-0000-0000-000000000005', '+201000000005', 'Employee3','employee', null, 'everyone');

update public.departments set manager_id = 'a0000000-0000-0000-0000-000000000002'
where id = 'd0000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------- allowlist ---
select tests.ok(public.hook_before_user_created('{"user":{"phone":"201999999999"}}') ? 'error',
  'unregistered phone is rejected before sign-up');
select tests.ok(public.hook_before_user_created('{"user":{"email":"x@y.com"}}') ? 'error',
  'email sign-up is rejected');
select tests.ok(public.hook_before_user_created('{"user":{"phone":"201000000003"}}') = '{}'::jsonb,
  'registered phone is accepted');

-- First logins (auth creates the users; the trigger links profiles).
insert into auth.users (id, phone) values
  ('00000000-0000-0000-0000-00000000000a', '201000000001'),
  ('00000000-0000-0000-0000-00000000000b', '201000000002'),
  ('00000000-0000-0000-0000-00000000000c', '201000000003'),
  ('00000000-0000-0000-0000-00000000000d', '201000000004'),
  ('00000000-0000-0000-0000-00000000000e', '201000000005');

select tests.ok((select count(*) from public.profiles where auth_user_id is not null) = 5,
  'auth accounts are linked to profiles on first login');
select tests.ok(public.hook_before_user_created('{"user":{"phone":"201000000003"}}') ? 'error',
  'an already-linked phone cannot create a second account');
select tests.ok(public.hook_custom_access_token(
  '{"user_id":"00000000-0000-0000-0000-00000000000c","claims":{"sub":"x"}}') -> 'claims' ->> 'app_role' = 'employee',
  'access token carries the app role');

-- --------------------------------------------------------- department group ---
select tests.ok((select count(*) from public.groups where department_id = 'd0000000-0000-0000-0000-000000000001') = 1,
  'a department gets its own group automatically');
select tests.ok((select count(*) from public.group_members gm join public.groups g on g.id = gm.group_id
                 where g.department_id = 'd0000000-0000-0000-0000-000000000001') = 2,
  'department employees are members of the department group');

-- ------------------------------------------------------------------ anon ------
set role anon;
select tests.fails('select * from public.posts', 'logged-out users cannot read posts');
select tests.fails('select * from public.profiles', 'logged-out users cannot read profiles');
reset role;

-- ---------------------------------------------------------------- profiles ----
select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
select tests.ok((select count(*) from public.profiles) = 5, 'employees see the directory');
select tests.fails('select phone from public.profiles', 'phone column is not readable directly');
select tests.ok((select count(*) from public.profile_contacts) = 4,
  'employee sees phones of "everyone" people + their own, not "managers only"');
select tests.fails($$update public.profiles set role = 'admin' where id = 'a0000000-0000-0000-0000-000000000003'$$,
  'employee cannot make themselves admin');
update public.profiles set is_active = false where id = 'a0000000-0000-0000-0000-000000000004';
select tests.ok((select is_active from public.profiles where id = 'a0000000-0000-0000-0000-000000000004'),
  'employee cannot deactivate someone (no rows changed)');
update public.profiles set bio = 'Hello', locale = 'en' where id = 'a0000000-0000-0000-0000-000000000003';
select tests.ok((select bio from public.profiles where id = 'a0000000-0000-0000-0000-000000000003') = 'Hello',
  'employee can edit their own bio and language');
select tests.ok(not exists (select 1 from public.profiles where id = 'a0000000-0000-0000-0000-000000000004' and bio is not null),
  'nobody else was changed');

select tests.login('00000000-0000-0000-0000-00000000000b'); -- Manager
select tests.ok((select count(*) from public.profile_contacts) = 4,
  'manager also sees "managers only" phones');

select tests.login('00000000-0000-0000-0000-00000000000a'); -- Admin
select tests.fails($$update public.profiles set role = 'employee' where id = 'a0000000-0000-0000-0000-000000000001'$$,
  'admin cannot demote themselves by accident');

-- -------------------------------------------------------------------- feed ----
select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
insert into public.posts (id, author_id, body)
values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', 'Hello company #welcome');
select tests.fails($$insert into public.posts (author_id, body) values ('a0000000-0000-0000-0000-000000000004', 'fake')$$,
  'cannot post as someone else');
select tests.fails($$insert into public.posts (author_id, body, is_pinned, is_announcement)
                     values ('a0000000-0000-0000-0000-000000000003', 'x', true, true)$$,
  'employee cannot pin a company announcement');

select tests.login('00000000-0000-0000-0000-00000000000a'); -- Admin
insert into public.posts (id, author_id, body, is_pinned, is_announcement)
values ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Company announcement', true, true);
select tests.fails($$update public.posts set body = 'edited by admin' where id = 'b0000000-0000-0000-0000-000000000001'$$,
  'admin cannot rewrite someone else''s post text');
update public.posts set comments_locked = true where id = 'b0000000-0000-0000-0000-000000000001';

select tests.login('00000000-0000-0000-0000-00000000000d'); -- Employee2
select tests.ok((select count(*) from public.posts where group_id is null) = 2, 'everyone sees the company feed');
select tests.fails($$insert into public.comments (post_id, author_id, body)
                     values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000004', 'hi')$$,
  'cannot comment when comments are locked');
insert into public.comments (id, post_id, author_id, body)
values ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000004', 'Noted');
insert into public.reactions (profile_id, post_id, emoji)
values ('a0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000002', '🎉');
insert into public.announcement_views (post_id, profile_id)
values ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000004');
select tests.fails($$insert into public.reactions (profile_id, post_id, emoji)
                     values ('a0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000002', '😂')$$,
  'one reaction per person per post');
update public.posts set deleted_at = now() where id = 'b0000000-0000-0000-0000-000000000002';
select tests.ok((select deleted_at from public.posts where id = 'b0000000-0000-0000-0000-000000000002') is null,
  'employee cannot delete someone else''s post');

select tests.login('00000000-0000-0000-0000-00000000000a'); -- Admin (post author)
select tests.ok((select count(*) from public.announcement_views where post_id = 'b0000000-0000-0000-0000-000000000002') = 1,
  'announcement author sees who has seen it');

-- --------------------------------------------------------- private groups -----
select tests.login('00000000-0000-0000-0000-00000000000b'); -- Manager
insert into public.groups (id, name, privacy, created_by)
values ('e0000000-0000-0000-0000-000000000001', 'Secret project', 'private', 'a0000000-0000-0000-0000-000000000002');
insert into public.group_members (group_id, profile_id)
values ('e0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003');
insert into public.posts (author_id, group_id, body, is_pinned)
values ('a0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000001', 'Group-only post', true);

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1 (member)
select tests.ok((select count(*) from public.posts where group_id = 'e0000000-0000-0000-0000-000000000001') = 1,
  'members see private group posts');

select tests.login('00000000-0000-0000-0000-00000000000e'); -- Employee3 (not member)
select tests.ok((select count(*) from public.posts where group_id = 'e0000000-0000-0000-0000-000000000001') = 0,
  'non-members cannot see private group posts');
select tests.ok((select count(*) from public.groups where id = 'e0000000-0000-0000-0000-000000000001') = 0,
  'non-members cannot even see the private group');
select tests.fails($$insert into public.group_members (group_id, profile_id)
                     values ('e0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000005')$$,
  'cannot join a private group without an invite');
select tests.fails($$insert into public.groups (name, created_by) values ('My group', 'a0000000-0000-0000-0000-000000000005')$$,
  'employees cannot create groups (managers/admins only)');

-- -------------------------------------------------------------- private chat --
select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
select public.get_or_create_direct_conversation('a0000000-0000-0000-0000-000000000004') as dm_id \gset
select tests.ok(public.get_or_create_direct_conversation('a0000000-0000-0000-0000-000000000004') = :'dm_id',
  'opening the same 1:1 chat twice reuses it');
insert into public.messages (id, conversation_id, sender_id, body)
values ('f0000000-0000-0000-0000-000000000001', :'dm_id', 'a0000000-0000-0000-0000-000000000003', 'Secret hello');

select tests.login('00000000-0000-0000-0000-00000000000d'); -- Employee2 (other member)
select tests.ok((select body from public.messages where id = 'f0000000-0000-0000-0000-000000000001') = 'Secret hello',
  'the other person can read the DM');
select public.mark_conversation_seen(:'dm_id');
insert into public.message_reactions (message_id, profile_id, emoji)
values ('f0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000004', '❤️'),
       ('f0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000004', '🔥');

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1 (sender)
select tests.ok((select seen_at from public.message_receipts
                 where message_id = 'f0000000-0000-0000-0000-000000000001'
                   and profile_id = 'a0000000-0000-0000-0000-000000000004') is not null,
  'sender sees who saw the message and when');
select tests.fails($$insert into public.message_receipts (message_id, profile_id, seen_at)
                     values ('f0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', now())$$,
  'cannot mark your own message as seen');

select tests.login('00000000-0000-0000-0000-00000000000a'); -- ADMIN
select tests.ok((select count(*) from public.messages) = 0, 'ADMIN CANNOT READ PRIVATE MESSAGES');
select tests.ok((select count(*) from public.conversations) = 0, 'admin cannot see private conversations');
select tests.ok((select count(*) from public.message_receipts) = 0, 'admin cannot see read receipts of others');
select tests.ok((select count(*) from public.message_reactions) = 0, 'admin cannot see chat reactions of others');
select tests.fails(format($$insert into public.messages (conversation_id, sender_id, body)
                            values (%L, 'a0000000-0000-0000-0000-000000000001', 'spy')$$, :'dm_id'),
  'admin cannot post into a chat they are not in');
select tests.fails(format($$insert into public.conversation_members (conversation_id, profile_id)
                            values (%L, 'a0000000-0000-0000-0000-000000000001')$$, :'dm_id'),
  'admin cannot add themselves to a private chat');
select tests.fails($$select public.mark_conversation_seen('00000000-0000-0000-0000-000000000000')$$,
  'chat functions refuse non-members');

-- Delete for everyone wipes the text.
select tests.login('00000000-0000-0000-0000-00000000000c');
update public.messages set deleted_at = now() where id = 'f0000000-0000-0000-0000-000000000001';
select tests.ok((select body from public.messages where id = 'f0000000-0000-0000-0000-000000000001') = '',
  'deleting a message wipes its text');

-- Group chat
select public.create_group_conversation('Team', array['a0000000-0000-0000-0000-000000000004'::uuid,
                                                      'a0000000-0000-0000-0000-000000000005'::uuid]) as gc_id \gset
select tests.ok((select count(*) from public.conversation_members where conversation_id = :'gc_id') = 3,
  'group chat created with all members');

-- ---------------------------------------------------------------- storage -----
reset role;
insert into storage.objects (bucket_id, name, owner_id)
values ('chat-media', :'dm_id' || '/photo.jpg', '00000000-0000-0000-0000-00000000000c'),
       ('post-media', 'b0000000-0000-0000-0000-000000000001/pic.jpg', '00000000-0000-0000-0000-00000000000c');
select tests.login('00000000-0000-0000-0000-00000000000a'); -- Admin
select tests.ok((select count(*) from storage.objects where bucket_id = 'chat-media') = 0,
  'admin cannot open private chat files');
select tests.ok((select count(*) from storage.objects where bucket_id = 'post-media') = 1,
  'post files follow post visibility');
select tests.login('00000000-0000-0000-0000-00000000000d'); -- Employee2
select tests.ok((select count(*) from storage.objects where bucket_id = 'chat-media') = 1,
  'chat members can open chat files');
select tests.login('00000000-0000-0000-0000-00000000000e'); -- Employee3
select tests.fails(format($$insert into storage.objects (bucket_id, name) values ('chat-media', %L)$$, :'dm_id' || '/x.jpg'),
  'non-members cannot upload into a chat');
select tests.fails($$insert into storage.objects (bucket_id, name) values ('post-media', 'b0000000-0000-0000-0000-000000000001/x.jpg')$$,
  'cannot upload files to someone else''s post');

-- --------------------------------------------------------- reports & notifs ---
select tests.login('00000000-0000-0000-0000-00000000000e'); -- Employee3
insert into public.reports (reporter_id, post_id, reason)
values ('a0000000-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-000000000001', 'Spam');
select tests.fails($$insert into public.notifications (recipient_id, type)
                     values ('a0000000-0000-0000-0000-000000000004', 'mention')$$,
  'the app cannot create fake notifications');

select tests.login('00000000-0000-0000-0000-00000000000d'); -- Employee2
select tests.ok((select count(*) from public.reports) = 0, 'employees cannot see other people''s reports');

select tests.login('00000000-0000-0000-0000-00000000000a'); -- Admin
select tests.ok((select count(*) from public.reports) = 1, 'admin sees reports');
update public.reports set status = 'resolved';
select tests.ok((select handled_by from public.reports) = 'a0000000-0000-0000-0000-000000000001',
  'resolving a report records who handled it');

-- ------------------------------------------------------------ deactivation ----
update public.profiles set is_active = false where id = 'a0000000-0000-0000-0000-000000000004';
select tests.ok((select deactivated_at from public.profiles where id = 'a0000000-0000-0000-0000-000000000004') is not null,
  'deactivation time is recorded');

select tests.login('00000000-0000-0000-0000-00000000000d'); -- Employee2, now deactivated
select tests.ok((select count(*) from public.posts) = 0, 'deactivated employee sees no posts');
select tests.ok((select count(*) from public.messages) = 0, 'deactivated employee sees no messages');
select tests.ok((select count(*) from public.profiles) = 0, 'deactivated employee sees no directory');
select tests.fails($$insert into public.posts (author_id, body) values ('a0000000-0000-0000-0000-000000000004', 'still here?')$$,
  'deactivated employee cannot post');
select tests.logout();
select tests.ok(public.hook_custom_access_token(
  '{"user_id":"00000000-0000-0000-0000-00000000000d","claims":{}}') ? 'error',
  'deactivated employee cannot refresh their session');

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
select tests.ok((select count(*) from public.profiles where id = 'a0000000-0000-0000-0000-000000000004') = 0,
  'deactivated employees disappear from the directory');

select tests.logout();
\echo 'ALL SECURITY TESTS PASSED'
