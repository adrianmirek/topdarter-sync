-- =====================================================================
-- Migration: Create Rating Table
-- =====================================================================
-- Purpose: Store user ratings for the app
-- 
-- Tables Created:
--   - topdarter.rating (user ratings with 1-5 stars)
--
-- Schema Version: 1.0.0
-- Created: 2026-02-23
-- =====================================================================

-- =====================================================================
-- Step 1: Create Rating Table
-- =====================================================================

create table if not exists topdarter.rating (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  score smallint not null check (score >= 1 and score <= 5),
  comment text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Add indexes
create index idx_rating_user_id on topdarter.rating(user_id);
create index idx_rating_created_at on topdarter.rating(created_at desc);
create index idx_rating_score on topdarter.rating(score);

-- Add comments
comment on table topdarter.rating is 'User ratings for the app';
comment on column topdarter.rating.id is 'Unique rating identifier';
comment on column topdarter.rating.user_id is 'User who submitted the rating (nullable for anonymous users)';
comment on column topdarter.rating.score is 'Rating score from 1 to 5 stars';
comment on column topdarter.rating.comment is 'Optional comment from the user';
comment on column topdarter.rating.created_at is 'Timestamp when rating was created';

-- =====================================================================
-- Step 2: Row Level Security (RLS)
-- =====================================================================

-- Enable RLS
alter table topdarter.rating enable row level security;

-- Policy: Allow anonymous and authenticated users to insert ratings
create policy "Anyone can insert ratings"
  on topdarter.rating
  for insert
  to anon, authenticated
  with check (true);

-- Policy: Users can view their own ratings
create policy "Users can view their own ratings"
  on topdarter.rating
  for select
  to anon, authenticated
  using (true);

-- Policy: Admin access (if needed)
create policy "Service role has full access"
  on topdarter.rating
  for all
  to service_role
  using (true)
  with check (true);

-- Grant permissions
grant usage on schema topdarter to anon, authenticated;
grant insert on topdarter.rating to anon, authenticated;
grant select on topdarter.rating to anon, authenticated;
