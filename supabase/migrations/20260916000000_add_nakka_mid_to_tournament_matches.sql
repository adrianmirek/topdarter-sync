-- =====================================================================
-- Migration: Add nakka_mid column to tournament_matches
-- Purpose: Store Nakka match mid and support exact-match lookups by mid
-- Date: 2026-09-16
-- =====================================================================

ALTER TABLE nakka.tournament_matches
ADD COLUMN IF NOT EXISTS nakka_mid TEXT;

-- Unique partial index: existing rows stay NULL; populated mids are unique
-- and can be looked up with an index-only equality search.
CREATE UNIQUE INDEX IF NOT EXISTS idx_tournament_matches_nakka_mid
  ON nakka.tournament_matches(nakka_mid)
  WHERE nakka_mid IS NOT NULL;

COMMENT ON COLUMN nakka.tournament_matches.nakka_mid IS
  'Nakka platform match mid from the match payload (e.g., iFLeTEwI_1789162367448). Primary lookup key for finding a match by mid.';

COMMENT ON INDEX nakka.idx_tournament_matches_nakka_mid IS
  'Unique btree on nakka_mid for exact-match searches. Partial so existing NULL rows are excluded.';
