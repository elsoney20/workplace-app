-- =============================================================================
-- Phase 2 / Migration 2: the first admin (the company owner).
-- Without at least one admin nobody could log in or register anyone else.
-- The name can be changed later from the admin panel.
-- =============================================================================
insert into public.profiles (phone, full_name, role)
values ('+201065111122', 'Owner', 'admin')
on conflict (phone) do update set role = 'admin', is_active = true;
