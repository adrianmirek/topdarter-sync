-- Add ordered_certificate_code to nakka.tournament_player_stats
-- This column stores an admin-assigned code that a player can use to generate
-- a full (no-watermark) certificate.
ALTER TABLE nakka.tournament_player_stats
  ADD COLUMN IF NOT EXISTS ordered_certificate_code TEXT;
