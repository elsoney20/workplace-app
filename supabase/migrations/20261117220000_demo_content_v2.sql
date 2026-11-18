-- =============================================================================
-- Demo content v2 (owner feedback, 2026-11-17): the demo should look real.
--   * Photo / video posts (real stock photos bundled in the app) are created
--     by the app as the admin, then handed to a demo colleague with
--     public.adopt_demo_post(), which also adds that post's comments and
--     reactions. Storage only lets a post's author upload its files, so the
--     post must start out as the admin's.
--   * seed_demo_content() no longer touches the caller's own posts.
--   * remove_demo_content() also removes adopted posts and the photo posts
--     made by the first demo version.
-- =============================================================================

create table if not exists private.demo_posts (
  post_id uuid primary key references public.posts (id) on delete cascade
);

create or replace function public.seed_demo_content()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me      uuid := private.current_profile_id();
  v_me_name text;
  p1 uuid := 'de300000-0000-0000-0000-000000000001'; -- Sara, Marketing
  p2 uuid := 'de300000-0000-0000-0000-000000000002'; -- Mohamed, Logistics
  p3 uuid := 'de300000-0000-0000-0000-000000000003'; -- Mona, Customer care
  p4 uuid := 'de300000-0000-0000-0000-000000000004'; -- Karim, Sales
  p5 uuid := 'de300000-0000-0000-0000-000000000005'; -- Nour, HR
  p6 uuid := 'de300000-0000-0000-0000-000000000006'; -- Omar, IT
  d1 uuid := 'de400000-0000-0000-0000-000000000001';
  d2 uuid := 'de400000-0000-0000-0000-000000000002';
  d3 uuid := 'de400000-0000-0000-0000-000000000003';
  d4 uuid := 'de400000-0000-0000-0000-000000000004';
  g1 uuid := 'de600000-0000-0000-0000-000000000001';
  c1 uuid := 'de500000-0000-0000-0000-000000000001';
  c2 uuid := 'de500000-0000-0000-0000-000000000002';
  c3 uuid := 'de500000-0000-0000-0000-000000000003';
  v_post uuid;
  v_comment uuid;
  v_msg uuid;
  r record;
  v_emojis text[] := array['👍', '❤️', '🔥', '👏', '😂', '😍'];
  i int := 0;
begin
  if not private.is_admin() then
    raise exception 'Only admins can load demo content' using errcode = '42501';
  end if;
  if exists (select 1 from public.profiles where id = p1) then
    raise exception 'Demo content is already loaded';
  end if;
  select full_name into v_me_name from public.profiles where id = v_me;

  -- Departments (their department groups are created automatically).
  insert into public.departments (id, name_ar, name_en) values
    (d1, 'التسويق', 'Marketing'),
    (d2, 'اللوجستيك والمخازن', 'Logistics'),
    (d3, 'خدمة العملاء', 'Customer care'),
    (d4, 'الموارد البشرية', 'HR');

  -- Colleagues (no login; phones are reserved demo numbers).
  insert into public.profiles (id, phone, full_name, department_id, job_title, role, bio) values
    (p1, '+201000009901', 'سارة علي',     d1, 'مديرة التسويق',       'manager',  'بحب الحملات اللي فيها أفكار جديدة 🎮'),
    (p2, '+201000009902', 'محمد حسن',     d2, 'مسؤول المخزن',        'manager',  null),
    (p3, '+201000009903', 'منى إبراهيم',  d3, 'خدمة العملاء',        'employee', null),
    (p4, '+201000009904', 'كريم يوسف',    null, 'مبيعات الفروع',     'employee', null),
    (p5, '+201000009905', 'نور الهدى',    d4, 'الموارد البشرية',     'manager',  null),
    (p6, '+201000009906', 'عمر خالد',     null, 'الدعم الفني',       'employee', null);
  update public.departments set manager_id = p1 where id = d1;
  update public.departments set manager_id = p2 where id = d2;
  update public.departments set manager_id = p5 where id = d4;

  -- A public group with a few members.
  insert into public.groups (id, name, description, privacy, created_by)
  values (g1, 'نادي الكورة ⚽', 'ماتشات الخميس بعد الشغل وتوقعات الدوري', 'public', p4);
  insert into public.group_members (group_id, profile_id, role) values
    (g1, p6, 'moderator'), (g1, p2, 'member'), (g1, v_me, 'member')
  on conflict do nothing;

  -- Company feed posts (oldest first). Photo / video posts are added by
  -- the app and handed to colleagues with adopt_demo_post().
  insert into public.posts (id, author_id, body, created_at) values
    ('de700000-0000-0000-0000-000000000001', p5,
     'أهلاً بزمايلنا الجداد في خدمة العملاء 👋 يارب تكون بداية حلوة ليكم معانا. ' ||
     'متنسوش تعدّوا على @[منى إبراهيم](' || p3 || ') عشان تستلموا اللابتوبات #ترحيب',
     now() - interval '2 days 3 hours'),
    ('de700000-0000-0000-0000-000000000003', p1,
     'إيه رأيكم في فكرة بطولة FC بين الفروع الشهر الجاي؟ 🏆 ' ||
     'اكتبوا في الكومنتات اسم فريقكم، و@[' || v_me_name || '](' || v_me || ') لو موافق نبدأ التنظيم #بطولة #كورة',
     now() - interval '9 hours'),
    ('de700000-0000-0000-0000-000000000004', p6,
     'تنبيه بسيط: هنعمل تحديث لنظام الكاشير في فرع مدينة نصر النهارده من 11 لـ 11:30 بالليل. ' ||
     'لو حصلت أي مشكلة كلموني على الشات #دعم_فني',
     now() - interval '2 hours'),
    ('de700000-0000-0000-0000-000000000005', p3,
     'عميل النهارده كتب لنا ريفيو 5 نجوم وقال إن التوصيل وصل في نفس اليوم ⭐⭐⭐⭐⭐ ' ||
     'برافو فريق اللوجستيك و@[محمد حسن](' || p2 || ') #عملاء',
     now() - interval '40 minutes');

  -- Group post.
  insert into public.posts (id, author_id, group_id, body, created_at) values
    ('de700000-0000-0000-0000-000000000006', p4, g1,
     'ماتش الخميس الساعة 8 في الملعب اللي جنب المخزن. مين جاي؟ 🙋‍♂️ #كورة',
     now() - interval '3 hours');

  -- Comments.
  insert into public.comments (post_id, author_id, body, created_at) values
    ('de700000-0000-0000-0000-000000000001', p1, 'أهلاً بيكم 🌸 أي حاجة تحتاجوها احنا موجودين', now() - interval '2 days 2 hours'),
    ('de700000-0000-0000-0000-000000000003', p6, 'فريق IT جاهز 💪 هنسمّي نفسنا "Lag Busters"', now() - interval '8 hours'),
    ('de700000-0000-0000-0000-000000000003', p3, 'خدمة العملاء معاكم! 😂', now() - interval '7 hours'),
    ('de700000-0000-0000-0000-000000000006', p2, 'أنا جاي ومعايا اتنين من المخزن', now() - interval '2 hours');
  -- Reactions from colleagues on every demo post.
  for r in select id from public.posts where id::text like 'de700000-%' loop
    insert into public.reactions (profile_id, post_id, emoji)
    select pp, r.id, v_emojis[1 + (abs(hashtext(pp::text || r.id::text)) % 6)]
    from unnest(array[p1, p2, p3, p4, p5, p6]) pp
    where pp <> (select author_id from public.posts where id = r.id)
    on conflict do nothing;
  end loop;

  -- Chats with the caller.
  insert into public.conversations (id, kind, direct_key, created_by) values
    (c1, 'direct', least(v_me::text, p3::text) || ':' || greatest(v_me::text, p3::text), p3),
    (c2, 'direct', least(v_me::text, p4::text) || ':' || greatest(v_me::text, p4::text), p4),
    (c3, 'group', null, p1);
  update public.conversations set title = 'فريق إطلاق العروض 🚀' where id = c3;
  insert into public.conversation_members (conversation_id, profile_id, role) values
    (c1, v_me, 'member'), (c1, p3, 'member'),
    (c2, v_me, 'member'), (c2, p4, 'member'),
    (c3, p1, 'owner'), (c3, p2, 'member'), (c3, v_me, 'member');

  -- Mona: a finished conversation, my last message seen.
  insert into public.messages (conversation_id, sender_id, body, created_at) values
    (c1, p3, 'صباح الخير 🌞 أرقام شكاوى الأسبوع جاهزة، أبعتهالك؟', now() - interval '3 hours'),
    (c1, v_me, 'صباح النور، أيوه ابعتيها وياريت مقارنة بالأسبوع اللي فات', now() - interval '2 hours 55 minutes'),
    (c1, p3, 'تمام، الشكاوى قلّت 18% 🎉 هبعتلك الشيت كامل بعد الاجتماع', now() - interval '2 hours 50 minutes');
  insert into public.messages (id, conversation_id, sender_id, body, created_at)
  values (gen_random_uuid(), c1, v_me, 'برافو عليكم 👏', now() - interval '2 hours 45 minutes')
  returning id into v_msg;
  insert into public.message_receipts (message_id, profile_id, delivered_at, seen_at)
  select m.id, p3, m.created_at + interval '5 seconds', m.created_at + interval '1 minute'
  from public.messages m where m.conversation_id = c1 and m.sender_id = v_me;
  update public.conversation_members set last_read_at = now() - interval '2 hours 44 minutes'
  where conversation_id = c1 and profile_id = v_me;

  -- Karim: unread messages for me.
  insert into public.messages (conversation_id, sender_id, body, created_at) values
    (c2, p4, 'أستاذ، فرع المعادي خلّص كل أجهزة PS5 النهارده 🔥', now() - interval '25 minutes'),
    (c2, p4, 'ينفع نطلب شحنة إضافية قبل الخميس؟', now() - interval '24 minutes');

  -- Group chat.
  insert into public.messages (conversation_id, sender_id, body, created_at) values
    (c3, p1, 'يا جماعة التصميمات النهائية للعروض جاهزة، هرفعها هنا بالليل', now() - interval '1 hour 30 minutes'),
    (c3, p2, 'المخزن جاهز لأي كميات، بس محتاج الأرقام قبل الأربع', now() - interval '1 hour 10 minutes'),
    (c3, v_me, 'تمام، نقفل الأرقام بكرة الساعة 12', now() - interval '1 hour'),
    (c3, p1, '👍 اتفقنا', now() - interval '55 minutes');
  insert into public.message_receipts (message_id, profile_id, delivered_at, seen_at)
  select m.id, pp, m.created_at + interval '3 seconds', m.created_at + interval '2 minutes'
  from public.messages m, unnest(array[p1, p2]) pp
  where m.conversation_id = c3 and m.sender_id = v_me;
end;
$$;

create or replace function public.adopt_demo_post(
  p_post uuid,
  p_author uuid,
  p_minutes_ago integer,
  p_comments jsonb default '[]'::jsonb
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
  c jsonb;
  v_emojis text[] := array['👍', '❤️', '🔥', '👏', '😂', '😍'];
begin
  if not private.is_admin() then
    raise exception 'Only admins can load demo content' using errcode = '42501';
  end if;
  if p_author::text not like 'de300000-%' then
    raise exception 'Not a demo colleague';
  end if;
  if not exists (
    select 1 from public.posts
    where id = p_post and author_id = v_me and created_at > now() - interval '1 hour'
  ) then
    raise exception 'Only a post you just made can become a demo post';
  end if;

  update public.posts
  set author_id = p_author,
      created_at = now() - make_interval(mins => greatest(p_minutes_ago, 0))
  where id = p_post;
  insert into private.demo_posts (post_id) values (p_post) on conflict do nothing;

  -- Everyone else reacts.
  insert into public.reactions (profile_id, post_id, emoji)
  select pr.id, p_post, v_emojis[1 + (abs(hashtext(pr.id::text || p_post::text)) % 6)]
  from public.profiles pr
  where pr.id::text like 'de300000-%' and pr.id <> p_author
  on conflict do nothing;

  -- Comments: [{"by": uuid, "body": text, "minutes_ago": int}, ...]
  for c in select * from jsonb_array_elements(coalesce(p_comments, '[]'::jsonb)) loop
    insert into public.comments (post_id, author_id, body, created_at)
    values (
      p_post,
      (c ->> 'by')::uuid,
      c ->> 'body',
      now() - make_interval(mins => greatest(coalesce((c ->> 'minutes_ago')::int, 0), 0))
    );
  end loop;
end;
$$;

create or replace function public.remove_demo_content()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
begin
  if not private.is_admin() then
    raise exception 'Only admins can remove demo content' using errcode = '42501';
  end if;
  delete from public.posts where id in (select post_id from private.demo_posts);
  -- Photo posts made by the first demo version (as the admin).
  delete from public.posts p
  where p.author_id = v_me
    and exists (
      select 1 from public.post_attachments a
      where a.post_id = p.id
        and a.file_name in ('black_friday.jpg', 'g2e_cup.jpg', 'new_arrivals.mp4', 'new_arrivals.jpg')
    );
  delete from public.conversations where id::text like 'de500000-%';
  delete from public.groups where id::text like 'de600000-%';
  delete from public.posts where id::text like 'de700000-%';
  delete from public.posts where author_id::text like 'de300000-%';
  update public.departments set manager_id = null where id::text like 'de400000-%';
  delete from public.profiles where id::text like 'de300000-%';
  delete from public.departments where id::text like 'de400000-%';
end;
$$;

revoke execute on function public.adopt_demo_post(uuid, uuid, integer, jsonb) from public, anon;
grant execute on function public.adopt_demo_post(uuid, uuid, integer, jsonb) to authenticated;
