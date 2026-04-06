-- Migration: Optimize player search performance
-- Date: 2026-03-02
-- Description: Add indexes and optimize get_player_matches_by_nickname function
--              to prevent timeout issues when searching for player matches.
--              Key additions:
--              - Pre-normalized name columns eliminate 72k normalize_polish_text() calls per request
--              - Pre-computed match_identifier_prefix eliminates per-row REGEXP_REPLACE in JOIN conditions

-- =====================================================================
-- PART 1: Pre-normalize player names (stored computed columns)
-- =====================================================================

-- pg_trgm must exist before any gin_trgm_ops index is created
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Add stored computed columns so the function never calls normalize_polish_text()
-- or REGEXP_REPLACE() per row at query time.
ALTER TABLE nakka.tournament_matches
  ADD COLUMN IF NOT EXISTS first_player_name_norm    TEXT,
  ADD COLUMN IF NOT EXISTS second_player_name_norm   TEXT,
  ADD COLUMN IF NOT EXISTS match_identifier_prefix   TEXT;

-- Back-fill computed values for existing rows
UPDATE nakka.tournament_matches
SET
  first_player_name_norm  = nakka.normalize_polish_text(first_player_name),
  second_player_name_norm = nakka.normalize_polish_text(second_player_name),
  match_identifier_prefix = REGEXP_REPLACE(nakka_match_identifier, '_[^_]+_[^_]+$', '');

-- Keep all computed columns in sync automatically
CREATE OR REPLACE FUNCTION nakka.trg_normalize_player_names()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.first_player_name_norm  := nakka.normalize_polish_text(NEW.first_player_name);
  NEW.second_player_name_norm := nakka.normalize_polish_text(NEW.second_player_name);
  NEW.match_identifier_prefix := REGEXP_REPLACE(NEW.nakka_match_identifier, '_[^_]+_[^_]+$', '');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_player_names ON nakka.tournament_matches;
CREATE TRIGGER trg_normalize_player_names
  BEFORE INSERT OR UPDATE OF first_player_name, second_player_name, nakka_match_identifier
  ON nakka.tournament_matches
  FOR EACH ROW EXECUTE FUNCTION nakka.trg_normalize_player_names();

-- GIN trigram indexes on normalized columns - used by the pre-filter WHERE
-- and the precise LIKE matching in the function below
CREATE INDEX IF NOT EXISTS idx_tm_first_player_norm_trgm
  ON nakka.tournament_matches
  USING gin (first_player_name_norm gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_tm_second_player_norm_trgm
  ON nakka.tournament_matches
  USING gin (second_player_name_norm gin_trgm_ops);

-- Add comments
COMMENT ON COLUMN nakka.tournament_matches.first_player_name_norm IS
'Pre-computed normalize_polish_text(first_player_name). Maintained by trg_normalize_player_names.';
COMMENT ON COLUMN nakka.tournament_matches.second_player_name_norm IS
'Pre-computed normalize_polish_text(second_player_name). Maintained by trg_normalize_player_names.';
COMMENT ON COLUMN nakka.tournament_matches.match_identifier_prefix IS
'Pre-computed REGEXP_REPLACE(nakka_match_identifier, ''_[^_]+_[^_]+$'', ''''). Maintained by trg_normalize_player_names. Used in player-result JOIN conditions to avoid per-row regex.';
COMMENT ON INDEX nakka.idx_tm_first_player_norm_trgm IS
'Trigram GIN index on normalized first player name - enables indexed LIKE pattern matching without per-row normalization calls';
COMMENT ON INDEX nakka.idx_tm_second_player_norm_trgm IS
'Trigram GIN index on normalized second player name - enables indexed LIKE pattern matching without per-row normalization calls';


-- =====================================================================
-- PART 2: Add indexes for player name searches
-- =====================================================================

-- Create trigram (GIN) indexes for LIKE/ILIKE pattern matching on raw names
-- These are used by the word_boundary_match path (non-combined names)
CREATE INDEX IF NOT EXISTS idx_tm_first_player_trgm 
  ON nakka.tournament_matches 
  USING gin (first_player_name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_tm_second_player_trgm 
  ON nakka.tournament_matches 
  USING gin (second_player_name gin_trgm_ops);

-- Create standard B-tree indexes for exact matches and word boundary searches
CREATE INDEX IF NOT EXISTS idx_tournament_matches_first_player_name 
  ON nakka.tournament_matches(first_player_name);

CREATE INDEX IF NOT EXISTS idx_tournament_matches_second_player_name 
  ON nakka.tournament_matches(second_player_name);

-- Create composite index for date-based sorting (most common query pattern)
CREATE INDEX IF NOT EXISTS idx_tournament_matches_dates 
  ON nakka.tournament_matches(tournament_id, imported_at DESC);

-- Add comments
COMMENT ON INDEX nakka.idx_tm_first_player_trgm IS 
'Trigram GIN index on first player name - enables indexed %LIKE% pattern matching';
COMMENT ON INDEX nakka.idx_tm_second_player_trgm IS 
'Trigram GIN index on second player name - enables indexed %LIKE% pattern matching';
COMMENT ON INDEX nakka.idx_tournament_matches_first_player_name IS 
'B-tree index on first player name for exact matches and word boundary searches';
COMMENT ON INDEX nakka.idx_tournament_matches_second_player_name IS 
'B-tree index on second player name for exact matches and word boundary searches';
COMMENT ON INDEX nakka.idx_tournament_matches_dates IS 
'Composite index for efficient date-based sorting in match queries';


-- =====================================================================
-- PART 3: Optimize get_player_matches_by_nickname function
-- =====================================================================

-- Drop existing function
DROP FUNCTION IF EXISTS nakka.get_player_matches_by_nickname(TEXT[], INTEGER) CASCADE;

-- Recreate function with optimized query logic
-- Changed to VOLATILE to allow timeout configuration
CREATE OR REPLACE FUNCTION nakka.get_player_matches_by_nickname(
  search_nicknames TEXT[],
  match_limit INTEGER DEFAULT 30
)
RETURNS SETOF nakka.player_match_result
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
AS $$
DECLARE
  v_old_timeout TEXT;
BEGIN
  -- Validate input: ensure array is not empty
  IF search_nicknames IS NULL OR array_length(search_nicknames, 1) IS NULL THEN
    RAISE EXCEPTION 'search_nicknames array cannot be empty';
  END IF;

  -- Save current timeout and set to 60 seconds
  SELECT current_setting('statement_timeout') INTO v_old_timeout;
  EXECUTE 'SET LOCAL statement_timeout = ''60s''';

  RETURN QUERY
  WITH 
  -- Step 1: Normalize input nicknames once — never per-row
  search_terms AS (
    SELECT
      nickname,
      nakka.normalize_polish_text(nickname) AS nickname_norm
    FROM unnest(search_nicknames) AS nickname
  ),
  -- Step 2: CHEAP pre-filter + early LIMIT
  --   Uses only GIN trigram indexes (no word_boundary_match, no stats JOINs).
  --   Joins tournaments solely to obtain the sort key (tournament_date).
  --   Over-fetches by 5× so that precise filtering in Step 3 still yields
  --   match_limit results in the common case.
  candidates AS (
    SELECT
      tm.tournament_match_id,
      tm.tournament_id,
      tm.nakka_match_identifier,
      tm.match_type,
      tm.href,
      tm.match_date,
      tm.first_player_name,
      tm.first_player_code,
      tm.second_player_name,
      tm.second_player_code,
      tm.match_identifier_prefix,
      tm.first_player_name_norm,
      tm.second_player_name_norm,
      tm.imported_at,
      t.tournament_date,
      t.nakka_identifier AS nakka_tournament_identifier,
      t.tournament_name,
      t.href             AS tournament_href
    FROM nakka.tournament_matches tm
    INNER JOIN nakka.tournaments t ON tm.tournament_id = t.tournament_id
    WHERE EXISTS (
        SELECT 1
        FROM search_terms st
        WHERE
            tm.first_player_name       ILIKE '%' || st.nickname      || '%'
         OR tm.second_player_name      ILIKE '%' || st.nickname      || '%'
         OR tm.first_player_name_norm  LIKE  '%' || st.nickname_norm || '%'
         OR tm.second_player_name_norm LIKE  '%' || st.nickname_norm || '%'
    )
    ORDER BY t.tournament_date DESC, tm.match_date DESC, tm.tournament_match_id DESC
    LIMIT match_limit * 5
  ),
  -- Step 3: Precise match flags — runs ONLY on the small candidate set, not the full table
  --   - Simple names  → word_boundary_match on raw columns
  --   - Combined names → LIKE on pre-normalized columns (no normalize_polish_text call)
  matching_matches AS (
    SELECT
      c.*,
      EXISTS (
        SELECT 1 FROM search_terms st
        WHERE (
          CASE 
            WHEN st.nickname NOT LIKE '%/%' AND st.nickname NOT LIKE '%\%' THEN
              nakka.word_boundary_match(c.first_player_name, st.nickname)
              AND c.first_player_name NOT LIKE '%/%'
              AND c.first_player_name NOT LIKE '%\%'
            ELSE
              c.first_player_name_norm LIKE '%' || st.nickname_norm || '%'
          END
        )
      ) AS first_player_matches,
      EXISTS (
        SELECT 1 FROM search_terms st
        WHERE (
          CASE 
            WHEN st.nickname NOT LIKE '%/%' AND st.nickname NOT LIKE '%\%' THEN
              nakka.word_boundary_match(c.second_player_name, st.nickname)
              AND c.second_player_name NOT LIKE '%/%'
              AND c.second_player_name NOT LIKE '%\%'
            ELSE
              c.second_player_name_norm LIKE '%' || st.nickname_norm || '%'
          END
        )
      ) AS second_player_matches
    FROM candidates c
  ),
  -- Step 4: Determine player roles and apply final LIMIT
  --   Stats JOINs (tournament_match_player_results) happen AFTER this, on ≤30 rows only
  match_data AS (
    SELECT
      mm.tournament_id,
      mm.nakka_tournament_identifier,
      mm.tournament_name,
      mm.tournament_date,
      mm.tournament_href,
      mm.tournament_match_id,
      mm.nakka_match_identifier,
      mm.match_type,
      mm.href AS match_href,
      mm.match_date,
      CASE
        WHEN mm.second_player_matches AND NOT mm.first_player_matches
        THEN mm.second_player_name
        ELSE mm.first_player_name
      END AS player_name,
      CASE
        WHEN mm.second_player_matches AND NOT mm.first_player_matches
        THEN mm.second_player_code
        ELSE mm.first_player_code
      END AS player_code,
      CASE
        WHEN mm.second_player_matches AND NOT mm.first_player_matches
        THEN mm.first_player_name
        ELSE mm.second_player_name
      END AS opponent_name,
      CASE
        WHEN mm.second_player_matches AND NOT mm.first_player_matches
        THEN mm.first_player_code
        ELSE mm.second_player_code
      END AS opponent_code,
      mm.match_identifier_prefix,
      mm.imported_at
    FROM matching_matches mm
    WHERE mm.first_player_matches OR mm.second_player_matches
    ORDER BY mm.tournament_date DESC, mm.match_date DESC, mm.tournament_match_id DESC
    LIMIT match_limit
  )
  SELECT 
    md.tournament_id,
    md.nakka_tournament_identifier,
    md.tournament_name,
    md.tournament_date,
    md.tournament_href,
    md.tournament_match_id,
    md.nakka_match_identifier,
    md.match_type,
    md.match_href,
    md.match_date,
    md.player_name,
    md.player_code,
    md.opponent_name,
    md.opponent_code,
    
    -- Player statistics
    pr.average_score,
    pr.first_nine_avg,
    pr.checkout_percentage,
    pr.score_60_count,
    pr.score_100_count,
    pr.score_140_count,
    pr.score_180_count,
    pr.high_finish,
    pr.best_leg,
    pr.worst_leg,
    pr.player_score,
    pr.opponent_score,
    
    -- Opponent statistics
    opr.average_score AS opponent_average_score,
    opr.first_nine_avg AS opponent_first_nine_avg,
    opr.checkout_percentage AS opponent_checkout_percentage,
    opr.score_60_count AS opponent_score_60_count,
    opr.score_100_count AS opponent_score_100_count,
    opr.score_140_count AS opponent_score_140_count,
    opr.score_180_count AS opponent_score_180_count,
    opr.high_finish AS opponent_high_finish,
    opr.best_leg AS opponent_best_leg,
    opr.worst_leg AS opponent_worst_leg,
    
    md.imported_at
    
  FROM match_data md
  LEFT JOIN nakka.tournament_match_player_results pr 
    ON pr.tournament_match_id = md.tournament_match_id
    AND pr.nakka_match_player_identifier = md.match_identifier_prefix || '_' || md.player_code
  LEFT JOIN nakka.tournament_match_player_results opr 
    ON opr.tournament_match_id = md.tournament_match_id
    AND opr.nakka_match_player_identifier = md.match_identifier_prefix || '_' || md.opponent_code
  ORDER BY md.tournament_date DESC, md.match_date DESC, md.tournament_match_id DESC;
END;
$$;

-- Grant execute permission to authenticated and anon roles
GRANT EXECUTE ON FUNCTION nakka.get_player_matches_by_nickname(TEXT[], INTEGER) TO authenticated, anon;

-- Add comments
COMMENT ON FUNCTION nakka.get_player_matches_by_nickname(TEXT[], INTEGER) IS 
'Retrieves player matches by nickname(s) from the database using word boundary matching.
Highly optimized version with 60-second statement timeout and indexed queries.
Key Improvements:
- Early LIMIT: GIN trigram pre-filter + tournament sort key + LIMIT(5×) before any word_boundary_match
- Pre-normalized columns (first/second_player_name_norm) eliminate per-row normalization calls
- Pre-computed match_identifier_prefix eliminates per-row REGEXP_REPLACE in JOIN conditions
- GIN trigram indexes on both raw and normalized columns for fast pre-filtering
- search_terms CTE pre-computes normalized nicknames once (not per row)
- Stats JOINs (tournament_match_player_results) run on ≤match_limit rows only
- Added indexes on player name columns for faster searches
- Changed to VOLATILE function to allow proper timeout configuration
- Set statement timeout to 60 seconds via EXECUTE
Query Optimization Strategy:
1. search_terms CTE: normalize input nicknames once — never repeated per row
2. candidates CTE: GIN trigram pre-filter + tournament JOIN for sort key + ORDER + LIMIT (5×) early
   → word_boundary_match is NOT called here; only cheap index lookups
3. matching_matches CTE: precise word-boundary / normalize flags on the small candidate set only
4. match_data CTE: filter confirmed matches + final LIMIT
5. Final SELECT: LEFT JOIN tournament_match_player_results × 2 on ≤30 rows only
This ordering ensures:
- The table is scanned once, narrowed by GIN indexes
- word_boundary_match runs on ≤(match_limit×5) rows, not the full filtered set
- Stats JOINs run on ≤match_limit rows only (never on the full match set)
Uses word boundary matching to prevent partial word matches:
- "ski" matches "John Ski" but NOT "Walkowski", "Ossowski", "Polski"
- "Kowalski" matches "Jan Kowalski" exactly
- "Kowal" does NOT match "Jan Kowalski" (partial word)
Handles combined player names intelligently (names with / or \ separators):
- When searching for individual names (e.g., "Sebastian Szymkowiak"), excludes combined names
- When searching for combined names (e.g., "Mateusz Obroszko/Sebastian Szymkowiak"), uses substring matching
- Returns matches ordered by tournament date (newest first)
- Includes player and opponent statistics when available';


-- =====================================================================
-- PART 4: Verify timeout configuration
-- =====================================================================

-- Show current statement_timeout setting
-- This is for verification purposes
DO $$
DECLARE
  current_timeout TEXT;
BEGIN
  SELECT setting INTO current_timeout 
  FROM pg_settings 
  WHERE name = 'statement_timeout';
  
  RAISE NOTICE 'Current statement_timeout: % ms', current_timeout;
END;
$$;
