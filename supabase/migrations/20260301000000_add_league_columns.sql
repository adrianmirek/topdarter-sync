-- =====================================================================
-- Migration: Add League Support Columns
-- Purpose: Add IsLeague flag to keywords and LeagueIdentifier to tournaments
-- Date: 2026-03-01
-- =====================================================================

-- Step 1: Add IsLeague column to nakka.keyword table
-- This column indicates whether a keyword represents a league
ALTER TABLE nakka.keyword
ADD COLUMN is_league BOOLEAN NOT NULL DEFAULT FALSE;

-- Step 2: Add LeagueIdentifier column to nakka.tournaments table
-- This column stores the league identifier for tournaments that are part of a league
ALTER TABLE nakka.tournaments
ADD COLUMN league_identifier TEXT DEFAULT NULL;

-- Step 3: Add comments for documentation
COMMENT ON COLUMN nakka.keyword.is_league IS 'Flag indicating whether this keyword represents a league (TRUE) or a regular tournament (FALSE)';
COMMENT ON COLUMN nakka.tournaments.league_identifier IS 'Identifier for the league this tournament belongs to (NULL if not part of a league)';

-- Step 4: Create index on league_identifier for faster lookups
CREATE INDEX IF NOT EXISTS idx_nakka_tournaments_league_identifier 
  ON nakka.tournaments (league_identifier) 
  WHERE league_identifier IS NOT NULL;

-- Step 5: Create index on is_league for filtering
CREATE INDEX IF NOT EXISTS idx_nakka_keyword_is_league 
  ON nakka.keyword (is_league);

-- Note: Existing rows will automatically have:
-- - is_league set to FALSE (0) due to the DEFAULT FALSE constraint
-- - league_identifier set to NULL due to the DEFAULT NULL constraint
