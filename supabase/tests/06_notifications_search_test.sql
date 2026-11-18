-- =============================================================================
-- Tests for Phase 6 (notifications, search, directory, moderation).
-- Runs after 01–05; same fixtures. Employee3 (a..05) is in the Sales
-- department since 04; Employee1 (a..03) phone_visibility = 'nobody'.
-- =============================================================================
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

-- ------------------------------------------------------------ notifications -
select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1 posts
insert into public.posts (id, author_id, body)
values ('b6000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', 'Quarterly numbers are ready #finance');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000005e'); -- Employee3 reacts twice
insert into public.reactions (profile_id, post_id, emoji)
values ('a0000000-0000-0000-0000-000000000005', 'b6000000-0000-0000-0000-000000000001', '👍');
update public.reactions set emoji = '🎉'
where profile_id = 'a0000000-0000-0000-0000-000000000005' and post_id = 'b6000000-0000-0000-0000-000000000001';
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
select tests.ok((select count(*) from public.list_notifications() where type = 'reaction'
                 and target ->> 'post_id' = 'b6000000-0000-0000-0000-000000000001') = 1,
  'the author is notified once about a reaction');
select tests.ok((select actor ->> 'full_name' from public.list_notifications() where type = 'reaction' limit 1) = 'Employee3',
  'notifications show who did it');
select tests.ok((select preview from public.list_notifications() where type = 'reaction' limit 1) like 'Quarterly%',
  'notifications show a preview of the post');
select tests.ok(public.unread_notification_count() > 0, 'unread count works');
select public.mark_notifications_read();
select tests.ok(public.unread_notification_count() = 0, 'mark all as read');
select tests.fails($$update public.notifications set type = 'mention'$$, 'notifications cannot be edited except read_at');
select tests.logout();

-- Announcement notifies everyone (except the author).
select tests.login_admin();
insert into public.posts (id, author_id, body, is_announcement, is_pinned)
values ('b6000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Holiday on Sunday', true, true);
select tests.logout();
select tests.ok((select count(*) from public.notifications where type = 'announcement'
                 and target ->> 'post_id' = 'b6000000-0000-0000-0000-000000000002')
                = (select count(*) from public.profiles where is_active) - 1,
  'a company announcement notifies every active employee');

-- Muted group: no notifications.
select tests.login('00000000-0000-0000-0000-00000000000b'); -- Manager (moderates Sales dept group)
insert into public.posts (id, author_id, group_id, body, is_announcement)
values ('b6000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000002',
        (select id from public.groups where department_id = 'd0000000-0000-0000-0000-000000000001'), 'Sales meeting', true);
select tests.logout();
select tests.ok((select count(*) from public.notifications where target ->> 'post_id' = 'b6000000-0000-0000-0000-000000000003'
                 and recipient_id = 'a0000000-0000-0000-0000-000000000003') = 1,
  'group announcement notifies group members');
select tests.ok((select count(*) from public.notifications where target ->> 'post_id' = 'b6000000-0000-0000-0000-000000000003'
                 and recipient_id = 'a0000000-0000-0000-0000-000000000004') = 0,
  'group announcement does not notify people outside the group');
update public.group_members set muted = true
where profile_id = 'a0000000-0000-0000-0000-000000000003'
  and group_id = (select id from public.groups where department_id = 'd0000000-0000-0000-0000-000000000001');
select tests.login('00000000-0000-0000-0000-00000000000b');
insert into public.comments (post_id, author_id, body)
values ('b6000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000002',
        'Agenda for @[Employee1](a0000000-0000-0000-0000-000000000003)');
select tests.logout();
select tests.ok((select count(*) from public.notifications where type = 'mention'
                 and recipient_id = 'a0000000-0000-0000-0000-000000000003'
                 and target ->> 'post_id' = 'b6000000-0000-0000-0000-000000000003') = 0,
  'a muted group sends no notifications');

-- ------------------------------------------------------------------ search --
select tests.login('00000000-0000-0000-0000-00000000000d'); -- Employee2 (not in Sales)
select tests.ok((select count(*) from public.search_posts('quarterly')) = 1, 'search finds company posts');
select tests.ok((select count(*) from public.search_posts('Sales meeting')) = 0,
  'search never shows posts from groups you cannot see');
select tests.ok((select count(*) from public.search_posts('a')) = 0, 'search needs at least 2 letters');
select tests.ok((select count(*) from public.search_messages('free')) = 0,
  'message search only covers your own chats');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1 is in the DM from Phase 5
select tests.ok((select count(*) from public.search_messages('Hi Sara')) = 1, 'message search finds my own messages');
select tests.logout();

select tests.login_admin();
select tests.ok((select count(*) from public.search_messages('Hi Sara')) = 0,
  'admins cannot search other people''s messages');
select tests.logout();

-- --------------------------------------------------------------- directory --
select tests.login('00000000-0000-0000-0000-00000000005e'); -- Employee3 (regular employee)
select tests.ok((select count(*) from public.list_directory()) = (select count(*) from public.profiles where is_active),
  'the directory lists every active employee');
select tests.ok((select phone from public.list_directory() where person ->> 'full_name' = 'Employee1') is null,
  'hidden phone numbers stay hidden in the directory');
select tests.ok((select phone from public.list_directory() where person ->> 'full_name' = 'Manager') = '+201000000002',
  'visible phone numbers are shown');
select tests.ok((select count(*) from public.list_directory(p_department_id => 'd0000000-0000-0000-0000-000000000001')) >= 3,
  'the directory filters by department');
select tests.ok((select count(*) from public.list_directory('sales')) >= 3, 'directory search matches department names');
update public.profiles set bio = 'Football fan', phone_visibility = 'nobody' where id = 'a0000000-0000-0000-0000-000000000005';
select tests.ok((select bio from public.get_my_settings()) = 'Football fan', 'employees can edit their own bio and phone visibility');
select tests.fails($$update public.profiles set job_title = 'CEO' where id = 'a0000000-0000-0000-0000-000000000005'$$,
  'employees cannot change their own job title');
select tests.logout();

-- ------------------------------------------------------------- moderation ---
select tests.login('00000000-0000-0000-0000-00000000000d'); -- Employee2 reports a post
select public.report_content(p_post_id => 'b6000000-0000-0000-0000-000000000001', p_reason => 'Wrong numbers');
select public.report_content(p_post_id => 'b6000000-0000-0000-0000-000000000001', p_reason => 'Again');
select tests.ok((select count(*) from public.list_reports()) = 1, 'reporting twice keeps one open report');
select tests.fails($$select public.handle_report((select id from public.list_reports() limit 1), 'dismissed')$$,
  'employees cannot handle reports');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000b'); -- Manager: not a company feed moderator
select tests.ok((select count(*) from public.list_reports() where post_id = 'b6000000-0000-0000-0000-000000000001') = 0,
  'group moderators do not see company feed reports');
select tests.logout();

select tests.login_admin();
select tests.ok((select content from public.list_reports() where post_id = 'b6000000-0000-0000-0000-000000000001') like 'Quarterly%',
  'admins see the reported content');
select public.handle_report((select id from public.list_reports() where post_id = 'b6000000-0000-0000-0000-000000000001'), 'resolved', true);
select tests.ok((select count(*) from public.get_feed() where id = 'b6000000-0000-0000-0000-000000000001') = 0,
  'resolving with delete removes the post from the feed');
select tests.ok((select content_deleted from public.list_reports('resolved') where post_id = 'b6000000-0000-0000-0000-000000000001'),
  'the report shows the content was deleted');
select tests.logout();

select tests.ok((select count(*) from public.notifications where type = 'report_update'
                 and recipient_id = 'a0000000-0000-0000-0000-000000000004') = 1,
  'the reporter is told their report was handled');

set role anon;
select tests.fails('select * from public.list_directory()', 'logged-out users cannot read the directory');
select tests.fails('select * from public.list_notifications()', 'logged-out users cannot read notifications');
reset role;

\echo 'ALL PHASE 6 TESTS PASSED'
