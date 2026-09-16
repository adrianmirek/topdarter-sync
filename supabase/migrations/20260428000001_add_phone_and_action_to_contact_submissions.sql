-- Add phone and action columns to topdarter.contact_submissions
-- phone   – optional phone number provided by the submitter
-- action  – discriminator: 'Contact' for regular enquiries,
--           'save certificate' for certificate order requests
ALTER TABLE topdarter.contact_submissions
  ADD COLUMN IF NOT EXISTS phone  TEXT,
  ADD COLUMN IF NOT EXISTS action TEXT NOT NULL DEFAULT 'Contact';
