-- =====================================================================
-- Migration: Add Certificate Columns to nakka.tournament_player_stats
-- Purpose: Store per-player generated certificate data
-- Date: 2026-04-26
-- =====================================================================

ALTER TABLE nakka.tournament_player_stats
  ADD COLUMN IF NOT EXISTS player_certificate_path            TEXT,
  ADD COLUMN IF NOT EXISTS player_certificate_watermark_path  TEXT,
  ADD COLUMN IF NOT EXISTS player_contact_number              TEXT,
  ADD COLUMN IF NOT EXISTS certificate_code                   TEXT UNIQUE;

COMMENT ON COLUMN nakka.tournament_player_stats.player_certificate_path IS
'Path to the AI-generated certificate image for this player (certificates/players/{tournament_id}/{player_id}/certificate.webp). Reserved for future ordering feature.';

COMMENT ON COLUMN nakka.tournament_player_stats.player_certificate_watermark_path IS
'Path to the watermarked/protected version of the player certificate (certificates/players/{tournament_id}/{player_id}/watermarked.webp). Set during generation.';

COMMENT ON COLUMN nakka.tournament_player_stats.player_contact_number IS
'Player contact info (phone number or email). Reserved for future ordering feature — not collected during certificate generation.';

COMMENT ON COLUMN nakka.tournament_player_stats.certificate_code IS
'Unique verification code assigned at certificate generation time (UUID-based). Embedded on the certificate for authenticity checks.';

-- Index for fast certificate lookup by code
CREATE UNIQUE INDEX IF NOT EXISTS idx_tournament_player_stats_certificate_code
  ON nakka.tournament_player_stats (certificate_code)
  WHERE certificate_code IS NOT NULL;
