-- Migration: Access Period Control for Broadcasters
-- Target: Supabase PostgreSQL

-- 1. Add access control columns to public.users
alter table public.users add column if not exists access_start timestamp with time zone;
alter table public.users add column if not exists access_end timestamp with time zone;

-- 2. Create helper function to check if broadcaster is active and within their access period
create or replace function public.is_active_broadcaster(user_id uuid)
returns boolean as $$
begin
  return exists (
    select 1 from public.users
    where id = user_id 
      and role = 'broadcaster' 
      and active = true 
      and (access_start is null or access_start <= now())
      and (access_end is null or access_end >= now())
  );
end;
$$ language plpgsql security definer;

-- 3. Update the INSERT RLS policy on public.lives to enforce the check
drop policy if exists "Broadcasters can create lives" on public.lives;
create policy "Broadcasters can create lives"
  on public.lives for insert
  to authenticated
  with check (
    auth.uid() = creator_id 
    and public.is_active_broadcaster(auth.uid())
  );

-- 4. Update handle_new_user trigger function to populate access_start and access_end on sign-up/creation
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, name, email, role, active, access_start, access_end)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', 'Usuário LiveLink'),
    new.email,
    coalesce(new.raw_user_meta_data->>'role', 'broadcaster'),
    coalesce((new.raw_user_meta_data->>'active')::boolean, true),
    (new.raw_user_meta_data->>'access_start')::timestamp with time zone,
    (new.raw_user_meta_data->>'access_end')::timestamp with time zone
  );
  return new;
end;
$$ language plpgsql security definer;
