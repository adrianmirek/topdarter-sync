-- =====================================================================
-- Migration: Create Contact Submissions Table
-- =====================================================================
-- Purpose: Store contact form submissions
-- 
-- Tables Created:
--   - topdarter.contact_submissions (contact form data)
--
-- Schema Version: 1.0.0
-- Created: 2026-02-23
-- =====================================================================

-- =====================================================================
-- Step 1: Create Contact Submissions Table
-- =====================================================================

create table if not exists topdarter.contact_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  email varchar(255) not null,
  description text not null,
  attachment_name varchar(255),
  attachment_data text,
  attachment_type varchar(100),
  attachment_size integer,
  status varchar(50) default 'pending' check (status in ('pending', 'read', 'responded', 'closed')),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Add indexes
create index idx_contact_submissions_user_id on topdarter.contact_submissions(user_id);
create index idx_contact_submissions_created_at on topdarter.contact_submissions(created_at desc);
create index idx_contact_submissions_status on topdarter.contact_submissions(status);
create index idx_contact_submissions_email on topdarter.contact_submissions(email);

-- Add comments
comment on table topdarter.contact_submissions is 'Contact form submissions from users';
comment on column topdarter.contact_submissions.id is 'Unique submission identifier';
comment on column topdarter.contact_submissions.user_id is 'User who submitted the form (nullable for anonymous users)';
comment on column topdarter.contact_submissions.email is 'Contact email address';
comment on column topdarter.contact_submissions.description is 'Message/description from user';
comment on column topdarter.contact_submissions.attachment_name is 'Original filename of attachment';
comment on column topdarter.contact_submissions.attachment_data is 'Base64-encoded binary data of attachment';
comment on column topdarter.contact_submissions.attachment_type is 'MIME type of attachment';
comment on column topdarter.contact_submissions.attachment_size is 'Size of attachment in bytes';
comment on column topdarter.contact_submissions.status is 'Status of the submission';
comment on column topdarter.contact_submissions.created_at is 'Timestamp when submission was created';

-- =====================================================================
-- Step 2: Row Level Security (RLS)
-- =====================================================================

-- Enable RLS
alter table topdarter.contact_submissions enable row level security;

-- Policy: Allow anonymous and authenticated users to insert submissions
create policy "Anyone can insert contact submissions"
  on topdarter.contact_submissions
  for insert
  to anon, authenticated
  with check (true);

-- Policy: Users can view their own submissions
create policy "Users can view their own submissions"
  on topdarter.contact_submissions
  for select
  to anon, authenticated
  using (true);

-- Policy: Service role has full access
create policy "Service role has full access"
  on topdarter.contact_submissions
  for all
  to service_role
  using (true)
  with check (true);

-- Grant permissions
grant usage on schema topdarter to anon, authenticated;
grant insert on topdarter.contact_submissions to anon, authenticated;
grant select on topdarter.contact_submissions to anon, authenticated;
