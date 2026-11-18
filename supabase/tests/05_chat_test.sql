-- =============================================================================
-- Tests for Phase 5 (chat). Runs after 01–04; same fixtures.
--   Admin a..01 (aal2 via tests.login_admin), Manager a..02 / ..0b,
--   Employee1 a..03 / ..0c, Employee2 a..04 / ..0d, Employee3 a..05 / ..5e
-- =============================================================================
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

create temp table t_chat (name text primary key, id uuid);
grant all on t_chat to public;

-- ------------------------------------------------------------- direct chat --
select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
insert into t_chat values ('dm', public.get_or_create_direct_conversation('a0000000-0000-0000-0000-000000000005'));
insert into public.messages (id, conversation_id, sender_id, body) values
  ('e5000000-0000-0000-0000-000000000001', (select id from t_chat where name = 'dm'), 'a0000000-0000-0000-0000-000000000003', 'Hi Sara');
insert into public.messages (id, conversation_id, sender_id, body) values
  ('e5000000-0000-0000-0000-000000000002', (select id from t_chat where name = 'dm'), 'a0000000-0000-0000-0000-000000000003', 'Are you free?');
select tests.ok((select other_person ->> 'full_name' from public.list_conversations() where id = (select id from t_chat where name = 'dm')) = 'Employee3',
  'the chat list shows the other person in a direct chat');
select tests.ok((select unread_count from public.list_conversations() where id = (select id from t_chat where name = 'dm')) = 0,
  'my own messages are not unread for me');
select tests.ok((select last_message ->> 'body' from public.list_conversations() where id = (select id from t_chat where name = 'dm')) = 'Are you free?',
  'the chat list shows the last message');
select tests.fails($$insert into public.message_attachments (message_id, storage_path, kind, size_bytes)
  values ('e5000000-0000-0000-0000-000000000001', 'some-other-chat/x.jpg', 'image', 10)$$,
  'chat attachments must be stored in the chat''s own folder');
insert into public.message_attachments (message_id, storage_path, kind, size_bytes)
values ('e5000000-0000-0000-0000-000000000001', (select id from t_chat where name = 'dm')::text || '/x.jpg', 'image', 10);
select tests.ok(private.can_use_realtime_topic('chat:' || (select id from t_chat where name = 'dm')),
  'members can join the chat''s live (typing) channel');
select tests.ok(private.can_use_realtime_topic('presence:online'), 'employees can join the online channel');
select tests.ok(not private.can_use_realtime_topic('something-else'), 'other live channels are refused');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000005e'); -- Employee3 receives
select tests.ok((select unread_count from public.list_conversations() where id = (select id from t_chat where name = 'dm')) = 2,
  'the receiver sees 2 unread messages');
select public.mark_conversation_delivered((select id from t_chat where name = 'dm'));
select tests.ok((select delivered_count from public.get_messages((select id from t_chat where name = 'dm'))
                 where id = 'e5000000-0000-0000-0000-000000000001') = 1, 'messages are marked delivered (✓)');
select public.mark_conversation_seen((select id from t_chat where name = 'dm'));
select tests.ok((select unread_count from public.list_conversations() where id = (select id from t_chat where name = 'dm')) = 0,
  'opening the chat clears unread');
select tests.ok((select seen_count from public.get_messages((select id from t_chat where name = 'dm'))
                 where id = 'e5000000-0000-0000-0000-000000000002') = 1, 'messages are marked seen (✓✓)');
select tests.ok((select jsonb_array_length(attachments) from public.get_messages((select id from t_chat where name = 'dm'))
                 where id = 'e5000000-0000-0000-0000-000000000001') = 1, 'messages include their attachments');
insert into public.messages (conversation_id, sender_id, body, reply_to_id)
values ((select id from t_chat where name = 'dm'), 'a0000000-0000-0000-0000-000000000005', 'Yes!', 'e5000000-0000-0000-0000-000000000002');
select tests.ok((select reply_to ->> 'body' from public.get_messages((select id from t_chat where name = 'dm')) where body = 'Yes!') = 'Are you free?',
  'replies include the quoted message');
insert into public.message_reactions (message_id, profile_id, emoji) values
  ('e5000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000005', '👍'),
  ('e5000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000005', '❤️');
select tests.ok((select reactions from public.get_messages((select id from t_chat where name = 'dm'))
                 where id = 'e5000000-0000-0000-0000-000000000001') ? '❤️', 'several emoji reactions per message');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1 sees who saw it
select tests.ok((select seen_at is not null from public.get_message_receipts('e5000000-0000-0000-0000-000000000002')
                 where person ->> 'full_name' = 'Employee3'), 'the sender sees who saw the message and when');
update public.messages set deleted_at = now() where id = 'e5000000-0000-0000-0000-000000000002';
select tests.ok((select body from public.get_messages((select id from t_chat where name = 'dm'))
                 where id = 'e5000000-0000-0000-0000-000000000002') = '', 'delete for everyone wipes the text');
select tests.ok((select reply_to ->> 'deleted' from public.get_messages((select id from t_chat where name = 'dm')) where body = 'Yes!') = 'true',
  'a reply shows that the quoted message was deleted');
select tests.logout();

-- ---------------------------------------------------------- privacy ---------
select tests.login_admin();
select tests.ok((select count(*) from public.get_messages((select id from t_chat where name = 'dm'))) = 0,
  'admins cannot read other people''s private chats');
select tests.ok((select count(*) from public.list_conversations() where id = (select id from t_chat where name = 'dm')) = 0,
  'admins do not see other people''s chats in their list');
select tests.ok((select count(*) from public.get_message_receipts('e5000000-0000-0000-0000-000000000001')) = 0,
  'admins cannot see receipts of other people''s chats');
select tests.ok(not private.can_use_realtime_topic('chat:' || (select id from t_chat where name = 'dm')),
  'admins cannot join the typing channel of other people''s chats');
select tests.logout();

-- ------------------------------------------------------------- group chat ---
select tests.login('00000000-0000-0000-0000-00000000000b'); -- Manager
insert into t_chat values ('team', public.create_group_conversation('Team',
  array['a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000005']::uuid[]));
select tests.ok((select member_count from public.list_conversations() where id = (select id from t_chat where name = 'team')) = 3,
  'group chat has the creator + 2 members');
insert into public.messages (id, conversation_id, sender_id, body)
values ('e5000000-0000-0000-0000-000000000010', (select id from t_chat where name = 'team'), 'a0000000-0000-0000-0000-000000000002', 'Standup at 10');
select tests.ok((select recipient_count from public.get_messages((select id from t_chat where name = 'team'))) = 2,
  'a group message has 2 recipients');
select tests.ok((select count(*) from public.get_message_receipts('e5000000-0000-0000-0000-000000000010')) = 2,
  'receipt list shows each recipient (not yet seen)');
update public.conversations set title = 'Sales team' where id = (select id from t_chat where name = 'team');
select public.leave_group_conversation((select id from t_chat where name = 'team'));
select tests.ok((select count(*) from public.list_conversations() where id = (select id from t_chat where name = 'team')) = 0,
  'after leaving, the chat is gone from my list');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1 (joined first)
select tests.ok((select my_role from public.list_conversations() where id = (select id from t_chat where name = 'team')) = 'owner',
  'when the owner leaves, another member becomes owner');
select tests.ok((select title from public.list_conversations() where id = (select id from t_chat where name = 'team')) = 'Sales team',
  'the owner can rename a group chat');
select tests.fails($$select public.leave_group_conversation((select id from t_chat where name = 'dm'))$$,
  'you cannot "leave" a direct chat');
select tests.logout();

set role anon;
select tests.fails('select * from public.list_conversations()', 'logged-out users cannot list chats');
reset role;

\echo 'ALL PHASE 5 CHAT TESTS PASSED'
