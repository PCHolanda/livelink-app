-- LiveLink Database Initialization Migration
-- Target: Supabase PostgreSQL (Postgres 15+)

-- Enable UUID Extension
create extension if not exists "uuid-ossp";

-- ==========================================
-- 1. TABLES DEFINITIONS
-- ==========================================

-- A. users (extends Supabase auth.users)
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null unique,
  role text not null check (role in ('admin', 'broadcaster')),
  active boolean not null default true,
  created_at timestamp with time zone not null default timezone('utc'::text, now())
);

-- B. lives (streaming rooms metadata)
create table public.lives (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text not null unique,
  creator_id uuid not null references public.users(id) on delete cascade,
  status text not null check (status in ('idle', 'live', 'ended')) default 'idle',
  started_at timestamp with time zone,
  ended_at timestamp with time zone,
  max_viewers integer not null default 0,
  current_viewers integer not null default 0,
  created_at timestamp with time zone not null default timezone('utc'::text, now())
);

-- C. viewers (real-time stream viewer sessions)
create table public.viewers (
  id uuid primary key default gen_random_uuid(),
  live_id uuid not null references public.lives(id) on delete cascade,
  ip_address text,
  joined_at timestamp with time zone not null default timezone('utc'::text, now()),
  left_at timestamp with time zone
);

-- D. audit_logs (administrative actions history)
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete set null,
  action text not null,
  created_at timestamp with time zone not null default timezone('utc'::text, now())
);

-- ==========================================
-- 2. HELPER FUNCTIONS
-- ==========================================

-- Function to check if a user is an active administrator
create or replace function public.is_admin(user_id uuid)
returns boolean as $$
begin
  return exists (
    select 1 from public.users
    where id = user_id and role = 'admin' and active = true
  );
end;
$$ language plpgsql security definer;

-- ==========================================
-- 3. TRIGGERS FOR DATA SYNC & AUTOMATION
-- ==========================================

-- Trigger: Automatically sync auth.users with public.users on sign-up / account creation
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, name, email, role, active)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', 'Usuário LiveLink'),
    new.email,
    coalesce(new.raw_user_meta_data->>'role', 'broadcaster'),
    coalesce((new.raw_user_meta_data->>'active')::boolean, true)
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Trigger: Automatically update viewers count in lives table
create or replace function public.handle_viewer_change()
returns trigger as $$
begin
  if (TG_OP = 'INSERT') then
    update public.lives
    set current_viewers = current_viewers + 1,
        max_viewers = greatest(max_viewers, current_viewers + 1)
    where id = new.live_id;
  elsif (TG_OP = 'UPDATE') then
    if (old.left_at is null and new.left_at is not null) then
      update public.lives
      set current_viewers = greatest(0, current_viewers - 1)
      where id = new.live_id;
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger on_viewer_change
  after insert or update on public.viewers
  for each row execute procedure public.handle_viewer_change();

-- Trigger: Automatically audit live state changes (creation, status update)
create or replace function public.handle_live_audit()
returns trigger as $$
begin
  if (TG_OP = 'INSERT') then
    insert into public.audit_logs (user_id, action)
    values (new.creator_id, 'Criou a transmissão: ' || new.title || ' (Slug: ' || new.slug || ')');
  elsif (TG_OP = 'UPDATE') then
    if (old.status != new.status) then
      insert into public.audit_logs (user_id, action)
      values (new.creator_id, 'Alterou status da transmissão "' || new.title || '" para "' || new.status || '"');
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger on_live_audit
  after insert or update on public.lives
  for each row execute procedure public.handle_live_audit();

-- ==========================================
-- 4. ROW LEVEL SECURITY (RLS) POLICIES
-- ==========================================

-- Enable Row Level Security on all tables
alter table public.users enable row level security;
alter table public.lives enable row level security;
alter table public.viewers enable row level security;
alter table public.audit_logs enable row level security;

-- A. Policies for public.users
create policy "Admins can do everything on users"
  on public.users for all
  to authenticated
  using (public.is_admin(auth.uid()));

create policy "Users can view their own profile"
  on public.users for select
  to authenticated
  using (auth.uid() = id);

create policy "Users can update their own profile"
  on public.users for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- B. Policies for public.lives
create policy "Admins can do everything on lives"
  on public.lives for all
  to authenticated
  using (public.is_admin(auth.uid()));

create policy "Broadcasters can view their own lives"
  on public.lives for select
  to authenticated
  using (auth.uid() = creator_id);

create policy "Broadcasters can create lives"
  on public.lives for insert
  to authenticated
  with check (
    auth.uid() = creator_id 
    and exists (
      select 1 from public.users 
      where id = auth.uid() and role = 'broadcaster' and active = true
    )
  );

create policy "Broadcasters can update their own lives"
  on public.lives for update
  to authenticated
  using (auth.uid() = creator_id)
  with check (auth.uid() = creator_id);

create policy "Broadcasters can delete their own lives"
  on public.lives for delete
  to authenticated
  using (auth.uid() = creator_id);

create policy "Anyone can view active or finished lives"
  on public.lives for select
  to anon, authenticated
  using (status in ('live', 'ended'));

-- C. Policies for public.viewers
create policy "Admins can do everything on viewers"
  on public.viewers for all
  to authenticated
  using (public.is_admin(auth.uid()));

create policy "Anyone can insert viewer records"
  on public.viewers for insert
  to anon, authenticated
  with check (true);

create policy "Anyone can update viewer records"
  on public.viewers for update
  to anon, authenticated
  using (true)
  with check (true);

create policy "Broadcasters can view viewers of their own lives"
  on public.viewers for select
  to authenticated
  using (
    exists (
      select 1 from public.lives
      where lives.id = viewers.live_id
      and (lives.creator_id = auth.uid())
    )
  );

-- D. Policies for public.audit_logs
create policy "Admins can view all audit logs"
  on public.audit_logs for select
  to authenticated
  using (public.is_admin(auth.uid()));

create policy "Users can write audit logs for themselves"
  on public.audit_logs for insert
  to authenticated
  with check (auth.uid() = user_id);
