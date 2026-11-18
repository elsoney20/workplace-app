-- =============================================================================
-- Engagement (owner request 2026-11-18: "fill the empty space, make it fun"):
--   * Birthdays (each employee sets their own; only day + month are shown)
--     and work anniversaries / new joiners (hire date, set by an admin).
--   * Company events with "I'm going".
--   * Kudos: thank a colleague with a badge; a weekly "heroes" board.
--   * Quick polls inside posts.
--   * get_home_sidebar(): everything the home side columns show, in one call.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Birthdays & hire dates
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists birthday date check (birthday is null or birthday >= date '1930-01-01'),
  add column if not exists hired_on date check (hired_on is null or hired_on >= date '1950-01-01');

-- The birth year stays private: the column is not readable directly, only
-- day + month come out of get_home_sidebar(). The hire date is public.
grant select (hired_on) on public.profiles to authenticated;

-- Same rules as in phase 2, plus: only an admin changes the hire date.
create or replace function private.guard_profile_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_trusted_role() then
    null;
  elsif private.is_admin() then
    -- An admin cannot lock themselves out by accident.
    if new.id = private.current_profile_id()
       and (new.role is distinct from old.role
            or new.is_active is distinct from old.is_active
            or new.phone is distinct from old.phone) then
      raise exception 'Admins cannot change their own role, phone or active status';
    end if;
    if new.auth_user_id is distinct from old.auth_user_id then
      raise exception 'The login link is managed automatically';
    end if;
  else
    if new.phone          is distinct from old.phone
    or new.full_name      is distinct from old.full_name
    or new.department_id  is distinct from old.department_id
    or new.job_title      is distinct from old.job_title
    or new.role           is distinct from old.role
    or new.is_active      is distinct from old.is_active
    or new.deactivated_at is distinct from old.deactivated_at
    or new.auth_user_id   is distinct from old.auth_user_id
    or new.hired_on       is distinct from old.hired_on then
      raise exception 'Only an admin can change these profile fields';
    end if;
  end if;

  -- A new phone number means a new login: the old one stops working.
  if new.phone is distinct from old.phone then
    new.auth_user_id := null;
  end if;

  if new.is_active is distinct from old.is_active then
    new.deactivated_at := case when new.is_active then null else now() end;
  end if;
  return new;
end;
$$;

-- My own birthday (null clears it).
create or replace function public.set_my_birthday(p_birthday date)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
begin
  if v_me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if p_birthday is not null and (p_birthday < date '1930-01-01' or p_birthday > current_date) then
    raise exception 'Invalid birthday' using errcode = '22023';
  end if;
  update public.profiles set birthday = p_birthday where id = v_me;
end;
$$;

create or replace function public.get_my_birthday()
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select birthday from public.profiles where id = private.current_profile_id();
$$;

-- Admin: an employee's hire date.
create or replace function public.admin_set_hired_on(p_profile uuid, p_hired_on date)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only admins can set hire dates' using errcode = '42501';
  end if;
  update public.profiles set hired_on = p_hired_on where id = p_profile;
end;
$$;

-- Next time a yearly date comes round (today counts). 29 Feb -> 28 Feb.
create or replace function private.next_yearly(p_date date)
returns date
language sql
stable
set search_path = ''
as $$
  with y as (
    select (p_date + make_interval(years => (extract(year from current_date) - extract(year from p_date))::int))::date as this_year
  )
  select case when this_year >= current_date then this_year
              else (p_date + make_interval(years => (extract(year from current_date) - extract(year from p_date))::int + 1))::date
         end
  from y;
$$;

-- -----------------------------------------------------------------------------
-- Events
-- -----------------------------------------------------------------------------
create table public.events (
  id           uuid primary key default gen_random_uuid(),
  title        text not null check (length(trim(title)) between 1 and 160),
  description  text check (description is null or length(description) <= 2000),
  location     text check (location is null or length(location) <= 160),
  kind         text not null default 'event'
               check (kind in ('event', 'tournament', 'meeting', 'celebration', 'training')),
  starts_at    timestamptz not null,
  ends_at      timestamptz check (ends_at is null or ends_at >= starts_at),
  created_by   uuid not null default private.current_profile_id()
               references public.profiles (id) on delete cascade,
  created_at   timestamptz not null default now()
);
create index events_starts_at_idx on public.events (starts_at);
create index events_created_by_idx on public.events (created_by);

create table public.event_attendees (
  event_id    uuid not null references public.events (id) on delete cascade,
  profile_id  uuid not null default private.current_profile_id()
              references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (event_id, profile_id)
);
create index event_attendees_profile_idx on public.event_attendees (profile_id);

alter table public.events enable row level security;
alter table public.event_attendees enable row level security;

create policy events_select on public.events
  for select to authenticated using (private.current_profile_id() is not null);
-- Managers / admins (HR, team leads) announce events.
create policy events_insert on public.events
  for insert to authenticated
  with check (private.is_manager_or_admin() and created_by = private.current_profile_id());
create policy events_update on public.events
  for update to authenticated
  using (created_by = private.current_profile_id() or private.is_admin())
  with check (created_by = private.current_profile_id() or private.is_admin());
create policy events_delete on public.events
  for delete to authenticated
  using (created_by = private.current_profile_id() or private.is_admin());

create policy event_attendees_select on public.event_attendees
  for select to authenticated using (private.current_profile_id() is not null);
create policy event_attendees_insert on public.event_attendees
  for insert to authenticated with check (profile_id = private.current_profile_id());
create policy event_attendees_delete on public.event_attendees
  for delete to authenticated using (profile_id = private.current_profile_id());

grant select, insert, update, delete on public.events to authenticated;
grant select, insert, delete on public.event_attendees to authenticated;

-- -----------------------------------------------------------------------------
-- Kudos
-- -----------------------------------------------------------------------------
create table public.kudos (
  id          uuid primary key default gen_random_uuid(),
  from_id     uuid not null default private.current_profile_id()
              references public.profiles (id) on delete cascade,
  to_id       uuid not null references public.profiles (id) on delete cascade,
  badge       text not null
              check (badge in ('thanks', 'teamwork', 'helpful', 'mvp', 'creative', 'speed')),
  message     text check (message is null or length(message) <= 280),
  created_at  timestamptz not null default now(),
  check (from_id <> to_id)
);
create index kudos_to_created_idx on public.kudos (to_id, created_at desc);
create index kudos_from_created_idx on public.kudos (from_id, created_at desc);
create index kudos_created_idx on public.kudos (created_at desc);

alter table public.kudos enable row level security;

create policy kudos_select on public.kudos
  for select to authenticated using (private.current_profile_id() is not null);
create policy kudos_insert on public.kudos
  for insert to authenticated
  with check (
    from_id = private.current_profile_id()
    and exists (select 1 from public.profiles p where p.id = to_id and p.is_active)
  );
create policy kudos_delete on public.kudos
  for delete to authenticated
  using (from_id = private.current_profile_id() or private.is_admin());

grant select, insert, delete on public.kudos to authenticated;

-- No spamming the board: at most 10 kudos a day each.
create or replace function private.guard_kudos_rate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.is_trusted_role() then
    return new;
  end if;
  if (select count(*) from public.kudos k
      where k.from_id = new.from_id and k.created_at > now() - interval '1 day') >= 10 then
    raise exception 'Too many kudos today' using errcode = '54000';
  end if;
  return new;
end;
$$;

create trigger kudos_rate before insert on public.kudos
  for each row execute function private.guard_kudos_rate();

alter type public.notification_type add value if not exists 'kudos';

create or replace function private.notify_kudos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications (recipient_id, type, actor_id, target)
  values (new.to_id, 'kudos', new.from_id, jsonb_build_object('kudos_id', new.id, 'badge', new.badge));
  return null;
end;
$$;

create trigger kudos_notify after insert on public.kudos
  for each row execute function private.notify_kudos();

-- -----------------------------------------------------------------------------
-- Polls (one per post)
-- -----------------------------------------------------------------------------
create table public.post_polls (
  post_id     uuid primary key references public.posts (id) on delete cascade,
  question    text not null check (length(trim(question)) between 1 and 300),
  closes_at   timestamptz,
  created_at  timestamptz not null default now()
);

create table public.poll_options (
  id        uuid primary key default gen_random_uuid(),
  post_id   uuid not null references public.post_polls (post_id) on delete cascade,
  label     text not null check (length(trim(label)) between 1 and 120),
  position  integer not null default 0
);
create index poll_options_post_idx on public.poll_options (post_id, position);

create table public.poll_votes (
  post_id     uuid not null references public.post_polls (post_id) on delete cascade,
  option_id   uuid not null references public.poll_options (id) on delete cascade,
  voter_id    uuid not null default private.current_profile_id()
              references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (post_id, voter_id)
);
create index poll_votes_option_idx on public.poll_votes (option_id);
create index poll_votes_voter_idx on public.poll_votes (voter_id);

alter table public.post_polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;

create policy post_polls_select on public.post_polls
  for select to authenticated using (private.can_view_post(post_id));
create policy poll_options_select on public.poll_options
  for select to authenticated using (private.can_view_post(post_id));
create policy poll_votes_select on public.poll_votes
  for select to authenticated using (private.can_view_post(post_id));

-- Polls and options are written only through create_poll(); votes through
-- vote_poll().
grant select on public.post_polls, public.poll_options, public.poll_votes to authenticated;

create or replace function public.create_poll(p_post_id uuid, p_question text, p_options text[])
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
  v_label text;
  v_pos int := 0;
  v_clean text[];
begin
  if v_me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if not exists (select 1 from public.posts p where p.id = p_post_id and p.author_id = v_me and p.deleted_at is null) then
    raise exception 'Only the author can add a poll to a post' using errcode = '42501';
  end if;
  select array_agg(trim(o)) into v_clean
  from unnest(p_options) o where length(trim(o)) > 0;
  if coalesce(array_length(v_clean, 1), 0) not between 2 and 6 then
    raise exception 'A poll needs 2 to 6 choices' using errcode = '22023';
  end if;
  insert into public.post_polls (post_id, question) values (p_post_id, trim(p_question));
  foreach v_label in array v_clean loop
    insert into public.poll_options (post_id, label, position) values (p_post_id, v_label, v_pos);
    v_pos := v_pos + 1;
  end loop;
end;
$$;

-- Vote, change my vote, or take it back (p_option_id null).
create or replace function public.vote_poll(p_post_id uuid, p_option_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
begin
  if v_me is null or not private.can_view_post(p_post_id) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.post_polls where post_id = p_post_id and closes_at is not null and closes_at <= now()) then
    raise exception 'This poll is closed' using errcode = '22023';
  end if;
  if p_option_id is null then
    delete from public.poll_votes where post_id = p_post_id and voter_id = v_me;
    return;
  end if;
  if not exists (select 1 from public.poll_options where id = p_option_id and post_id = p_post_id) then
    raise exception 'Unknown choice' using errcode = '22023';
  end if;
  insert into public.poll_votes (post_id, option_id, voter_id) values (p_post_id, p_option_id, v_me)
  on conflict (post_id, voter_id) do update set option_id = excluded.option_id, created_at = now();
end;
$$;

-- The polls of a page of posts (posts without a poll are left out).
create or replace function public.get_polls(p_post_ids uuid[])
returns table (post_id uuid, poll jsonb)
language sql
stable
security invoker
set search_path = ''
as $$
  select pp.post_id,
    jsonb_build_object(
      'question', pp.question,
      'closes_at', pp.closes_at,
      'total', (select count(*) from public.poll_votes v where v.post_id = pp.post_id),
      'my_option', (select v.option_id from public.poll_votes v
                    where v.post_id = pp.post_id and v.voter_id = private.current_profile_id()),
      'options', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', o.id, 'label', o.label,
                 'votes', (select count(*) from public.poll_votes v where v.option_id = o.id)
               ) order by o.position)
        from public.poll_options o where o.post_id = pp.post_id
      ), '[]'::jsonb)
    )
  from public.post_polls pp
  where pp.post_id = any(p_post_ids);
$$;

-- -----------------------------------------------------------------------------
-- Home side columns
-- -----------------------------------------------------------------------------
create or replace function public.get_home_sidebar()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
begin
  if v_me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'my_birthday_set', (select birthday is not null from public.profiles where id = v_me),

    -- Birthdays in the next 7 days (day + month only).
    'birthdays', coalesce((
      select jsonb_agg(jsonb_build_object(
               'person', private.person_card(x.id),
               'day', x.next_day,
               'days_until', x.next_day - current_date
             ) order by x.next_day, x.full_name)
      from (
        select p.id, p.full_name, private.next_yearly(p.birthday) as next_day
        from public.profiles p
        where p.is_active and p.birthday is not null
      ) x
      where x.next_day <= current_date + 7
    ), '[]'::jsonb),

    -- Work anniversaries (1 year or more) in the next 7 days.
    'anniversaries', coalesce((
      select jsonb_agg(jsonb_build_object(
               'person', private.person_card(x.id),
               'day', x.next_day,
               'days_until', x.next_day - current_date,
               'years', extract(year from x.next_day)::int - extract(year from x.hired_on)::int
             ) order by x.next_day, x.full_name)
      from (
        select p.id, p.full_name, p.hired_on, private.next_yearly(p.hired_on) as next_day
        from public.profiles p
        where p.is_active and p.hired_on is not null and p.hired_on < current_date
      ) x
      where x.next_day <= current_date + 7
        and extract(year from x.next_day) > extract(year from x.hired_on)
    ), '[]'::jsonb),

    -- Joined in the last 45 days.
    'new_joiners', coalesce((
      select jsonb_agg(jsonb_build_object('person', private.person_card(p.id), 'hired_on', p.hired_on)
             order by p.hired_on desc)
      from (
        select id, hired_on from public.profiles
        where is_active and hired_on between current_date - 45 and current_date
        order by hired_on desc limit 8
      ) p
    ), '[]'::jsonb),

    -- Next events.
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'title', e.title, 'description', e.description,
               'location', e.location, 'kind', e.kind,
               'starts_at', e.starts_at, 'ends_at', e.ends_at,
               'created_by', e.created_by,
               'going_count', (select count(*) from public.event_attendees a where a.event_id = e.id),
               'i_am_going', exists (select 1 from public.event_attendees a where a.event_id = e.id and a.profile_id = v_me),
               'going', coalesce((
                 select jsonb_agg(private.person_card(a.profile_id))
                 from (select profile_id from public.event_attendees a
                       where a.event_id = e.id order by a.created_at limit 5) a
               ), '[]'::jsonb)
             ) order by e.starts_at)
      from (
        select * from public.events
        where coalesce(ends_at, starts_at + interval '3 hours') >= now()
        order by starts_at limit 6
      ) e
    ), '[]'::jsonb),

    -- Heroes of the week: most kudos received in the last 7 days.
    'heroes', coalesce((
      select jsonb_agg(jsonb_build_object('person', private.person_card(h.to_id), 'count', h.n)
             order by h.n desc, h.last desc)
      from (
        select k.to_id, count(*) as n, max(k.created_at) as last
        from public.kudos k
        join public.profiles p on p.id = k.to_id and p.is_active
        where k.created_at > now() - interval '7 days'
        group by k.to_id
        order by n desc, last desc
        limit 5
      ) h
    ), '[]'::jsonb),

    -- Latest kudos.
    'kudos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', k.id, 'from', private.person_card(k.from_id), 'to', private.person_card(k.to_id),
               'badge', k.badge, 'message', k.message, 'created_at', k.created_at
             ) order by k.created_at desc)
      from (select * from public.kudos order by created_at desc limit 8) k
    ), '[]'::jsonb)
  );
end;
$$;

-- Cards for a set of people (e.g. who is online).
create or replace function public.get_people(p_ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(private.person_card(p.id) order by p.full_name), '[]'::jsonb)
  from public.profiles p
  where private.current_profile_id() is not null
    and p.is_active and p.id = any(p_ids);
$$;

-- -----------------------------------------------------------------------------
-- Demo extras (Admin panel -> Demo content, after seed_demo_content()).
-- Everything hangs off the demo colleagues, so remove_demo_content() clears
-- it through the foreign keys.
-- -----------------------------------------------------------------------------
create or replace function public.seed_demo_extras()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
  p1 uuid := 'de300000-0000-0000-0000-000000000001'; -- Sara, Marketing
  p2 uuid := 'de300000-0000-0000-0000-000000000002'; -- Mohamed, Logistics
  p3 uuid := 'de300000-0000-0000-0000-000000000003'; -- Mona, Customer care
  p4 uuid := 'de300000-0000-0000-0000-000000000004'; -- Karim, Sales
  p5 uuid := 'de300000-0000-0000-0000-000000000005'; -- Nour, HR
  p6 uuid := 'de300000-0000-0000-0000-000000000006'; -- Omar, IT
  e1 uuid := 'de800000-0000-0000-0000-000000000001';
  e2 uuid := 'de800000-0000-0000-0000-000000000002';
  e3 uuid := 'de800000-0000-0000-0000-000000000003';
  v_poll uuid := 'de700000-0000-0000-0000-0000000000a1';
  v_thu timestamptz;
begin
  if not private.is_admin() then
    raise exception 'Only admins can load demo content' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles where id = p1) then
    raise exception 'Load the demo content first';
  end if;
  if exists (select 1 from public.events where id = e1) then
    return; -- already there
  end if;

  -- Birthdays (one today, one in 3 days) and hire dates.
  update public.profiles set birthday = (current_date - interval '27 years')::date where id = p3;
  update public.profiles set birthday = (current_date + 3 - interval '31 years')::date where id = p6;
  update public.profiles set birthday = (current_date - 40 - interval '29 years')::date where id = p1;
  update public.profiles set hired_on = (current_date + 2 - interval '3 years')::date where id = p2;
  update public.profiles set hired_on = (current_date - interval '5 years')::date where id = p5;
  update public.profiles set hired_on = current_date - 9 where id = p4;
  update public.profiles set hired_on = current_date - 20 where id = p6;
  update public.profiles set hired_on = (current_date - interval '2 years 3 months')::date where id = p1;
  update public.profiles set hired_on = (current_date - interval '1 year 7 months')::date where id = p3;

  -- Next Thursday, 6 PM Cairo.
  v_thu := (date_trunc('week', now() at time zone 'Africa/Cairo') + interval '3 days 18 hours') at time zone 'Africa/Cairo';
  if v_thu < now() then v_thu := v_thu + interval '7 days'; end if;

  insert into public.events (id, title, description, location, kind, starts_at, ends_at, created_by) values
    (e1, 'بطولة G2E لـ EA FC 25 🎮',
     'خروج المغلوب، ماتش واحد لكل دور. الجايزة: دراع DualSense Edge للبطل 🏆',
     'الدور التالت – غرفة الألعاب', 'tournament', v_thu, v_thu + interval '3 hours', p4),
    (e2, 'يوم العيلة في الشركة 👨‍👩‍👧',
     'ألعاب للأطفال، تجربة أحدث الأجهزة، وأكل للكل. هاتوا عيلتكم!',
     'المقر الرئيسي', 'celebration', v_thu + interval '9 days' - interval '8 hours', v_thu + interval '9 days' - interval '2 hours', p5),
    (e3, 'ورشة: إزاي تصوّر المنتج للسوشيال 📸',
     'ساعة عملية مع فريق التسويق: إضاءة، زوايا، ومونتاج سريع على الموبايل.',
     'أونلاين (Teams)', 'training', now() + interval '1 day 3 hours', now() + interval '1 day 4 hours', p1);
  insert into public.event_attendees (event_id, profile_id) values
    (e1, p4), (e1, p6), (e1, p2), (e1, p3),
    (e2, p5), (e2, p1), (e2, p2),
    (e3, p1), (e3, p3);

  -- Kudos (a few for me too).
  insert into public.kudos (from_id, to_id, badge, message, created_at) values
    (p2, p4, 'teamwork', 'شكراً إنك فضلت معانا لحد ما الشحنة اتوزعت 💪', now() - interval '3 days'),
    (p3, p6, 'helpful', 'حلّيت مشكلة السيستم في ٥ دقايق قبل ما العملاء يحسّوا 🙏', now() - interval '2 days'),
    (p1, p3, 'mvp', 'أعلى تقييم رضا عملاء الشهر ده! 🌟', now() - interval '1 day 4 hours'),
    (p4, p6, 'speed', 'الكاشير رجع يشتغل في الفرع في وقت قياسي ⚡', now() - interval '20 hours'),
    (p5, p1, 'creative', 'حملة Black Friday كانت تحفة 🎨', now() - interval '9 hours'),
    (p6, p2, 'thanks', 'شكراً على ترتيب المخزن، بقى أسهل بكتير', now() - interval '5 hours'),
    (p1, v_me, 'thanks', 'شكراً إنك اعتمدت الميزانية بسرعة 🙌', now() - interval '3 hours'),
    (p4, p6, 'teamwork', 'أحسن فريق دعم فني 🔧', now() - interval '1 hour');

  -- A poll post.
  insert into public.posts (id, author_id, body, created_at)
  values (v_poll, p1, 'يوم الخميس الغدا علينا 🍕 صوّتوا بسرعة قبل الساعة ١٢!', now() - interval '50 minutes');
  insert into public.post_polls (post_id, question) values (v_poll, 'نطلب غدا إيه يوم الخميس؟');
  insert into public.poll_options (id, post_id, label, position) values
    ('de900000-0000-0000-0000-000000000001', v_poll, 'بيتزا 🍕', 0),
    ('de900000-0000-0000-0000-000000000002', v_poll, 'كشري 🍝', 1),
    ('de900000-0000-0000-0000-000000000003', v_poll, 'مشويات 🍢', 2),
    ('de900000-0000-0000-0000-000000000004', v_poll, 'سوشي 🍣', 3);
  insert into public.poll_votes (post_id, option_id, voter_id) values
    (v_poll, 'de900000-0000-0000-0000-000000000001', p2),
    (v_poll, 'de900000-0000-0000-0000-000000000002', p3),
    (v_poll, 'de900000-0000-0000-0000-000000000001', p4),
    (v_poll, 'de900000-0000-0000-0000-000000000003', p5),
    (v_poll, 'de900000-0000-0000-0000-000000000001', p6);
end;
$$;

revoke execute on function
  public.set_my_birthday(date),
  public.get_my_birthday(),
  public.admin_set_hired_on(uuid, date),
  public.create_poll(uuid, text, text[]),
  public.vote_poll(uuid, uuid),
  public.get_polls(uuid[]),
  public.get_home_sidebar(),
  public.get_people(uuid[]),
  public.seed_demo_extras()
from public, anon;
grant execute on function
  public.set_my_birthday(date),
  public.get_my_birthday(),
  public.admin_set_hired_on(uuid, date),
  public.create_poll(uuid, text, text[]),
  public.vote_poll(uuid, uuid),
  public.get_polls(uuid[]),
  public.get_home_sidebar(),
  public.get_people(uuid[]),
  public.seed_demo_extras()
to authenticated;
revoke all on function private.next_yearly(date) from public;
grant execute on function private.next_yearly(date) to authenticated, service_role;
