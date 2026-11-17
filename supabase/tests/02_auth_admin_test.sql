-- =============================================================================
-- Security tests for Phase 2 (login + admin panel). Runs right after
-- 01_rls_test.sql on the same throwaway database and reuses its fixtures:
--   Admin     profile a..01 / login ..0a
--   Employee1 profile a..03 / login ..0c
--   Employee2 profile a..04 / login ..0d (deactivated at the end of 01)
--   Employee3 profile a..05 / login ..0e
-- =============================================================================
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

-- ------------------------------------------------------------ own profile ----
select tests.login('00000000-0000-0000-0000-00000000000c'); -- Employee1
select tests.ok((select phone from public.get_my_profile()) = '+201000000003',
  'employee can read their own profile including phone');
select tests.fails('select * from public.admin_list_employees()',
  'employee cannot open the admin employee list');
select tests.fails($$insert into public.profiles (phone, full_name) values ('+201000000099', 'Sneaky')$$,
  'employee cannot add employees');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000d'); -- Employee2 (deactivated)
select tests.ok((select count(*) from public.get_my_profile()) = 0,
  'deactivated employee gets no profile (app signs them out)');
select tests.logout();

set role anon;
select tests.fails('select * from public.get_my_profile()', 'logged-out users cannot call get_my_profile');
select tests.fails('select * from public.admin_list_employees()', 'logged-out users cannot call admin_list_employees');
reset role;

-- ------------------------------------------------------------ admin panel ----
select tests.login('00000000-0000-0000-0000-00000000000a'); -- Admin
select tests.ok((select count(*) from public.admin_list_employees()) = 5,
  'admin sees all employees, including deactivated ones');
select tests.ok((select phone from public.admin_list_employees() where id = 'a0000000-0000-0000-0000-000000000004') = '+201000000004',
  'admin sees phone numbers in the employee list');
select tests.ok((select has_logged_in from public.admin_list_employees() where id = 'a0000000-0000-0000-0000-000000000003'),
  'admin sees who has already logged in');

insert into public.profiles (id, phone, full_name, job_title, role)
values ('a0000000-0000-0000-0000-000000000006', '+201000000006', 'New Hire', 'Accountant', 'employee');
select tests.ok((select count(*) from public.admin_list_employees()) = 6, 'admin can add an employee');
select tests.ok((select has_logged_in from public.admin_list_employees() where id = 'a0000000-0000-0000-0000-000000000006') = false,
  'a new employee has not logged in yet');
select tests.fails($$insert into public.profiles (phone, full_name) values ('+201000000006', 'Duplicate')$$,
  'the same phone number cannot be registered twice');
select tests.fails($$insert into public.profiles (phone, full_name) values ('01000000007', 'Bad format')$$,
  'phone numbers must be in international format');

select tests.fails($$update public.profiles set phone = '+201000000077' where id = 'a0000000-0000-0000-0000-000000000001'$$,
  'admin cannot change their own phone (would lock them out)');
select tests.fails($$update public.profiles set is_active = false where id = 'a0000000-0000-0000-0000-000000000001'$$,
  'admin cannot deactivate themselves');

-- Reactivate Employee2.
update public.profiles set is_active = true where id = 'a0000000-0000-0000-0000-000000000004';
select tests.ok((select deactivated_at from public.admin_list_employees() where id = 'a0000000-0000-0000-0000-000000000004') is null,
  'reactivation clears the deactivation time');

-- Change Employee3's phone number.
update public.profiles set phone = '+201000000055' where id = 'a0000000-0000-0000-0000-000000000005';
select tests.ok((select has_logged_in from public.admin_list_employees() where id = 'a0000000-0000-0000-0000-000000000005') = false,
  'changing a phone number unlinks the old login');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000d'); -- Employee2, active again
select tests.ok((select count(*) from public.get_my_profile()) = 1, 'reactivated employee gets access back');
select tests.logout();

select tests.login('00000000-0000-0000-0000-00000000000e'); -- Employee3's OLD login
select tests.ok((select count(*) from public.profiles) = 0, 'the old phone login no longer has access');
select tests.logout();

select tests.ok(public.hook_before_user_created('{"user":{"phone":"201000000055"}}') = '{}'::jsonb,
  'the new phone number can sign in');
select tests.ok(public.hook_before_user_created('{"user":{"phone":"201000000005"}}') ? 'error',
  'the old phone number can no longer create an account');
insert into auth.users (id, phone) values ('00000000-0000-0000-0000-00000000005e', '201000000055');
select tests.login('00000000-0000-0000-0000-00000000005e');
select tests.ok((select id from public.get_my_profile()) = 'a0000000-0000-0000-0000-000000000005',
  'the new phone login is linked to the same employee');
select tests.logout();

-- ------------------------------------------------ authenticator app (TOTP) ----
insert into auth.mfa_factors (user_id, status) values ('00000000-0000-0000-0000-00000000000a', 'unverified');
select tests.login('00000000-0000-0000-0000-00000000000a');
select tests.ok((select count(*) from public.admin_list_employees()) = 6,
  'an unfinished authenticator setup does not block the admin');
select tests.logout();

update auth.mfa_factors set status = 'verified' where user_id = '00000000-0000-0000-0000-00000000000a';
select tests.login('00000000-0000-0000-0000-00000000000a'); -- SMS code only (aal1)
select tests.ok((select count(*) from public.profiles) = 0,
  'with an authenticator app on, the SMS code alone gives no access');
select tests.fails('select * from public.admin_list_employees()',
  'with an authenticator app on, admin powers need the app code too');
select tests.logout();

select set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-00000000000a', 'role', 'authenticated', 'aal', 'aal2')::text, false);
set role authenticated;
select tests.ok((select count(*) from public.admin_list_employees()) = 6,
  'after entering the authenticator code the admin has full access');
select tests.logout();

-- --------------------------------------------------------- dev SMS sender ----
select tests.ok(public.hook_send_sms_dev('{"user":{"phone":"201000000003"},"sms":{"otp":"123456"}}') = '{}'::jsonb,
  'development SMS sender accepts the request and sends nothing');
select tests.ok(not has_function_privilege('authenticated', 'public.hook_send_sms_dev(jsonb)', 'execute'),
  'app users cannot call the SMS hook');

\echo 'ALL PHASE 2 SECURITY TESTS PASSED'
