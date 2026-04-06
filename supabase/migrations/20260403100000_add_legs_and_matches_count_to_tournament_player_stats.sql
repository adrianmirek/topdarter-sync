-- =====================================================================
-- Migration: Add legs_count and matches_count to tournament_player_stats
-- Purpose: Track the number of legs and matches played per player
--          per tournament, imported from the Nakka platform.
-- Date: 2026-04-03
-- =====================================================================

ALTER TABLE nakka.tournament_player_stats
  ADD COLUMN IF NOT EXISTS legs_count    INTEGER NOT NULL DEFAULT 0 CHECK (legs_count >= 0),
  ADD COLUMN IF NOT EXISTS matches_count INTEGER NOT NULL DEFAULT 0 CHECK (matches_count >= 0);

COMMENT ON COLUMN nakka.tournament_player_stats.legs_count IS
'Total number of legs played by the player in this tournament.';

COMMENT ON COLUMN nakka.tournament_player_stats.matches_count IS
'Total number of matches played by the player in this tournament.';
