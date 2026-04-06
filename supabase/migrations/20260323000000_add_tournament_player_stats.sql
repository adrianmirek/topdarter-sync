-- =====================================================================
-- Migration: Add Tournament Player Stats Table and Sync Stats Flag
-- Purpose: Store aggregated player statistics per tournament from Nakka platform
-- Date: 2026-03-23
-- =====================================================================

-- =====================================================================
-- PART 1: Add sync_stats column to nakka.tournaments
-- =====================================================================

ALTER TABLE nakka.tournaments
  ADD COLUMN IF NOT EXISTS sync_stats BOOLEAN NOT NULL DEFAULT FALSE;

-- Back-fill existing rows: mark them as already synced
UPDATE nakka.tournaments
  SET sync_stats = TRUE
  WHERE sync_stats = FALSE;

COMMENT ON COLUMN nakka.tournaments.sync_stats IS
'Indicates whether tournament player stats should be synced. FALSE = do not sync (default for new rows), TRUE = sync enabled (set for all pre-existing rows).';

-- =====================================================================
-- PART 2: Create nakka.tournament_player_stats table
-- =====================================================================

CREATE TABLE IF NOT EXISTS nakka.tournament_player_stats (
  -- Primary key
  tournament_player_stat_id SERIAL PRIMARY KEY,

  -- Foreign key to tournaments table
  tournament_id INTEGER NOT NULL
    REFERENCES nakka.tournaments(tournament_id) ON DELETE CASCADE,

  -- Player identifier on Nakka platform (e.g. "3JOu")
  player_id TEXT NOT NULL,

  -- Tournament ranking position (0 = not ranked / unknown)
  rank INTEGER NOT NULL DEFAULT 0 CHECK (rank >= 0),

  -- Scoring statistics
  score_100_count INTEGER NOT NULL DEFAULT 0 CHECK (score_100_count >= 0),
  score_140_count INTEGER NOT NULL DEFAULT 0 CHECK (score_140_count >= 0),
  score_170_count INTEGER NOT NULL DEFAULT 0 CHECK (score_170_count >= 0),
  score_180_count INTEGER NOT NULL DEFAULT 0 CHECK (score_180_count >= 0),

  -- Leg statistics
  high_finish    INTEGER NOT NULL DEFAULT 0 CHECK (high_finish >= 0),
  best_leg       INTEGER NOT NULL DEFAULT 0 CHECK (best_leg >= 0),

  -- Averages and rates
  average_score  NUMERIC(6,2),
  first_nine_avg NUMERIC(6,2),
  win_rate       NUMERIC(5,2),
  leg_rate       NUMERIC(5,2),

  -- Source URL for this player's stats page
  href TEXT,

  -- Import metadata
  imported_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- NULL means import succeeded; a non-NULL value contains the error message
  import_error TEXT,

  -- Prevent duplicate entries for the same player in the same tournament
  CONSTRAINT unique_tournament_player_stat UNIQUE (tournament_id, player_id)
);

-- =====================================================================
-- PART 3: Indexes
-- =====================================================================

CREATE INDEX IF NOT EXISTS idx_tournament_player_stats_tournament_id
  ON nakka.tournament_player_stats (tournament_id);

CREATE INDEX IF NOT EXISTS idx_tournament_player_stats_player_id
  ON nakka.tournament_player_stats (player_id);

CREATE INDEX IF NOT EXISTS idx_tournament_player_stats_import_error
  ON nakka.tournament_player_stats (import_error)
  WHERE import_error IS NOT NULL;

-- =====================================================================
-- PART 4: Comments
-- =====================================================================

COMMENT ON TABLE nakka.tournament_player_stats IS
'Stores aggregated player statistics per tournament imported from the Nakka 01 platform (n01darts.com).';

COMMENT ON COLUMN nakka.tournament_player_stats.player_id IS
'Nakka platform player identifier (e.g. "3JOu"). Not a FK — players are not stored in a dedicated table.';

COMMENT ON COLUMN nakka.tournament_player_stats.rank IS
'Player finishing rank in the tournament. 0 indicates the rank is unknown or not yet imported.';

COMMENT ON COLUMN nakka.tournament_player_stats.import_error IS
'NULL when the row was imported successfully. A non-NULL value stores the error message from a failed import attempt.';

COMMENT ON COLUMN nakka.tournament_player_stats.last_updated IS
'Timestamp of the most recent update to this row (set manually or via trigger on future updates).';

-- =====================================================================
-- PART 5: Grant permissions
-- =====================================================================

GRANT SELECT, INSERT, UPDATE ON nakka.tournament_player_stats TO authenticated;
GRANT SELECT, INSERT, UPDATE ON nakka.tournament_player_stats TO anon;

-- Grant on the sequence (name is auto-derived by PostgreSQL; use dynamic lookup to be safe)
DO $$
DECLARE
  seq_name TEXT;
BEGIN
  SELECT pg_get_serial_sequence('nakka.tournament_player_stats', 'tournament_player_stat_id')
    INTO seq_name;
  IF seq_name IS NOT NULL THEN
    EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO authenticated', seq_name);
  END IF;
END $$;

DO $$
DECLARE
  seq_name TEXT;
BEGIN
  SELECT pg_get_serial_sequence('nakka.tournament_player_stats', 'tournament_player_stat_id')
    INTO seq_name;
  IF seq_name IS NOT NULL THEN
    EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO anon', seq_name);
  END IF;
END $$;
